import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../../core/database/database_manager.dart';
import '../../../core/database/metadata/installed_content_provider.dart';
import '../services/selective_database_importer.dart';

// ─── State ───────────────────────────────────────────────────────────────────

class DownloaderState {
  final bool isActive;
  final double progress;
  final String statusMessage;
  final bool isComplete;
  final String? error;
  final ImportReport? report;

  const DownloaderState({
    this.isActive = false,
    this.progress = 0.0,
    this.statusMessage = '',
    this.isComplete = false,
    this.error,
    this.report,
  });

  DownloaderState copyWith({
    bool? isActive,
    double? progress,
    String? statusMessage,
    bool? isComplete,
    String? error,
    ImportReport? report,
  }) {
    return DownloaderState(
      isActive: isActive ?? this.isActive,
      progress: progress ?? this.progress,
      statusMessage: statusMessage ?? this.statusMessage,
      isComplete: isComplete ?? this.isComplete,
      error: error,
      report: report ?? this.report,
    );
  }
}

// ─── Notifier ────────────────────────────────────────────────────────────────

class DownloaderNotifier extends Notifier<DownloaderState> {
  final _importer = SelectiveDatabaseImporter();
  final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(minutes: 2),
      receiveTimeout: const Duration(minutes: 10),
      followRedirects: true,
    ),
  );

  @override
  DownloaderState build() => const DownloaderState();

  Future<void> _downloadZipWithRetry({
    required String url,
    required String tempPath,
  }) async {
    const maxAttempts = 3;
    final file = File(tempPath);

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final existingBytes = await file.exists() ? await file.length() : 0;

      if (attempt > 1) {
        state = state.copyWith(
          statusMessage:
              'Connection interrupted. Retrying ($attempt/$maxAttempts)...',
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
            validateStatus: (status) {
              if (status == null) return false;
              return status >= 200 && status < 300;
            },
          ),
          onReceiveProgress: (received, total) {
            final cumulativeReceived = existingBytes + received;
            final cumulativeTotal = total > 0 ? existingBytes + total : total;
            if (cumulativeTotal > 0) {
              final pct = cumulativeReceived / cumulativeTotal * 0.5;
              state = state.copyWith(
                progress: pct.clamp(0.0, 0.5),
                statusMessage: 'Downloading database...',
              );
            } else {
              state = state.copyWith(statusMessage: 'Downloading database...');
            }
          },
        );
        return;
      } on DioException {
        if (attempt == maxAttempts) rethrow;
      }
    }
  }

  /// Download the unified ZIP from [url] and import all databases.
  Future<void> startDownload(String url) async {
    state = const DownloaderState(
      isActive: true,
      progress: 0.0,
      statusMessage: 'Connecting to server...',
    );

    try {
      final dbDir = await DatabaseManager().getDatabaseDirectoryPath();
      final tempPath = p.join(
        dbDir.path,
        'download_${DateTime.now().millisecondsSinceEpoch}.zip',
      );

      // 1. Download (with retry + resume for unstable mobile networks)
      await _downloadZipWithRetry(url: url, tempPath: tempPath);

      // 2. Import
      state = state.copyWith(progress: 0.5, statusMessage: 'Extracting...');
      final result = await _importer.importAllFromZip(
        zipPath: tempPath,
        onProgress: (pct, msg) {
          state = state.copyWith(progress: 0.5 + pct * 0.5, statusMessage: msg);
        },
      );

      // Cleanup temp ZIP
      try {
        await File(tempPath).delete();
      } catch (_) {}

      if (result.success) {
        await ref.read(hasInstalledContentProvider.notifier).refresh();
        state = DownloaderState(
          isComplete: true,
          statusMessage: result.message,
          progress: 1.0,
          report: result.report,
        );
      } else {
        state = DownloaderState(
          error: result.message,
          statusMessage: 'Failed',
          report: result.report,
        );
      }
    } on DioException catch (e) {
      final reason = e.message ?? 'Network stream interrupted.';
      state = DownloaderState(
        error:
            'Download failed after multiple retries: $reason\n\nPlease retry, or use Import from Device with the same ZIP file.',
        statusMessage: 'Failed',
      );
    } catch (e) {
      state = DownloaderState(
        error: 'Download failed: $e',
        statusMessage: 'Failed',
      );
    }
  }

  /// Import all databases from a local ZIP file selected from device storage.
  Future<void> importFromZip(String filePath) async {
    state = const DownloaderState(
      isActive: true,
      progress: 0.0,
      statusMessage: 'Starting import...',
    );

    final result = await _importer.importAllFromZip(
      zipPath: filePath,
      onProgress: (pct, msg) {
        state = state.copyWith(progress: pct, statusMessage: msg);
      },
    );

    if (result.success) {
      await ref.read(hasInstalledContentProvider.notifier).refresh();
      state = DownloaderState(
        isComplete: true,
        statusMessage: result.message,
        progress: 1.0,
        report: result.report,
      );
    } else {
      state = DownloaderState(
        error: result.message,
        statusMessage: 'Failed',
        report: result.report,
      );
    }
  }

  void reset() => state = const DownloaderState();
}

// ─── Providers ────────────────────────────────────────────────────────────────

final downloaderProvider =
    NotifierProvider<DownloaderNotifier, DownloaderState>(
      DownloaderNotifier.new,
    );
