import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sql;
import '../../../core/database/database_manager.dart';
import '../../../core/database/metadata/installed_database_model.dart';
import '../../../core/database/metadata/installed_database_registry.dart';

// ─── Result ──────────────────────────────────────────────────────────────────

class ImportResult {
  final bool success;
  final String message;
  const ImportResult._(this.success, this.message);
  factory ImportResult.success(String msg) => ImportResult._(true, msg);
  factory ImportResult.failure(String msg) => ImportResult._(false, msg);
}

// ─── Bible format detection ───────────────────────────────────────────────────

enum _BibleFormat { oldFormat, newFormat, invalid }

class _ValidationResult {
  final bool isValid;
  final String message;
  final _BibleFormat format;
  const _ValidationResult(this.isValid, this.message,
      [this.format = _BibleFormat.invalid]);
}

// ─── Importer ────────────────────────────────────────────────────────────────

/// Mirrors Android's SelectiveDatabaseImporter.
/// Validates source databases, copies them to canonical app-owned target paths,
/// ensures FTS5 tables are built, and registers metadata.
class SelectiveDatabaseImporter {
  final DatabaseManager _dbManager = DatabaseManager();
  final InstalledDatabaseRegistry _registry = InstalledDatabaseRegistry();

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Import a Bible database from [sourceFile] into the app.
  /// Target file: bible_<versionCode>.db
  Future<ImportResult> importBible({
    required File sourceFile,
    required String versionCode, // 'kjv' or 'bsi'
    required String displayName,
    required String language, // 'en' or 'ta'
    bool setAsDefault = true,
    required void Function(double, String) onProgress,
  }) async {
    try {
      onProgress(0.1, 'Validating Bible database...');
      final validation = _validateBible(sourceFile.path);
      if (!validation.isValid) {
        return ImportResult.failure(validation.message);
      }

      onProgress(0.3, 'Installing $displayName...');
      final dbDir = await _dbManager.getDatabaseDirectoryPath();
      final targetPath = p.join(dbDir.path, 'bible_$versionCode.db');

      await _dbManager.closeDatabase('bible_$versionCode.db');
      await _dbManager.deleteDatabaseFiles('bible_$versionCode.db');
      await sourceFile.copy(targetPath);

      onProgress(0.7, 'Building search index...');
      _ensureFts(targetPath, DbType.bible);

      onProgress(0.85, 'Updating metadata...');
      if (setAsDefault) {
        await _registry.clearDefaultForLanguage(DbType.bible, language);
      }
      await _registry.upsert(InstalledDatabase(
        type: DbType.bible,
        code: versionCode,
        displayName: displayName,
        language: language,
        installedDate: DateTime.now().millisecondsSinceEpoch,
        fileSize: File(targetPath).lengthSync(),
        isDefault: setAsDefault,
      ));

      onProgress(1.0, 'Import complete!');
      return ImportResult.success('$displayName installed successfully.');
    } catch (e, st) {
      debugPrint('importBible error: $e\n$st');
      return ImportResult.failure('Bible import failed: $e');
    }
  }

  /// Import a Sermon database from [sourceFile] into the app.
  /// Target file: sermons_<languageCode>.db
  Future<ImportResult> importSermons({
    required File sourceFile,
    required String languageCode, // 'en' or 'ta'
    required String displayName,
    bool setAsDefault = true,
    required void Function(double, String) onProgress,
  }) async {
    try {
      onProgress(0.1, 'Validating Sermon database...');
      if (!_validateSermon(sourceFile.path)) {
        return ImportResult.failure(
            'Invalid Sermon database: missing sermons or sermon_paragraphs table.');
      }

      onProgress(0.3, 'Installing $displayName...');
      final dbDir = await _dbManager.getDatabaseDirectoryPath();
      final targetPath = p.join(dbDir.path, 'sermons_$languageCode.db');

      await _dbManager.closeDatabase('sermons_$languageCode.db');
      await _dbManager.deleteDatabaseFiles('sermons_$languageCode.db');
      await sourceFile.copy(targetPath);

      onProgress(0.7, 'Building search index...');
      _ensureFts(targetPath, DbType.sermon);

      onProgress(0.85, 'Updating metadata...');
      if (setAsDefault) {
        await _registry.clearDefaultForLanguage(DbType.sermon, languageCode);
      }
      await _registry.upsert(InstalledDatabase(
        type: DbType.sermon,
        code: languageCode,
        displayName: displayName,
        language: languageCode,
        installedDate: DateTime.now().millisecondsSinceEpoch,
        fileSize: File(targetPath).lengthSync(),
        isDefault: setAsDefault,
      ));

      onProgress(1.0, 'Import complete!');
      return ImportResult.success('$displayName installed successfully.');
    } catch (e, st) {
      debugPrint('importSermons error: $e\n$st');
      return ImportResult.failure('Sermon import failed: $e');
    }
  }

