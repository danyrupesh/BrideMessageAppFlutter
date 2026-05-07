import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sql;

import '../../../core/database/database_manager.dart';
import '../../../core/database/metadata/special_book_download_registry.dart';
import '../../../core/database/models/special_book_models.dart';

// ── Download state ────────────────────────────────────────────────────────────

class BookDownloadState {
  const BookDownloadState({
    this.isActive = false,
    this.progress = 0.0,
    this.statusMessage = '',
    this.isComplete = false,
    this.error,
  });

  final bool isActive;
  final double progress;
  final String statusMessage;
  final bool isComplete;
  final String? error;

  bool get hasError => error != null;

  BookDownloadState copyWith({
    bool? isActive,
    double? progress,
    String? statusMessage,
    bool? isComplete,
    String? error,
  }) {
    return BookDownloadState(
      isActive: isActive ?? this.isActive,
      progress: progress ?? this.progress,
      statusMessage: statusMessage ?? this.statusMessage,
      isComplete: isComplete ?? this.isComplete,
      error: error,
    );
  }
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class SpecialBookDownloadNotifier
    extends Notifier<BookDownloadState> {
  SpecialBookDownloadNotifier(this.bookId);
  final String bookId;

  final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(minutes: 2),
      receiveTimeout: const Duration(minutes: 15),
      followRedirects: true,
    ),
  );

  @override
  BookDownloadState build() => const BookDownloadState();

  /// Download per-book content ZIP from [url] and install it.
  Future<void> downloadBook({
    required String url,
    required String lang,
    required int expectedVersion,
  }) async {
    state = const BookDownloadState(
      isActive: true,
      progress: 0.0,
      statusMessage: 'Connecting...',
    );

    try {
      final dbDir = await DatabaseManager().getDatabaseDirectoryPath();
      final tempPath = p.join(
        dbDir.path,
        'special_book_${bookId}_${lang}_${DateTime.now().millisecondsSinceEpoch}.zip',
      );

      await _downloadWithRetry(url: url, tempPath: tempPath);

      state = state.copyWith(progress: 0.5, statusMessage: 'Extracting...');

      final result = await _importFromZip(
        zipPath: tempPath,
        bookId: bookId,
        lang: lang,
        expectedVersion: expectedVersion,
      );

      try {
        await File(tempPath).delete();
      } catch (_) {}

      if (result.success) {
        await ref
            .read(specialBookDownloadStatusProvider(SpecialBookKey(bookId: bookId, lang: lang)).notifier)
            .refresh();
        state = BookDownloadState(
          isComplete: true,
          progress: 1.0,
          statusMessage: result.message,
        );
      } else {
        state = BookDownloadState(
          error: result.message,
          statusMessage: 'Failed',
        );
      }
    } on DioException catch (e) {
      state = BookDownloadState(
        error: 'Download failed: ${e.message ?? 'Network error'}',
        statusMessage: 'Failed',
      );
    } catch (e) {
      state = BookDownloadState(
        error: 'Download failed: $e',
        statusMessage: 'Failed',
      );
    }
  }

  /// Import a per-book content ZIP from a local file path.
  Future<void> importFromZip({
    required String filePath,
    required String lang,
    required int expectedVersion,
  }) async {
    state = const BookDownloadState(
      isActive: true,
      progress: 0.0,
      statusMessage: 'Starting import...',
    );

    final result = await _importFromZip(
      zipPath: filePath,
      bookId: bookId,
      lang: lang,
      expectedVersion: expectedVersion,
    );

    if (result.success) {
      await ref
          .read(specialBookDownloadStatusProvider(SpecialBookKey(bookId: bookId, lang: lang)).notifier)
          .refresh();
      state = BookDownloadState(
        isComplete: true,
        progress: 1.0,
        statusMessage: result.message,
      );
    } else {
      state = BookDownloadState(
        error: result.message,
        statusMessage: 'Failed',
      );
    }
  }

  /// Delete the downloaded content for this book.
  Future<void> deleteDownload(String lang) async {
    try {
      final registry = SpecialBookDownloadRegistry();
      final record = await registry.get(bookId, lang);
      if (record != null) {
        final file = File(record.localDbPath);
        if (await file.exists()) await file.delete();
        await registry.remove(bookId, lang);
      }
      await ref
          .read(specialBookDownloadStatusProvider(SpecialBookKey(bookId: bookId, lang: lang)).notifier)
          .refresh();
      state = const BookDownloadState();
    } catch (e) {
      state = BookDownloadState(error: 'Delete failed: $e');
    }
  }

  void reset() => state = const BookDownloadState();

  // ── Private ──────────────────────────────────────────────────────────────

  Future<void> _downloadWithRetry({
    required String url,
    required String tempPath,
  }) async {
    const maxAttempts = 3;
    final file = File(tempPath);

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final existingBytes = await file.exists() ? await file.length() : 0;
      if (attempt > 1) {
        state = state.copyWith(
          statusMessage: 'Retrying ($attempt/$maxAttempts)...',
        );
      }
      try {
        await _dio.download(
          url,
          tempPath,
          fileAccessMode: existingBytes > 0
              ? FileAccessMode.append
              : FileAccessMode.write,
          deleteOnError: false,
          options: Options(
            headers: existingBytes > 0
                ? <String, dynamic>{'Range': 'bytes=$existingBytes-'}
                : null,
            validateStatus: (s) => s != null && s >= 200 && s < 300,
          ),
          onReceiveProgress: (received, total) {
            final cum = existingBytes + received;
            final cumTotal = total > 0 ? existingBytes + total : total;
            if (cumTotal > 0) {
              final pct = cum / cumTotal * 0.5;
              state = state.copyWith(
                progress: pct.clamp(0.0, 0.5),
                statusMessage: 'Downloading book content...',
              );
            }
          },
        );
        return;
      } on DioException {
        if (attempt == maxAttempts) rethrow;
      }
    }
  }

  Future<_ImportResult> _importFromZip({
    required String zipPath,
    required String bookId,
    required String lang,
    required int expectedVersion,
  }) async {
    try {
      state = state.copyWith(progress: 0.55, statusMessage: 'Reading archive...');

      final zipFile = File(zipPath);
      if (!await zipFile.exists()) {
        return _ImportResult.failure('ZIP file not found: $zipPath');
      }

      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // Find the content .db file
      final dbEntry = archive.firstWhere(
        (f) =>
            f.isFile &&
            f.name.endsWith('.db') &&
            !f.name.toLowerCase().contains('manifest'),
        orElse: () => ArchiveFile('', 0, []),
      );

      if (dbEntry.name.isEmpty) {
        return _ImportResult.failure('No .db file found in archive.');
      }

      state = state.copyWith(progress: 0.65, statusMessage: 'Validating...');

      // Validate the content DB
      final dbDir = await DatabaseManager().getDatabaseDirectoryPath();
      final safeId = bookId.replaceAll(RegExp(r'[^a-z0-9_\-]'), '_');
      final targetDbName = 'special_book_${safeId}_$lang.db';
      final targetPath = p.join(dbDir.path, targetDbName);

      // Write to temp for validation
      final tempValidatePath = p.join(dbDir.path, 'validate_sb_${DateTime.now().millisecondsSinceEpoch}.db');
      final tempValidate = File(tempValidatePath);
      await tempValidate.writeAsBytes(dbEntry.content as List<int>);

      try {
        final db = sql.sqlite3.open(tempValidatePath, mode: sql.OpenMode.readOnly);
        try {
          final tables = db
              .select("SELECT name FROM sqlite_master WHERE type='table'")
              .map((r) => (r.columnAt(0) as String).toLowerCase())
              .toSet();
          if (!tables.contains('chapters')) {
            return _ImportResult.failure(
              'Invalid book content: missing chapters table.',
            );
          }
        } finally {
          db.close();
        }
      } finally {
        await tempValidate.delete();
      }

      state = state.copyWith(progress: 0.8, statusMessage: 'Installing...');

      // Install to final path
      await DatabaseManager().closeDatabase(targetDbName);
      await DatabaseManager().deleteDatabaseFiles(targetDbName);
      final destFile = File(targetPath);
      await destFile.writeAsBytes(dbEntry.content as List<int>);

      state = state.copyWith(progress: 0.9, statusMessage: 'Registering...');

      // Register in download registry
      final registry = SpecialBookDownloadRegistry();
      await registry.upsert(
        SpecialBookDownload(
          bookId: bookId,
          lang: lang,
          contentVersion: expectedVersion,
          downloadedAt: DateTime.now().toUtc().toIso8601String(),
          localDbPath: targetPath,
        ),
      );

      return _ImportResult.success('Book content installed successfully.');
    } catch (e, st) {
      debugPrint('SpecialBookDownload._importFromZip error: $e\n$st');
      return _ImportResult.failure('Import failed: $e');
    }
  }
}

