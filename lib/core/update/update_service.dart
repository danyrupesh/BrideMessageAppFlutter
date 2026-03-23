import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/database/database_manager.dart';
import '../../core/database/metadata/installed_database_registry.dart';
import '../../features/onboarding/services/selective_database_importer.dart';
import '../../features/songs/services/hymns_importer.dart';

const String kAppUpdatesManifestUrl =
    'https://api.endtimebride.in/database/updates/app_version.json';
const String kDatabaseUpdatesManifestUrl =
    'https://api.endtimebride.in/database/updates/db_version.json';

class AppUpdateInfo {
  final String targetVersion;
  final bool mandatory;
  final String url;
  final String currentVersion;
  final String packageType;

  const AppUpdateInfo({
    required this.targetVersion,
    required this.mandatory,
    required this.url,
    required this.currentVersion,
    required this.packageType,
  });
}

class DatabaseUpdateInfo {
  final String id;
  final String displayName;
  final int version;
  final bool mandatory;
  final String url;
  final String installStrategy;

  const DatabaseUpdateInfo({
    required this.id,
    required this.displayName,
    required this.version,
    required this.mandatory,
    required this.url,
    required this.installStrategy,
  });
}

class UpdateService {
  final Dio _dio;

  UpdateService({Dio? dio}) : _dio = dio ?? Dio();

  Future<AppUpdateInfo?> checkAppUpdate() async {
    final payload = await _fetchJson(kAppUpdatesManifestUrl);
    if (payload == null) return null;

    final platformKey = _platformKey;
    if (platformKey == null) return null;

    final target = payload[platformKey];
    if (target is! Map) return null;

    final targetVersion = (target['version'] ?? '').toString().trim();
    final url = (target['url'] ?? '').toString().trim();
    final mandatory = _parseBool(target['mandatory']);
    final packageType =
        (target['packageType'] ?? target['package_type'] ?? 'installer')
            .toString()
            .trim()
            .toLowerCase();

    if (targetVersion.isEmpty || url.isEmpty) return null;

    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version.trim();

    if (_compareSemver(targetVersion, currentVersion) <= 0) {
      return null;
    }

    return AppUpdateInfo(
      targetVersion: targetVersion,
      mandatory: mandatory,
      url: url,
      currentVersion: currentVersion,
      packageType: packageType,
    );
  }

  Future<List<DatabaseUpdateInfo>> checkDatabaseUpdates() async {
    final payload = await _fetchJson(kDatabaseUpdatesManifestUrl);
    if (payload == null) return const <DatabaseUpdateInfo>[];

    final prefs = await SharedPreferences.getInstance();
    final entries = _extractDatabaseEntries(payload);
    final updates = <DatabaseUpdateInfo>[];

    for (final entry in entries) {
      final id = (entry['id'] ?? '').toString().trim();
      final displayName = (entry['displayName'] ?? id).toString().trim();
      final version = _parseInt(entry['version']);
      final url = (entry['url'] ?? '').toString().trim();
      final mandatory = _parseBool(entry['mandatory']);
      final installStrategy =
          (entry['installStrategy'] ??
                  entry['install_strategy'] ??
                  entry['strategy'] ??
                  'auto')
              .toString()
              .trim()
              .toLowerCase();
      final bundledVersion =
          _parseInt(entry['bundledVersion'] ?? entry['defaultVersion']) ?? 0;

      if (id.isEmpty || version == null || url.isEmpty) continue;

      // Fresh installs should not receive update prompts before a DB exists.
      final isInstalled = await _isDatabaseInstalledLocally(id);
      if (!isInstalled) continue;

      final localVersion = prefs.getInt(_dbVersionKey(id)) ?? bundledVersion;
      if (version > localVersion) {
        updates.add(
          DatabaseUpdateInfo(
            id: id,
            displayName: displayName.isEmpty ? id : displayName,
            version: version,
            mandatory: mandatory,
            url: url,
            installStrategy: installStrategy,
          ),
        );
      }
    }

    updates.sort((a, b) => a.id.compareTo(b.id));
    return updates;
  }