  /// Import all databases from a unified ZIP file.
  /// Classifies each .db by filename — same rules as Android's importAllFromZip.
  Future<ImportResult> importAllFromZip({
    required String zipPath,
    required void Function(double, String) onProgress,
  }) async {
    try {
      onProgress(0.05, 'Reading ZIP file...');
      final zipFile = File(zipPath);
      if (!await zipFile.exists()) {
        return ImportResult.failure('ZIP file not found.');
      }

      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      final dbEntries =
          archive.where((f) => f.isFile && f.name.endsWith('.db')).toList();
      if (dbEntries.isEmpty) {
        return ImportResult.failure('No .db files found in archive.');
      }

      onProgress(0.1, 'Found ${dbEntries.length} database(s)...');

      final dbDir = await _dbManager.getDatabaseDirectoryPath();
      final results = <String>[];
      var imported = 0;
      var failed = 0;

      for (var i = 0; i < dbEntries.length; i++) {
        final entry = dbEntries[i];
        final fileName = p.basename(entry.name).toLowerCase();
        final baseProgress = 0.1 + (i / dbEntries.length) * 0.85;

        // Write to temp file for processing
        final tempPath = p.join(dbDir.path, 'import_temp_$i.db');
        final tempFile = File(tempPath);
        tempFile.writeAsBytesSync(entry.content as List<int>);

        try {
          final ImportResult result;

          // ── Classify by filename (same as Android SelectiveDatabaseImporter) ──
          if (fileName.contains('bible') &&
              (fileName.contains('_en') || fileName.contains('kjv'))) {
            onProgress(baseProgress, 'Importing English Bible...');
            result = await importBible(
              sourceFile: tempFile,
              versionCode: 'kjv',
              displayName: 'KJV Bible',
              language: 'en',
              setAsDefault: true,
              onProgress: (p, m) => onProgress(
                  baseProgress + p * (0.85 / dbEntries.length), m),
            );
          } else if (fileName.contains('bible') &&
              (fileName.contains('_ta') || fileName.contains('bsi'))) {
            onProgress(baseProgress, 'Importing Tamil Bible...');
            result = await importBible(
              sourceFile: tempFile,
              versionCode: 'bsi',
              displayName: 'BSI Tamil Bible',
              language: 'ta',
              setAsDefault: true,
              onProgress: (p, m) => onProgress(
                  baseProgress + p * (0.85 / dbEntries.length), m),
            );
          } else if (fileName.contains('sermon') &&
              fileName.contains('_en')) {
            onProgress(baseProgress, 'Importing English Sermons...');
            result = await importSermons(
              sourceFile: tempFile,
              languageCode: 'en',
              displayName: 'English Sermons',
              setAsDefault: true,
              onProgress: (p, m) => onProgress(
                  baseProgress + p * (0.85 / dbEntries.length), m),
            );
          } else if (fileName.contains('sermon') &&
              fileName.contains('_ta')) {
            onProgress(baseProgress, 'Importing Tamil Sermons...');
            result = await importSermons(
              sourceFile: tempFile,
              languageCode: 'ta',
              displayName: 'Tamil Sermons',
              setAsDefault: true,
              onProgress: (p, m) => onProgress(
                  baseProgress + p * (0.85 / dbEntries.length), m),
            );
          } else {
            debugPrint('Skipping unknown DB: ${entry.name}');
            results.add('Skipped: ${p.basename(entry.name)} (unknown type)');
            continue;
          }

          if (result.success) {
            imported++;
            results.add('✓ ${result.message}');
          } else {
            failed++;
            results.add('✗ ${p.basename(entry.name)}: ${result.message}');
          }
        } finally {
          if (await tempFile.exists()) await tempFile.delete();
        }
      }

      onProgress(1.0, 'Installation complete!');

      if (imported == 0) {
        return ImportResult.failure(
            'No databases installed.\n${results.join("\n")}');
      }
      if (failed == 0) {
        return ImportResult.success(
            'Successfully installed $imported database(s).\n${results.join("\n")}');
      }
      return ImportResult.success(
          'Installed $imported, failed $failed.\n${results.join("\n")}');
    } catch (e, st) {
      debugPrint('importAllFromZip error: $e\n$st');
      return ImportResult.failure('Import failed: $e');
    }
  }

