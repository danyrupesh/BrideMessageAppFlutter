import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/hymns_importer.dart';

sealed class SongInstallState {
  const SongInstallState();
}

class SongInstallIdle extends SongInstallState {
  const SongInstallIdle();
}

class SongInstallConnecting extends SongInstallState {
  const SongInstallConnecting();
}

class SongInstallDownloading extends SongInstallState {
  final double progress; // 0..1
  const SongInstallDownloading(this.progress);
}

class SongInstallExtracting extends SongInstallState {
  const SongInstallExtracting();
}

class SongInstallSuccess extends SongInstallState {
  const SongInstallSuccess();
}

class SongInstallError extends SongInstallState {
  final String message;
  const SongInstallError(this.message);
}

class SongInstallNotifier extends Notifier<SongInstallState> {
  final HymnsImporter _importer = HymnsImporter();

  @override
  SongInstallState build() => const SongInstallIdle();

  Future<void> onDownloadFromServer() async {
    // Avoid starting another download while one is in progress.
    if (state is SongInstallConnecting ||
        state is SongInstallDownloading ||
        state is SongInstallExtracting) {
      return;
    }
    state = const SongInstallConnecting();
    try {
      await _importer.downloadAndInstall(
        onProgress: (progress, message) {
          // Treat mid-range progress as downloading, near-end as extracting.
          if (progress < 0.8) {
            state = SongInstallDownloading(progress);
          } else {
            state = const SongInstallExtracting();
          }
        },
      );
      state = const SongInstallSuccess();
    } catch (e) {
      state = SongInstallError(e.toString());
    }
  }

  Future<void> onImportFromZip(String path) async {
    // Avoid overlapping operations.
    if (state is SongInstallConnecting ||
        state is SongInstallDownloading ||
        state is SongInstallExtracting) {
      return;
    }
    state = const SongInstallConnecting();
    try {
      await _importer.installFromZip(
        zipPath: path,
        onProgress: (progress, message) {
          if (progress < 0.8) {
            state = SongInstallDownloading(progress);
          } else {
            state = const SongInstallExtracting();
          }
        },
      );
      state = const SongInstallSuccess();
    } catch (e) {
      state = SongInstallError(e.toString());
    }
  }

  void reset() {
    state = const SongInstallIdle();
  }
}

final songInstallProvider =
    NotifierProvider<SongInstallNotifier, SongInstallState>(
  SongInstallNotifier.new,
);

