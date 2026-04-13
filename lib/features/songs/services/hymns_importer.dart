import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/database_manager.dart';

const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://api.endtimebride.in',
);

class HymnsImporter {
  static const String serverZipUrl =
      '$kApiBaseUrl/database/only_believe_song.zip';
  static const String hymnDbName = 'hymn.db';

  final DatabaseManager _dbManager = DatabaseManager();
  final Dio _dio = Dio();

  /// Returns true if the hymns database file already exists.
  static Future<bool> isInstalled() async {
    final dbDir = await DatabaseManager().getDatabaseDirectoryPath();
    final path = p.join(dbDir.path, hymnDbName);
    return File(path).exists();
  }

  /// Download the hymns ZIP from the server and install it as [hymnDbName].
  ///
  /// [onProgress] receives (0..1, humanMessage).
  Future<void> downloadAndInstall({
    required void Function(double, String) onProgress,
  }) async {
    final dbDir = await _dbManager.getDatabaseDirectoryPath();
    final tempZipPath =
        p.join(dbDir.path, 'hymns_download_${DateTime.now().millisecondsSinceEpoch}.zip');

    try {
      onProgress(0.0, 'Connecting to server...');

      await _dio.download(
        serverZipUrl,
        tempZipPath,
        onReceiveProgress: (received, total) {
          if (total <= 0) return;
          final pct = received / total;
          onProgress(pct * 0.6, 'Downloading hymns database...');
        },
      );

      await _installFromZipInternal(
        zipPath: tempZipPath,
        baseProgress: 0.6,
        onProgress: onProgress,
      );
    } finally {
      final tmp = File(tempZipPath);
      if (await tmp.exists()) {
        try {
          await tmp.delete();
        } catch (_) {}
      }
    }
  }

  /// Install hymns from a locally selected ZIP file.
  ///
  /// [onProgress] receives (0..1, humanMessage).
  Future<void> installFromZip({
    required String zipPath,
    required void Function(double, String) onProgress,
  }) async {
    await _installFromZipInternal(
      zipPath: zipPath,
      baseProgress: 0.0,
      onProgress: onProgress,
    );
  }

  Future<void> _installFromZipInternal({
    required String zipPath,
    required double baseProgress,
    required void Function(double, String) onProgress,
  }) async {
    onProgress(baseProgress, 'Reading ZIP file...');

    final zipFile = File(zipPath);
    if (!await zipFile.exists()) {
      throw Exception('ZIP file not found.');
    }

    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final dbEntry = archive.firstWhere(
      (f) => f.isFile && f.name.toLowerCase().endsWith('.db'),
      orElse: () => throw Exception('No .db file found in archive.'),
    );

    onProgress(baseProgress + 0.1, 'Preparing hymns database...');

    final dbDir = await _dbManager.getDatabaseDirectoryPath();
    final tempDbPath = p.join(dbDir.path, 'hymns_import_temp.db');
    final tempDbFile = File(tempDbPath);
    tempDbFile.writeAsBytesSync(dbEntry.content as List<int>);

    try {
      onProgress(baseProgress + 0.3, 'Installing hymns database...');

      await _dbManager.deleteDatabaseFiles(hymnDbName);

      final targetPath = p.join(dbDir.path, hymnDbName);
      await tempDbFile.copy(targetPath);

      onProgress(1.0, 'Hymns database installed.');
    } finally {
      if (await tempDbFile.exists()) {
        try {
          await tempDbFile.delete();
        } catch (_) {}
      }
    }
  }
}

