import 'dart:async';
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
import 'database_patch_applier.dart';
import '../../features/onboarding/services/selective_database_importer.dart';
import '../../features/songs/services/hymns_importer.dart';

const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://api.endtimebride.in',
);
const String kAppUpdatesManifestUrl =
    '$kApiBaseUrl/database/updates/app_version.json';
const String kDatabaseUpdatesManifestUrl =
    '$kApiBaseUrl/database/updates/db_version.json';

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
  final String version;
  final String? updateMessage;
  final bool mandatory;
  final String url;
  final String installStrategy;
  final DatabasePatchInfo? patch;

  const DatabaseUpdateInfo({
    required this.id,
    required this.displayName,
    required this.version,
    required this.updateMessage,
    required this.mandatory,
    required this.url,
    required this.installStrategy,
    this.patch,
  });
}

class DatabasePatchInfo {
  final String fromVersion;
  final String? targetDbFileName;
  final String? manifestUrl;
  final String? downloadUrl;
  final String? sha256;
  final int? size;
  final String type;

  const DatabasePatchInfo({
    required this.fromVersion,
    required this.targetDbFileName,
    required this.manifestUrl,
    required this.downloadUrl,
    required this.sha256,
    required this.size,
    required this.type,
  });
}

class UpdateService {
  static const String kPrimaryDatabasePackageId = 'bridemessage_db_en-ta';
  static const List<String> _legacyDatabasePackageIds = ['bridemessage_db'];

  final Dio _dio;

