import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../database/database_manager.dart';

class DatabasePatchApplyResult {
  final bool success;
  final String message;

  const DatabasePatchApplyResult._(this.success, this.message);

  factory DatabasePatchApplyResult.success(String message) =>
      DatabasePatchApplyResult._(true, message);

  factory DatabasePatchApplyResult.failure(String message) =>
      DatabasePatchApplyResult._(false, message);
}

class DatabasePatchApplier {
  final DatabaseManager _databaseManager = DatabaseManager();

  Future<DatabasePatchApplyResult> applySqlChangelogBundle({
    required String zipPath,
    required String targetDbFileName,
    required String baseVersion,
    required String targetVersion,
    required void Function(String message) onStatus,
    String? expectedZipSha256,
    CancelToken? cancelToken,
  }) async {
    try {
      _throwIfCancelled(cancelToken, zipPath);
      final zipFile = File(zipPath);
      if (!await zipFile.exists()) {
        return DatabasePatchApplyResult.failure('Patch bundle not found.');
      }

      if (expectedZipSha256 != null && expectedZipSha256.trim().isNotEmpty) {
        final actual = await _sha256ForFile(zipFile);
        if (actual.toLowerCase() != expectedZipSha256.trim().toLowerCase()) {
          return DatabasePatchApplyResult.failure(
            'Patch checksum mismatch. Expected $expectedZipSha256 but got $actual.',
          );
        }
      }

      onStatus('Verifying patch bundle...');
      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      final patchJsonEntry = archive.firstWhere(
        (entry) =>
            entry.isFile &&
            p.basename(entry.name).toLowerCase() == 'patch.json',
        orElse: () => throw StateError('Patch bundle missing patch.json'),
      );

      final patchJson =
          jsonDecode(utf8.decode(patchJsonEntry.content as List<int>))
              as Map<String, dynamic>;

      final patchTargetDbFileName =
          (patchJson['targetDbFileName'] ??
                  patchJson['databaseFileName'] ??
                  targetDbFileName)
              .toString()
              .trim();
      if (patchTargetDbFileName.isEmpty) {
        return DatabasePatchApplyResult.failure(
          'Patch bundle missing target DB filename.',
        );
      }

      final patchBaseVersion =
          (patchJson['fromVersion'] ?? patchJson['baseVersion'] ?? '')
              .toString()
              .trim();
      if (patchBaseVersion.isNotEmpty && patchBaseVersion != baseVersion) {
        return DatabasePatchApplyResult.failure(
          'Patch base version mismatch. Expected $baseVersion but bundle targets $patchBaseVersion.',
        );
      }

      final patchTargetVersion =
          (patchJson['toVersion'] ??
                  patchJson['targetVersion'] ??
                  targetVersion)
              .toString()
              .trim();

      final sqlStatements = _extractSqlStatements(archive, patchJson);
      if (sqlStatements.isEmpty) {
        return DatabasePatchApplyResult.failure(
          'Patch bundle has no SQL statements to apply.',
        );
      }

      _throwIfCancelled(cancelToken, zipPath);
      final dbPath = await _databaseManager.getDatabasePath(
        patchTargetDbFileName,
      );
      await _databaseManager.closeDatabase(patchTargetDbFileName);
      final backupPath = '$dbPath.patch_backup';
      final dbFile = File(dbPath);

      if (!await dbFile.exists()) {
        return DatabasePatchApplyResult.failure(
          'Target database file not found: $dbPath',
        );
      }

      await _copyFile(dbFile, File(backupPath));

      final database = await openDatabase(
        dbPath,
        singleInstance: false,
        readOnly: false,
      );

      try {
        onStatus('Applying patch to $patchTargetDbFileName...');
        await database.transaction((txn) async {
          for (final statement in sqlStatements) {
            _throwIfCancelled(cancelToken, zipPath);
            final normalized = statement.trim();
            if (normalized.isEmpty) continue;
            await txn.execute(normalized);
          }
          await _rebuildFts(txn, patchTargetDbFileName, patchJson);
          await txn.rawQuery('PRAGMA optimize');
        });

        await database.close();

        if (patchJson['postApplySha256'] is String &&
            (patchJson['postApplySha256'] as String).trim().isNotEmpty) {
          final expectedPost = (patchJson['postApplySha256'] as String).trim();
          final actualPost = await _sha256ForFile(File(dbPath));
          if (actualPost.toLowerCase() != expectedPost.toLowerCase()) {
            await _restoreBackup(backupPath, dbPath);
            return DatabasePatchApplyResult.failure(
              'Post-apply checksum mismatch for $patchTargetDbFileName.',
            );
          }
        }

        await _deleteBackup(backupPath);
        onStatus('Patch applied to $patchTargetDbFileName.');
        return DatabasePatchApplyResult.success(
          'Applied patch ${baseVersion} -> ${patchTargetVersion.isEmpty ? targetVersion : patchTargetVersion}.',
        );
      } catch (e, st) {
        debugPrint('DatabasePatchApplier error: $e\n$st');
        try {
          await database.close();
        } catch (_) {}
        await _restoreBackup(backupPath, dbPath);
        return DatabasePatchApplyResult.failure('Patch apply failed: $e');
      }
    } catch (e, st) {
      debugPrint('DatabasePatchApplier outer error: $e\n$st');
      return DatabasePatchApplyResult.failure('Patch bundle failed: $e');
    }
  }