  // ── Validation ───────────────────────────────────────────────────────────────

  _ValidationResult _validateBible(String dbPath) {
    try {
      final db = sql.sqlite3.open(dbPath, mode: sql.OpenMode.readOnly);
      try {
        final tables = db
            .select("SELECT name FROM sqlite_master WHERE type='table'")
            .map((r) => (r.columnAt(0) as String).toLowerCase())
            .toSet();

        if (tables.contains('bible_verses')) {
          final count = db.select('SELECT COUNT(*) FROM bible_verses');
          final n = count.isEmpty ? 0 : (count.first.columnAt(0) as int? ?? 0);
          if (n == 0) {
            return const _ValidationResult(false, 'Bible database is empty.');
          }
          return const _ValidationResult(true, 'OK', _BibleFormat.newFormat);
        }
        if (tables.contains('words')) {
          return const _ValidationResult(true, 'OK', _BibleFormat.oldFormat);
        }
        return const _ValidationResult(
            false, 'Not a valid Bible database (missing bible_verses / words).');
      } finally {
        db.close();
      }
    } catch (e) {
      return _ValidationResult(false, 'Validation error: $e');
    }
  }

  bool _validateSermon(String dbPath) {
    try {
      final db = sql.sqlite3.open(dbPath, mode: sql.OpenMode.readOnly);
      try {
        final tables = db
            .select("SELECT name FROM sqlite_master WHERE type='table'")
            .map((r) => (r.columnAt(0) as String).toLowerCase())
            .toSet();
        return tables.contains('sermons') &&
            tables.contains('sermon_paragraphs');
      } finally {
        db.close();
      }
    } catch (_) {
      return false;
    }
  }

  // ── FTS maintenance ──────────────────────────────────────────────────────────

  /// Ensures the correct FTS5 virtual table exists and is populated.
  /// If the table already has rows, only verifies; otherwise rebuilds.
  void _ensureFts(String dbPath, DbType type) {
    try {
      final db = sql.sqlite3.open(dbPath);
      try {
        if (type == DbType.bible) {
          _ensureBibleFts(db);
        } else {
          _ensureSermonFts(db);
        }
      } finally {
        db.close();
      }
    } catch (e) {
      debugPrint('_ensureFts($type) warning: $e');
    }
  }

  void _ensureBibleFts(sql.Database db) {
    // Create FTS5 table if absent
    db.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS bible_fts
      USING fts5(
        language, book, text,
        content=bible_verses,
        content_rowid=id,
        tokenize='unicode61'
      )
    ''');

    // Check if populated
    final check = db.select('SELECT COUNT(*) FROM bible_fts');
    final count = check.isEmpty ? 0 : (check.first.columnAt(0) as int? ?? 0);
    if (count == 0) {
      debugPrint('bible_fts empty — rebuilding from bible_verses...');
      db.execute(
        'INSERT INTO bible_fts(rowid, language, book, text) '
        'SELECT id, language, book, text FROM bible_verses',
      );
    }
  }

  void _ensureSermonFts(sql.Database db) {
    db.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS sermon_fts
      USING fts5(
        text,
        content=sermon_paragraphs,
        content_rowid=id,
        tokenize='unicode61'
      )
    ''');

    final check = db.select('SELECT COUNT(*) FROM sermon_fts');
    final count = check.isEmpty ? 0 : (check.first.columnAt(0) as int? ?? 0);
    if (count == 0) {
      debugPrint('sermon_fts empty — rebuilding from sermon_paragraphs...');
      db.execute(
        'INSERT INTO sermon_fts(rowid, text) '
        'SELECT id, text FROM sermon_paragraphs',
      );
    }
  }

  /// Run PRAGMA optimize on both FTS tables (lightweight, mirrors Android's FtsOptimizer).
  void warmUpFts(String dbPath, DbType type) {
    try {
      final db = sql.sqlite3.open(dbPath);
      try {
        db.execute('PRAGMA optimize');
        final tableName = type == DbType.bible ? 'bible_fts' : 'sermon_fts';
        db.execute("INSERT INTO $tableName($tableName) VALUES('optimize')");
      } finally {
        db.close();
      }
    } catch (e) {
      debugPrint('warmUpFts warning: $e');
    }
  }
}