  UpdateService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(minutes: 5),
              receiveTimeout: const Duration(minutes: 10),
            ),
          );

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
      final version = (entry['version'] ?? '').toString().trim();
      final rawUrl = (entry['url'] ?? '').toString().trim();
      final zipFileName = (entry['zipFileName'] ?? entry['zip_file_name'] ?? '')
          .toString()
          .trim();
      final url = _resolveDatabaseDownloadUrl(
        rawUrl: rawUrl,
        zipFileName: zipFileName,
      );
      final mandatory = _parseBool(entry['mandatory']);
      final updateMessage =
          (entry['updateMessage'] ??
                  entry['notes'] ??
                  entry['description'] ??
                  '')
              .toString()
              .trim();
      final installStrategy =
          (entry['installStrategy'] ??
                  entry['install_strategy'] ??
                  entry['strategy'] ??
                  'auto')
              .toString()
              .trim()
              .toLowerCase();
      final patch = _parsePatchInfo(entry);
      final bundledVersion =
          _parseInt(entry['bundledVersion'] ?? entry['defaultVersion']) ?? 0;

      if (id.isEmpty || version.isEmpty || url.isEmpty) continue;

      // Fresh installs should not receive update prompts before a DB exists.
      final isInstalled = await _isDatabaseInstalledLocally(id);
      if (!isInstalled) continue;

      final localVersion = _getStoredDbVersion(
        prefs,
        id,
        defaultValue: bundledVersion > 0 ? bundledVersion.toString() : '0',
      );
      if (_compareSemver(version, localVersion) > 0) {
        updates.add(
          DatabaseUpdateInfo(
            id: id,
            displayName: displayName.isEmpty ? id : displayName,
            version: version,
            updateMessage: updateMessage.isEmpty ? null : updateMessage,
            mandatory: mandatory,
            url: url,
            installStrategy: installStrategy,
            patch: patch,
          ),
        );
      }
    }

    updates.sort((a, b) => a.id.compareTo(b.id));
    return _dedupeAndPrioritizeUpdates(updates);
  }

  List<DatabaseUpdateInfo> _dedupeAndPrioritizeUpdates(
    List<DatabaseUpdateInfo> updates,
  ) {
    if (updates.isEmpty) return const <DatabaseUpdateInfo>[];

    // Keep latest entry per id if duplicates are present.
    final byId = <String, DatabaseUpdateInfo>{};
    for (final item in updates) {
      final existing = byId[item.id];
      if (existing == null ||
          _compareSemver(item.version, existing.version) > 0) {
        byId[item.id] = item;
      }
    }

    final items = byId.values.toList(growable: false);

    // If any specific stream updates exist, suppress generic package updates
    // from the prompt to avoid duplicate/noisy messaging.
    final hasSpecificStream = items.any(
      (item) =>
          item.id != kPrimaryDatabasePackageId &&
          !_legacyDatabasePackageIds.contains(item.id),
    );

    final filtered = hasSpecificStream
        ? items
              .where(
                (item) =>
                    item.id != kPrimaryDatabasePackageId &&
                    !_legacyDatabasePackageIds.contains(item.id),
              )
              .toList(growable: false)
        : items;

    filtered.sort((a, b) => a.id.compareTo(b.id));
    return filtered;
  }

  /// Returns the installed DB package version shown to users in settings.
  ///
  /// Priority:
  /// 1) Stored value in SharedPreferences (`updates.db.version.<id>`)
  /// 2) bundledVersion from manifest entry for current package id
  /// 3) null when no local/manifest version can be determined
  Future<String?> getCurrentDatabaseVersion() async {
    final prefs = await SharedPreferences.getInstance();

    for (final id in [
      kPrimaryDatabasePackageId,
      ..._legacyDatabasePackageIds,
    ]) {
      final key = _dbVersionKey(id);
      if (!prefs.containsKey(key)) continue;

      final value = _getStoredDbVersion(prefs, id, defaultValue: '0');
      if (value.isNotEmpty && value != '0') {
        return value;
      }
    }

    final payload = await _fetchJson(kDatabaseUpdatesManifestUrl);
    if (payload == null) return null;

    final entries = _extractDatabaseEntries(payload);
    for (final entry in entries) {
      final id = (entry['id'] ?? '').toString().trim();
      final isKnownId =
          id == kPrimaryDatabasePackageId ||
          _legacyDatabasePackageIds.contains(id);
      if (!isKnownId) continue;

      final bundledVersion = _parseInt(
        entry['bundledVersion'] ?? entry['defaultVersion'],
      );
      if (bundledVersion != null && bundledVersion > 0) {
        return bundledVersion.toString();
      }
    }

    return null;
  }

  Future<void> applyDatabaseUpdates(
    List<DatabaseUpdateInfo> updates, {
    void Function(String message)? onStatus,
    void Function(int received, int total)? onReceiveProgress,
    CancelToken? cancelToken,
  }) async {
    if (updates.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final importer = SelectiveDatabaseImporter();
    final patchApplier = DatabasePatchApplier();

    for (final update in updates) {
      _throwIfCancelled(cancelToken, path: update.url);
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
      final localVersion = _getStoredDbVersion(
        prefs,
        update.id,
        defaultValue: '0',
      );
      final shouldUsePatch =
          update.patch != null &&
          update.patch!.fromVersion == localVersion &&
          update.patch!.downloadUrl != null &&
          update.patch!.targetDbFileName != null &&
          update.patch!.type == 'sql_changelog';
      final patchDownloadUrl = update.patch?.downloadUrl;
      var usePatchDownload = shouldUsePatch;

      try {
        if (update.patch != null && !shouldUsePatch) {
          onStatus?.call(
            'Patch metadata detected for ${update.displayName}; using full package fallback...',
          );
        }

        if (shouldUsePatch) {
          onStatus?.call('Downloading patch for ${update.displayName}...');
          await _dio
              .download(
                patchDownloadUrl!,
                zipPath,
                cancelToken: cancelToken,
                onReceiveProgress: (received, total) {
                  onReceiveProgress?.call(received, total);

                  if (total > 0) {
                    final percent = (received / total * 100).clamp(0, 100);
                    onStatus?.call(
                      'Downloading patch ${update.displayName}... ${percent.toStringAsFixed(0)}%',
                    );
                  } else {
                    final mb = received / (1024 * 1024);
                    onStatus?.call(
                      'Downloading patch ${update.displayName}... ${mb.toStringAsFixed(1)} MB',
                    );
                  }
                },
                options: Options(responseType: ResponseType.bytes),
              )
              .timeout(
                const Duration(minutes: 12),
                onTimeout: () => throw TimeoutException(
                  'Patch download timed out for ${update.displayName}.',
                ),
              );

          _throwIfCancelled(cancelToken, path: patchDownloadUrl);

          final patchResult = await patchApplier.applySqlChangelogBundle(
            zipPath: zipPath,
            targetDbFileName: update.patch!.targetDbFileName!,
            baseVersion: localVersion,
            targetVersion: update.version,
            expectedZipSha256: update.patch!.sha256,
            onStatus: (message) => onStatus?.call(message),
            cancelToken: cancelToken,
          );

          if (patchResult.success) {
            await prefs.setString(_dbVersionKey(update.id), update.version);
            onStatus?.call(patchResult.message);
            continue;
          }

          onStatus?.call(
            'Patch apply failed for ${update.displayName}; falling back to full package...',
          );
          usePatchDownload = false;
        }

        onStatus?.call('Downloading ${update.displayName}...');
        await _dio
            .download(
              update.url,
              zipPath,
              cancelToken: cancelToken,
              onReceiveProgress: (received, total) {
                onReceiveProgress?.call(received, total);

                if (total > 0) {
                  final percent = (received / total * 100).clamp(0, 100);
                  onStatus?.call(
                    '${usePatchDownload ? 'Downloading patch' : 'Downloading'} ${update.displayName}... ${percent.toStringAsFixed(0)}%',
                  );
                } else {
                  final mb = received / (1024 * 1024);
                  onStatus?.call(
                    '${usePatchDownload ? 'Downloading patch' : 'Downloading'} ${update.displayName}... ${mb.toStringAsFixed(1)} MB',
                  );
                }
              },
              options: Options(responseType: ResponseType.bytes),
            )
            .timeout(
              const Duration(minutes: 12),
              onTimeout: () => throw TimeoutException(
                'Download timed out for ${update.displayName}.',
              ),
            );

        _throwIfCancelled(cancelToken, path: update.url);

        onStatus?.call('Installing ${update.displayName}...');
        final shouldUseHymnsInstaller =
            _useHymnsInstaller(update) || await _looksLikeHymnsZip(zipPath);

        if (shouldUseHymnsInstaller) {
          final hymnsImporter = HymnsImporter();
          await hymnsImporter.installFromZip(
            zipPath: zipPath,
            onProgress: (_, message) => onStatus?.call(message),
          );
        } else if (_isSingleStreamDatabaseId(update.id)) {
          await _installSingleStreamDatabaseFromZip(
            zipPath: zipPath,
            id: update.id,
            importer: importer,
            onStatus: onStatus,
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

        _throwIfCancelled(cancelToken, path: update.url);

        await prefs.setString(_dbVersionKey(update.id), update.version);
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

  DatabasePatchInfo? _parsePatchInfo(Map<String, dynamic> entry) {
    final patchRaw = entry['patch'];
    Map<String, dynamic>? patch;
    if (patchRaw is Map) {
      patch = patchRaw.map((key, value) => MapEntry(key.toString(), value));
    }

    final fromVersion =
        (patch?['fromVersion'] ?? entry['delta_from_version'] ?? '')
            .toString()
            .trim();
    if (fromVersion.isEmpty) return null;

    final targetDbFileName =
        (patch?['targetDbFileName'] ??
                entry['patch_target_db_file_name'] ??
                entry['target_db_file_name'] ??
                '')
            .toString()
            .trim();

    final manifestUrl = (patch?['manifestUrl'] ?? patch?['url'] ?? '')
        .toString()
        .trim();
    final downloadUrl = (patch?['downloadUrl'] ?? entry['url_delta'] ?? '')
        .toString()
        .trim();
    final sha256 = (patch?['sha256'] ?? entry['checksum_delta'] ?? '')
        .toString()
        .trim();
    final size = _parseInt(patch?['size'] ?? entry['delta_size']);
    final type = (patch?['type'] ?? entry['patch_type'] ?? 'sql_changelog')
        .toString()
        .trim()
        .toLowerCase();

    return DatabasePatchInfo(
      fromVersion: fromVersion,
      targetDbFileName: targetDbFileName.isEmpty ? null : targetDbFileName,
      manifestUrl: manifestUrl.isEmpty ? null : manifestUrl,
      downloadUrl: downloadUrl.isEmpty ? null : downloadUrl,
      sha256: sha256.isEmpty ? null : sha256,
      size: size,
      type: type,
    );
  }

  String? get _platformKey {
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    return null;
  }

  String _dbVersionKey(String id) => 'updates.db.version.$id';

  void _throwIfCancelled(CancelToken? token, {required String path}) {
    if (token?.isCancelled != true) return;
    throw DioException(
      requestOptions: RequestOptions(path: path),
      type: DioExceptionType.cancel,
      error: 'Database update cancelled by user.',
    );
  }

  String _getStoredDbVersion(
    SharedPreferences prefs,
    String id, {
    required String defaultValue,
  }) {
    final key = _dbVersionKey(id);
    final raw = prefs.get(key);
    if (raw is String && raw.trim().isNotEmpty) {
      return raw.trim();
    }
    if (raw is int) {
      return raw.toString();
    }
    if (raw is double) {
      return raw.toString();
    }
    return defaultValue;
  }

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

    if (id == 'tracts_en' || id == 'tracts_ta') {
      final dbDir = await DatabaseManager().getDatabaseDirectoryPath();
      final fileName = id == 'tracts_en' ? 'tracts_en.db' : 'tracts_ta.db';
      return File(p.join(dbDir.path, fileName)).exists();
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

  bool _isSingleStreamDatabaseId(String id) {
    return const <String>{
      'bible_en',
      'bible_ta',
      'sermons_en',
      'sermons_ta',
      'cod_en',
      'cod_ta',
      'tracts_en',
      'tracts_ta',
      'stories_en',
      'stories_ta',
    }.contains(id);
  }

  Future<void> _installSingleStreamDatabaseFromZip({
    required String zipPath,
    required String id,
    required SelectiveDatabaseImporter importer,
    void Function(String message)? onStatus,
  }) async {
    final archive = ZipDecoder().decodeBytes(await File(zipPath).readAsBytes());
    final spec = _singleDbSpecForId(id);
    if (spec == null) {
      throw StateError('Unsupported single database id: $id');
    }
    final expectedDbName = spec.expectedDbName;
    final entry = archive.firstWhere(
      (f) => f.isFile && p.basename(f.name).toLowerCase() == expectedDbName,
      orElse: () => ArchiveFile('', 0, []),
    );
    if (entry.name.isEmpty) {
      throw StateError('ZIP does not contain $expectedDbName');
    }

    final tempRoot = await getTemporaryDirectory();
    final tempDbFile = File(
      p.join(
        tempRoot.path,
        'single_db_import_${id}_${DateTime.now().millisecondsSinceEpoch}.db',
      ),
    );
    await tempDbFile.writeAsBytes(entry.content as List<int>, flush: true);
    try {
      late final ImportResult result;
      if (id == 'tracts_en' || id == 'tracts_ta') {
        result = await importer.importTractsDatabase(
          sourceFile: tempDbFile,
          languageCode: spec.langCode!,
          displayName: spec.displayName,
          onProgress: (_, message) => onStatus?.call(message),
        );
      } else if (id == 'stories_en' || id == 'stories_ta') {
        result = await importer.importStoriesDatabase(
          sourceFile: tempDbFile,
          languageCode: spec.langCode!,
          displayName: spec.displayName,
          onProgress: (_, message) => onStatus?.call(message),
        );
      } else if (id == 'sermons_en' || id == 'sermons_ta') {
        result = await importer.importSermons(
          sourceFile: tempDbFile,
          languageCode: spec.langCode!,
          displayName: spec.displayName,
          setAsDefault: true,
          onProgress: (_, message) => onStatus?.call(message),
        );
      } else if (id == 'bible_en' || id == 'bible_ta') {
        result = await importer.importBible(
          sourceFile: tempDbFile,
          versionCode: spec.bibleVersionCode!,
          displayName: spec.displayName,
          language: spec.langCode!,
          setAsDefault: true,
          onProgress: (_, message) => onStatus?.call(message),
        );
      } else if (id == 'cod_en' || id == 'cod_ta') {
        result = await importer.importCodDatabase(
          sourceFile: tempDbFile,
          targetDbFileName: spec.expectedDbName,
          displayName: spec.displayName,
          onProgress: (_, message) => onStatus?.call(message),
        );
      } else {
        throw StateError('Unsupported single database id: $id');
      }

      if (!result.success) {
        throw StateError(result.message);
      }
    } finally {
      if (await tempDbFile.exists()) {
        await tempDbFile.delete();
      }
    }
  }

  _SingleDbSpec? _singleDbSpecForId(String id) {
    switch (id) {
      case 'bible_en':
        return const _SingleDbSpec(
          expectedDbName: 'bible_en_kjv.db',
          displayName: 'English Bible',
          langCode: 'en',
          bibleVersionCode: 'kjv',
        );
      case 'bible_ta':
        return const _SingleDbSpec(
          expectedDbName: 'bible_ta_bsi.db',
          displayName: 'Tamil Bible',
          langCode: 'ta',
          bibleVersionCode: 'bsi',
        );
      case 'sermons_en':
        return const _SingleDbSpec(
          expectedDbName: 'sermons_en.db',
          displayName: 'English Sermons',
          langCode: 'en',
        );
      case 'sermons_ta':
        return const _SingleDbSpec(
          expectedDbName: 'sermons_ta.db',
          displayName: 'Tamil Sermons',
          langCode: 'ta',
        );
      case 'cod_en':
        return const _SingleDbSpec(
          expectedDbName: 'cod_english.db',
          displayName: 'COD English',
        );
      case 'cod_ta':
        return const _SingleDbSpec(
          expectedDbName: 'cod_tamil.db',
          displayName: 'COD Tamil',
        );
      case 'tracts_en':
        return const _SingleDbSpec(
          expectedDbName: 'tracts_en.db',
          displayName: 'English Tracts',
          langCode: 'en',
        );
      case 'tracts_ta':
        return const _SingleDbSpec(
          expectedDbName: 'tracts_ta.db',
          displayName: 'Tamil Tracts',
          langCode: 'ta',
        );
      case 'stories_en':
        return const _SingleDbSpec(
          expectedDbName: 'stories_en.db',
          displayName: 'English Stories',
          langCode: 'en',
        );
      case 'stories_ta':
        return const _SingleDbSpec(
          expectedDbName: 'stories_ta.db',
          displayName: 'Tamil Stories',
          langCode: 'ta',
        );
      default:
        return null;
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

  String _resolveDatabaseDownloadUrl({
    required String rawUrl,
    required String zipFileName,
  }) {
    final localBase = kApiBaseUrl.trim().replaceAll(RegExp(r'/$'), '');
    final localUri = Uri.tryParse(localBase);
    final remoteUri = Uri.tryParse(rawUrl);

    // Prefer explicit local API host URL when zip filename is available.
    // This avoids stale/prod URLs in db_version.json during dev testing.
    if (zipFileName.isNotEmpty && localUri != null) {
      if (remoteUri == null || remoteUri.host != localUri.host) {
        return '$localBase/database/${Uri.encodeComponent(zipFileName)}';
      }
    }

    return rawUrl;
  }
}

class _SingleDbSpec {
  final String expectedDbName;
  final String displayName;
  final String? langCode;
  final String? bibleVersionCode;

  const _SingleDbSpec({
    required this.expectedDbName,
    required this.displayName,
    this.langCode,
    this.bibleVersionCode,
  });
}
