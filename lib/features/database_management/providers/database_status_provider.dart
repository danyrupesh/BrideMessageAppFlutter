import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../onboarding/providers/database_discovery_provider.dart';
import '../../onboarding/services/database_discovery_service.dart';

const List<String> _genericBundleComponentKeys = <String>[
  'bible_en_kjv.db',
  'bible_ta_bsi.db',
  'sermons_en.db',
  'sermons_ta.db',
  'cod_english.db',
  'cod_tamil.db',
];

/// Tracks the status of a single database
class DatabaseStatusInfo {
  final DatabaseInfo available;
  final String? installedVersion;
  final bool isInstalled;
  final bool hasUpdate;
  final int estimatedSizeMB;

  const DatabaseStatusInfo({
    required this.available,
    required this.installedVersion,
    required this.isInstalled,
    required this.hasUpdate,
    required this.estimatedSizeMB,
  });

  /// Checks if an update is available
  bool get updateAvailable => hasUpdate && isInstalled;

  /// Formats size as human-readable string
  String get sizeText => estimatedSizeMB > 1024
      ? '${(estimatedSizeMB / 1024).toStringAsFixed(1)} GB'
      : '$estimatedSizeMB MB';

  /// Short status text for UI display
  String get statusText {
    if (!isInstalled) return 'Not installed';
    if (hasUpdate) return 'Update available';
    return 'Already updated';
  }

  /// Status color badge
  String get statusBadge {
    if (!isInstalled) return 'missing';
    if (hasUpdate) return 'update';
    return 'ok';
  }
}

/// Compares two semantic versions (e.g., "1.0" vs "2.1.3")
int _compareSemver(String v1, String v2) {
  try {
    final parts1 = v1.split('.').map(int.tryParse).whereType<int>().toList();
    final parts2 = v2.split('.').map(int.tryParse).whereType<int>().toList();

    for (int i = 0; i < (parts1.length > parts2.length ? parts1.length : parts2.length); i++) {
      final p1 = i < parts1.length ? parts1[i] : 0;
      final p2 = i < parts2.length ? parts2[i] : 0;
      if (p1 != p2) return p1.compareTo(p2);
    }
    return 0;
  } catch (_) {
    return 0; // If parsing fails, assume equal
  }
}

/// Maps database serverIDs to SharedPreferences version keys
String _versionPrefKey(String databaseId) {
  return 'onboarding.db.version.$databaseId';
}

String _updateVersionPrefKey(String databaseId) {
  return 'updates.db.version.$databaseId';
}

String? _firstNonEmptyVersion(SharedPreferences prefs, Iterable<String> keys) {
  for (final key in keys) {
    final value = prefs.getString(key)?.trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

String? _resolveInstalledVersion(SharedPreferences prefs, DatabaseInfo db) {
  final direct = _firstNonEmptyVersion(prefs, [
    _versionPrefKey(db.id),
    _updateVersionPrefKey(db.id),
    _updateVersionPrefKey('bridemessage_db'),
    _updateVersionPrefKey('bridemessage_db_en-ta'),
  ]);
  if (direct != null) {
    return direct;
  }

  if (!db.id.startsWith('bridemessage_db')) {
    return null;
  }

  final componentVersions = _genericBundleComponentKeys
      .map((fileName) => prefs.getString('onboarding.db.version.$fileName')?.trim())
      .whereType<String>()
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList();

  if (componentVersions.isEmpty) {
    return null;
  }

  componentVersions.sort(_compareSemver);
  return componentVersions.last;
}

/// Provider to get all database status information
/// Shows which databases are installed, which have updates, etc.
final databaseStatusProvider =
    FutureProvider.family<List<DatabaseStatusInfo>, String>(
  (ref, apiBaseUrl) async {
    final discovery = ref.watch(databaseDiscoveryProvider);
    final available = await discovery.availableDatabases(apiBaseUrl);

    // Get versions from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final installedVersions = <String, String>{};

    for (final db in available) {
      final resolvedVersion = _resolveInstalledVersion(prefs, db);
      if (resolvedVersion != null && resolvedVersion.isNotEmpty) {
        installedVersions[db.id] = resolvedVersion;
      }
    }

    // Build status for each database
    final statusList = available.map((db) {
      final installedVersion = installedVersions[db.id];
      final isInstalled = installedVersion != null;
      final hasUpdate = isInstalled && _compareSemver(installedVersion, db.version) < 0;

      return DatabaseStatusInfo(
        available: db,
        installedVersion: installedVersion,
        isInstalled: isInstalled,
        hasUpdate: hasUpdate,
        estimatedSizeMB: (db.fileSize / (1024 * 1024)).round(),
      );
    }).toList();

    // Sort: missing first, then updates available, then up-to-date
    statusList.sort((a, b) {
      if (!a.isInstalled && b.isInstalled) return -1;
      if (a.isInstalled && !b.isInstalled) return 1;
      if (a.hasUpdate && !b.hasUpdate) return -1;
      if (!a.hasUpdate && b.hasUpdate) return 1;
      return a.available.displayName.compareTo(b.available.displayName);
    });

    return statusList;
  },
);
