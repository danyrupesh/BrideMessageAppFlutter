import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../onboarding/providers/database_discovery_provider.dart';
import '../../onboarding/services/database_discovery_service.dart';
import 'local_databases_provider.dart';

const List<String> _genericBundleComponentKeys = <String>[
  'bible_en_kjv.db',
  'bible_ta_bsi.db',
  'sermons_en.db',
  'sermons_ta.db',
  'cod_english.db',
  'cod_tamil.db',
  'tracts_en.db',
  'tracts_ta.db',
  'stories_en.db',
  'stories_ta.db',
  'church_ages_en.db',
  'church_ages_ta.db',
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
    final value = prefs.get(key)?.toString().trim();
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
      .map((fileName) => prefs.get('onboarding.db.version.$fileName')?.toString().trim())
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
    
    // Fetch available databases from server, but don't fail if server is down
    List<DatabaseInfo> available = [];
    try {
      available = await discovery.availableDatabases(apiBaseUrl);
    } catch (e) {
      // If server is down, we'll try to reconstruct what we can from local info
      available = [];
    }

    // Get actually installed files from disk
    final installedFilesAsync = ref.watch(installedDatabaseIdsProvider);
    final installedFileIds = installedFilesAsync.value ?? <String>{};

    // Get versions from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final installedVersions = <String, String>{};

    // Helper to check if a database is actually installed on disk
    bool isPhysicallyInstalled(String dbId) {
      if (installedFileIds.contains(dbId)) return true;
      if (dbId == 'bridemessage_db_en-ta' || dbId == 'bridemessage_db') {
        // Bundles are installed if their components are present
        return installedFileIds.any((id) => id.endsWith('.db'));
      }
      return false;
    }

    // Identify installed databases and their versions
    final allKnownIds = available.map((d) => d.id).toSet().union(installedFileIds);
    
    for (final id in allKnownIds) {
      final db = available.firstWhere((d) => d.id == id, 
          orElse: () => DatabaseInfo(
            id: id,
            displayName: id.replaceAll('_', ' ').replaceAll('.db', '').toUpperCase(),
            version: '?',
            isMandatory: false,
            installStrategy: 'generic',
            downloadUrl: '',
            sha256: '',
            fileSize: 0,
            publishedAt: '',
            bundledVersion: 0,
            isSingleDatabase: true,
          ));
      
      final resolvedVersion = _resolveInstalledVersion(prefs, db);
      if (resolvedVersion != null && resolvedVersion.isNotEmpty) {
        installedVersions[db.id] = resolvedVersion;
      } else if (isPhysicallyInstalled(id)) {
        installedVersions[id] = 'Installed';
      }
    }

    // Build status for each database
    // Start with server available ones
    final statusMap = <String, DatabaseStatusInfo>{};
    
    for (final db in available) {
      final installedVersion = installedVersions[db.id];
      final isInstalled = installedVersion != null || isPhysicallyInstalled(db.id);
      final hasUpdate = isInstalled && installedVersion != null && db.version != '?' && _compareSemver(installedVersion, db.version) < 0;

      statusMap[db.id] = DatabaseStatusInfo(
        available: db,
        installedVersion: installedVersion ?? (isInstalled ? 'Unknown' : null),
        isInstalled: isInstalled,
        hasUpdate: hasUpdate,
        estimatedSizeMB: (db.fileSize / (1024 * 1024)).round(),
      );
    }

    // Add local-only ones (if any were not in server list)
    for (final id in installedFileIds) {
      if (!statusMap.containsKey(id)) {
        statusMap[id] = DatabaseStatusInfo(
          available: DatabaseInfo(
            id: id,
            displayName: id.replaceAll('_', ' ').replaceAll('.db', '').toUpperCase(),
            version: 'Local',
            isMandatory: false,
            installStrategy: 'generic',
            downloadUrl: '',
            sha256: '',
            fileSize: 0,
            publishedAt: '',
            bundledVersion: 0,
            isSingleDatabase: true,
          ),
          installedVersion: installedVersions[id] ?? 'Installed',
          isInstalled: true,
          hasUpdate: false,
          estimatedSizeMB: 0,
        );
      }
    }

    final statusList = statusMap.values.toList();

    // Sort: updates available first, then missing, then up-to-date
    statusList.sort((a, b) {
      if (a.hasUpdate && !b.hasUpdate) return -1;
      if (!a.hasUpdate && b.hasUpdate) return 1;
      if (!a.isInstalled && b.isInstalled) return 1; // Show missing at bottom of management
      if (a.isInstalled && !b.isInstalled) return -1; // Show installed at top of management
      return a.available.displayName.compareTo(b.available.displayName);
    });

    return statusList;
  },
);
