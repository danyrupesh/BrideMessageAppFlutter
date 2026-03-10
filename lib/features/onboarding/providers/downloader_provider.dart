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

  const DownloaderState({
    this.isActive = false,
    this.progress = 0.0,
    this.statusMessage = '',
    this.isComplete = false,
    this.error,
  });

  DownloaderState copyWith({
    bool? isActive,
    double? progress,
    String? statusMessage,
    bool? isComplete,
    String? error,
  }) {
    return DownloaderState(
      isActive: isActive ?? this.isActive,
      progress: progress ?? this.progress,
      statusMessage: statusMessage ?? this.statusMessage,
      isComplete: isComplete ?? this.isComplete,
      error: error,
    );
  }
}

// ─── Notifier ────────────────────────────────────────────────────────────────

class DownloaderNotifier extends Notifier<DownloaderState> {
  final _importer = SelectiveDatabaseImporter();
  final _dio = Dio();

  @override
  DownloaderState build() => const DownloaderState();

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

      // 1. Download
      await _dio.download(
        url,
        tempPath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final pct = received / total * 0.5;
            state = state.copyWith(
              progress: pct,
              statusMessage: 'Downloading database...',
            );
          }
        },
      );

      // 2. Import
      state = state.copyWith(progress: 0.5, statusMessage: 'Extracting...');
      final result = await _importer.importAllFromZip(
        zipPath: tempPath,
        onProgress: (pct, msg) {
          state = state.copyWith(
            progress: 0.5 + pct * 0.5,
            statusMessage: msg,
          );
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
        );
      } else {
        state = DownloaderState(
          error: result.message,
          statusMessage: 'Failed',
        );
      }
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
      );
    } else {
      state = DownloaderState(
        error: result.message,
        statusMessage: 'Failed',
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
