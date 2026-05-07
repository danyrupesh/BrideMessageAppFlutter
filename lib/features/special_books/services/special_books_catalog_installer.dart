import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/database_manager.dart';
import '../../onboarding/services/database_discovery_service.dart';
import '../../onboarding/services/selective_database_importer.dart';

const String kSpecialBooksApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://api.endtimebride.in',
);

class SpecialBooksCatalogInstaller {
  SpecialBooksCatalogInstaller({
    DatabaseDiscoveryService? discovery,
    SelectiveDatabaseImporter? importer,
  }) : _discovery = discovery ?? DatabaseDiscoveryService(),
       _importer = importer ?? SelectiveDatabaseImporter();

  final DatabaseDiscoveryService _discovery;
  final SelectiveDatabaseImporter _importer;

  Future<bool> installByDownload(String lang) async {
    final dbId = 'special_books_catalog_$lang';
    final displayName = lang == 'ta'
        ? 'Special Books Catalog (Tamil)'
        : 'Special Books Catalog (English)';

    try {
      final all = await _discovery.availableDatabases(kSpecialBooksApiBaseUrl);
      final entry = all.where((d) => d.id == dbId).toList();
      if (entry.isEmpty) return false;
      final downloadUrl = entry.first.downloadUrl.trim();
      if (downloadUrl.isEmpty) return false;

      final dbDir = await DatabaseManager().getDatabaseDirectoryPath();
      final downloadPath = p.join(dbDir.path, '${dbId}_download.tmp');
      await Dio().download(downloadUrl, downloadPath);

      final isDb = await _looksLikeSqliteDb(downloadPath);
      String? importPath;
      if (isDb) {
        importPath = downloadPath;
      } else if (await _looksLikeZipFile(downloadPath)) {
        final extractedPath = p.join(dbDir.path, '${dbId}_extracted.db');
        importPath = await _extractDbFromZip(
          zipPath: downloadPath,
          expectedDbFileName: 'special_books_catalog_$lang.db',
          outputPath: extractedPath,
        );
      }

      if (importPath == null || !await _looksLikeSqliteDb(importPath)) {
        try {
          await File(downloadPath).delete();
        } catch (_) {}
        return false;
      }

      final result = await _importer.importSpecialBooksCatalog(
        sourceFile: File(importPath),
        languageCode: lang,
        displayName: displayName,
        onProgress: (progress, message) {},
      );

      try {
        await File(downloadPath).delete();
      } catch (_) {}
      if (importPath != downloadPath) {
        try {
          await File(importPath).delete();
        } catch (_) {}
      }

      return result.success;
    } catch (_) {
      return false;
    }
  }

  Future<bool> installByFilePicker(String lang) async {
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const ['db'],
      dialogTitle: 'Select special_books_catalog_$lang.db',
    );
    if (picked == null || picked.files.isEmpty) return false;
    final selectedPath = picked.files.single.path;
    if (selectedPath == null || selectedPath.trim().isEmpty) return false;
    if (!await _looksLikeSqliteDb(selectedPath)) return false;

    final displayName = lang == 'ta'
        ? 'Special Books Catalog (Tamil)'
        : 'Special Books Catalog (English)';
    final result = await _importer.importSpecialBooksCatalog(
      sourceFile: File(selectedPath),
      languageCode: lang,
      displayName: displayName,
      onProgress: (progress, message) {},
    );
    return result.success;
  }

  Future<bool> _looksLikeSqliteDb(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return false;
      final bytes = await file.openRead(0, 16).fold<List<int>>(
        <int>[],
        (acc, data) => acc..addAll(data),
      );
      if (bytes.length < 16) return false;
      return String.fromCharCodes(bytes).startsWith('SQLite format 3');
    } catch (_) {
      return false;
    }
  }

  Future<bool> _looksLikeZipFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return false;
      final bytes = await file.openRead(0, 4).fold<List<int>>(
        <int>[],
        (acc, data) => acc..addAll(data),
      );
      return bytes.length >= 4 &&
          bytes[0] == 0x50 &&
          bytes[1] == 0x4B &&
          bytes[2] == 0x03 &&
          bytes[3] == 0x04;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _extractDbFromZip({
    required String zipPath,
    required String expectedDbFileName,
    required String outputPath,
  }) async {
    try {
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      ArchiveFile? dbEntry;
      for (final file in archive.files) {
        if (!file.isFile) continue;
        final baseName = p.basename(file.name).toLowerCase();
        if (baseName == expectedDbFileName.toLowerCase()) {
          dbEntry = file;
          break;
        }
      }
      dbEntry ??= archive.files.firstWhere(
        (file) => file.isFile && p.basename(file.name).toLowerCase().endsWith('.db'),
        orElse: () => ArchiveFile('', 0, []),
      );
      if (dbEntry.name.isEmpty) return null;
      await File(outputPath).writeAsBytes(dbEntry.content as List<int>, flush: true);
      return outputPath;
    } catch (_) {
      return null;
    }
  }
}