class _ImportResult {
  const _ImportResult._(this.success, this.message);
  factory _ImportResult.success(String msg) => _ImportResult._(true, msg);
  factory _ImportResult.failure(String msg) => _ImportResult._(false, msg);
  final bool success;
  final String message;
}

// ── Download status provider ──────────────────────────────────────────────────

class SpecialBookKey {
  const SpecialBookKey({required this.bookId, required this.lang});
  final String bookId;
  final String lang;

  @override
  bool operator ==(Object other) =>
      other is SpecialBookKey && other.bookId == bookId && other.lang == lang;

  @override
  int get hashCode => Object.hash(bookId, lang);
}

class SpecialBookDownloadStatusNotifier
    extends AsyncNotifier<bool> {
  SpecialBookDownloadStatusNotifier(this.key);
  final SpecialBookKey key;

  @override
  Future<bool> build() async {
    return SpecialBookDownloadRegistry().isDownloaded(key.bookId, key.lang);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(
      await SpecialBookDownloadRegistry().isDownloaded(key.bookId, key.lang),
    );
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final specialBookDownloadProvider =
    NotifierProvider.family<SpecialBookDownloadNotifier, BookDownloadState, String>(
  (bookId) => SpecialBookDownloadNotifier(bookId),
);

final specialBookDownloadStatusProvider = AsyncNotifierProvider.family<
    SpecialBookDownloadStatusNotifier, bool, SpecialBookKey>(
  (key) => SpecialBookDownloadStatusNotifier(key),
);