  Future<void> applyDatabaseUpdates(
    List<DatabaseUpdateInfo> updates, {
    void Function(String message)? onStatus,
    void Function(int received, int total)? onReceiveProgress,
  }) async {
    if (updates.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final importer = SelectiveDatabaseImporter();

    for (final update in updates) {
      final tempRoot = await getTemporaryDirectory();
      final workDir = Directory(
        p.join(
          tempRoot.path,
          'db_update_${update.id}_${DateTime.now().millisecondsSinceEpoch}',
        ),
      );

      if (!await workDir.exists()) {
        await workDir.create(recursive: true);
      }

      final zipPath = p.join(workDir.path, '${update.id}.zip');

      try {
        onStatus?.call('Downloading ${update.displayName}...');
        await _dio.download(
          update.url,
          zipPath,
          onReceiveProgress: onReceiveProgress,
          options: Options(responseType: ResponseType.bytes),
        );

        onStatus?.call('Installing ${update.displayName}...');
        final shouldUseHymnsInstaller =
            _useHymnsInstaller(update) || await _looksLikeHymnsZip(zipPath);

        if (shouldUseHymnsInstaller) {
          final hymnsImporter = HymnsImporter();
          await hymnsImporter.installFromZip(
            zipPath: zipPath,
            onProgress: (_, message) => onStatus?.call(message),
          );
        } else {
          final result = await importer.importAllFromZip(
            zipPath: zipPath,
            onProgress: (_, message) => onStatus?.call(message),
          );

          if (!result.success) {
            throw StateError(result.message);
          }
        }

        await prefs.setInt(_dbVersionKey(update.id), update.version);
        onStatus?.call('${update.displayName} updated to v${update.version}.');
      } finally {
        if (await workDir.exists()) {
          await workDir.delete(recursive: true);
        }
      }
    }
  }

  Future<Map<String, dynamic>?> _fetchJson(String url) async {
    try {
      final response = await _dio.get(
        url,
        options: Options(responseType: ResponseType.json),
      );
      final data = response.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) {
        return data.map((key, value) => MapEntry(key.toString(), value));
      }
    } on DioException catch (e) {
      debugPrint('UpdateService network error for $url: ${e.message}');
    } on SocketException catch (e) {
      debugPrint('UpdateService socket error for $url: $e');
    } catch (e) {
      debugPrint('UpdateService unexpected error for $url: $e');
    }
    return null;
  }

  List<Map<String, dynamic>> _extractDatabaseEntries(Map<String, dynamic> raw) {
    final listRaw = raw['databases'];
    if (listRaw is List) {
      return listRaw.whereType<Map>().map((entry) {
        return entry.map((key, value) => MapEntry(key.toString(), value));
      }).toList();
    }

    // Backward-compatible parser for keyed payload format.
    final entries = <Map<String, dynamic>>[];
    raw.forEach((key, value) {
      if (value is Map) {
        final mapped = value.map(
          (innerKey, innerValue) => MapEntry(innerKey.toString(), innerValue),
        );
        entries.add(<String, dynamic>{'id': key.toString(), ...mapped});
      }
    });
    return entries;
  }

  String? get _platformKey {
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    return null;
  }

  String _dbVersionKey(String id) => 'updates.db.version.$id';

  Future<bool> _isDatabaseInstalledLocally(String id) async {
    if (id == 'only_believe_song') {
      return HymnsImporter.isInstalled();
    }

    if (id == 'bridemessage_db') {
      if (await InstalledDatabaseRegistry().hasAnyContent(
        allowFileFallback: true,
      )) {
        return true;
      }

      final dbDir = await DatabaseManager().getDatabaseDirectoryPath();
      const known = <String>['cod_tamil.db', 'cod_english.db'];
      for (final fileName in known) {
        if (await File(p.join(dbDir.path, fileName)).exists()) {
          return true;
        }
      }
      return false;
    }

    // Unknown IDs are treated as installed so custom manifests can still work.
    return true;
  }

  bool _useHymnsInstaller(DatabaseUpdateInfo update) {
    if (update.installStrategy == 'hymns') return true;
    if (update.installStrategy == 'auto') {
      return update.id == 'only_believe_song';
    }
    return false;
  }

  Future<bool> _looksLikeHymnsZip(String zipPath) async {
    try {
      final zipFile = File(zipPath);
      if (!await zipFile.exists()) return false;

      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      for (final entry in archive) {
        if (!entry.isFile) continue;
        final name = p.basename(entry.name).toLowerCase();
        if (name == HymnsImporter.hymnDbName.toLowerCase()) {
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  bool _parseBool(Object? value) {
    if (value is bool) return value;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1';
    }
    if (value is num) return value != 0;
    return false;
  }

  int? _parseInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  int _compareSemver(String a, String b) {
    final aParts = _toVersionParts(a);
    final bParts = _toVersionParts(b);
    final maxLen = aParts.length > bParts.length
        ? aParts.length
        : bParts.length;

    for (var i = 0; i < maxLen; i++) {
      final ai = i < aParts.length ? aParts[i] : 0;
      final bi = i < bParts.length ? bParts[i] : 0;
      if (ai > bi) return 1;
      if (ai < bi) return -1;
    }
    return 0;
  }

  List<int> _toVersionParts(String input) {
    final clean = input.split('+').first;
    return clean
        .split('.')
        .map(
          (part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
        )
        .toList();
  }
}
