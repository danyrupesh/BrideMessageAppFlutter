import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/tamil_hymns_importer.dart';

sealed class TamilSongInstallState {
  const TamilSongInstallState();
}

class TamilSongInstallIdle extends TamilSongInstallState {
  const TamilSongInstallIdle();
}

class TamilSongInstallConnecting extends TamilSongInstallState {
  const TamilSongInstallConnecting();
}

class TamilSongInstallDownloading extends TamilSongInstallState {
  final double progress;
  const TamilSongInstallDownloading(this.progress);
}

class TamilSongInstallExtracting extends TamilSongInstallState {
  const TamilSongInstallExtracting();
}

class TamilSongInstallSuccess extends TamilSongInstallState {
  const TamilSongInstallSuccess();
}

class TamilSongInstallError extends TamilSongInstallState {
  final String message;
  const TamilSongInstallError(this.message);
}

class TamilSongInstallNotifier extends Notifier<TamilSongInstallState> {
  final TamilHymnsImporter _importer = TamilHymnsImporter();

  @override
  TamilSongInstallState build() => const TamilSongInstallIdle();

  Future<void> onDownloadFromServer() async {
    if (state is TamilSongInstallConnecting || state is TamilSongInstallDownloading || state is TamilSongInstallExtracting) return;
    state = const TamilSongInstallConnecting();
    try {
      await _importer.downloadAndInstall(
        onProgress: (progress, message) {
          if (progress < 0.8) {
            state = TamilSongInstallDownloading(progress);
          } else {
            state = const TamilSongInstallExtracting();
          }
        },
      );
      state = const TamilSongInstallSuccess();
    } catch (e) {
      state = TamilSongInstallError(e.toString());
    }
  }

  Future<void> onImportFromZip(String path) async {
    if (state is TamilSongInstallConnecting || state is TamilSongInstallDownloading || state is TamilSongInstallExtracting) return;
    state = const TamilSongInstallConnecting();
    try {
      await _importer.installFromZip(
        zipPath: path,
        onProgress: (progress, message) {
          if (progress < 0.8) {
            state = TamilSongInstallDownloading(progress);
          } else {
            state = const TamilSongInstallExtracting();
          }
        },
      );
      state = const TamilSongInstallSuccess();
    } catch (e) {
      state = TamilSongInstallError(e.toString());
    }
  }

  void reset() => state = const TamilSongInstallIdle();
}

final tamilSongInstallProvider = NotifierProvider<TamilSongInstallNotifier, TamilSongInstallState>(TamilSongInstallNotifier.new);