  List<String> _extractSqlStatements(
    Archive archive,
    Map<String, dynamic> patchJson,
  ) {
    final statements = <String>[];

    final inlineStatements = patchJson['statements'];
    if (inlineStatements is List) {
      for (final entry in inlineStatements) {
        if (entry is String && entry.trim().isNotEmpty) {
          statements.add(entry);
        }
      }
    }

    final sqlFiles = patchJson['sqlFiles'];
    if (sqlFiles is List) {
      for (final entry in sqlFiles) {
        if (entry is! String) continue;
        final sqlEntry = archive.firstWhere(
          (item) => item.isFile && p.basename(item.name) == p.basename(entry),
          orElse: () => throw StateError('Patch SQL file not found: $entry'),
        );
        final content = utf8.decode(sqlEntry.content as List<int>);
        for (final part in _splitSqlScript(content)) {
          if (part.trim().isNotEmpty) {
            statements.add(part);
          }
        }
      }
    }

    return statements;
  }

  List<String> _splitSqlScript(String script) {
    final result = <String>[];
    final buffer = StringBuffer();
    var inSingleQuote = false;
    var inDoubleQuote = false;

    for (var i = 0; i < script.length; i++) {
      final ch = script[i];

      if (ch == "'" && !inDoubleQuote) {
        inSingleQuote = !inSingleQuote;
      } else if (ch == '"' && !inSingleQuote) {
        inDoubleQuote = !inDoubleQuote;
      }

      if (ch == ';' && !inSingleQuote && !inDoubleQuote) {
        final statement = buffer.toString().trim();
        if (statement.isNotEmpty) result.add(statement);
        buffer.clear();
        continue;
      }

      buffer.write(ch);
    }

    final tail = buffer.toString().trim();
    if (tail.isNotEmpty) result.add(tail);
    return result;
  }

  Future<void> _rebuildFts(
    Transaction txn,
    String targetDbFileName,
    Map<String, dynamic> patchJson,
  ) async {
    final contentType = (patchJson['contentType'] ?? patchJson['type'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final inferredType = _inferContentType(targetDbFileName, contentType);

    switch (inferredType) {
      case 'sermon':
        await txn.execute(
          "INSERT INTO sermon_fts(sermon_fts) VALUES('rebuild')",
        );
        break;
      case 'bible':
        await txn.execute("INSERT INTO bible_fts(bible_fts) VALUES('rebuild')");
        break;
      case 'cod':
        await txn.execute(
          "INSERT INTO questions_fts(questions_fts) VALUES('rebuild')",
        );
        await txn.execute(
          "INSERT INTO answers_fts(answers_fts) VALUES('rebuild')",
        );
        break;
      default:
        // Best effort only; some patch bundles may not need FTS rebuild.
        break;
    }
  }

  String _inferContentType(String targetDbFileName, String manifestType) {
    switch (manifestType) {
      case 'sermon':
      case 'bible':
      case 'cod':
        return manifestType;
    }

    final lower = targetDbFileName.toLowerCase();
    if (lower.contains('sermon')) return 'sermon';
    if (lower.contains('bible')) return 'bible';
    if (lower.contains('cod')) return 'cod';
    return '';
  }

  Future<String> _sha256ForFile(File file) async {
    final hash = await file.openRead().transform(sha256).first;
    return hash.toString();
  }

  Future<void> _copyFile(File source, File target) async {
    await target.parent.create(recursive: true);
    if (await target.exists()) {
      await target.delete();
    }
    await source.copy(target.path);
  }

  Future<void> _restoreBackup(String backupPath, String dbPath) async {
    final backup = File(backupPath);
    if (!await backup.exists()) return;
    await File(dbPath).delete().catchError((_) {});
    await backup.rename(dbPath);
    await _cleanupSidecars(dbPath);
  }

  Future<void> _deleteBackup(String backupPath) async {
    final backup = File(backupPath);
    if (await backup.exists()) {
      await backup.delete();
    }
  }

  Future<void> _cleanupSidecars(String dbPath) async {
    for (final suffix in ['-wal', '-shm', '-journal']) {
      final file = File('$dbPath$suffix');
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  void _throwIfCancelled(CancelToken? token, String path) {
    if (token?.isCancelled != true) return;
    throw DioException(
      requestOptions: RequestOptions(path: path),
      type: DioExceptionType.cancel,
      error: 'Patch apply cancelled by user.',
    );
  }
}
