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
  'quotes_en.db',
  'prayer_quotes_en.db',
  'special_books_catalog_en.db',
  'special_books_catalog_ta.db',
];

final Map<String, List<String>> _standardDbAliases = {
  'bible_en': ['bible_en_kjv', 'bible_kjv', 'bible_en'],
  'bible_ta': ['bible_ta_bsi', 'bible_bsi', 'bible_ta'],
  'sermons_en': ['sermons_en'],
  'sermons_ta': ['sermons_ta'],
  'tracts_en': ['tracts_en'],
  'tracts_ta': ['tracts_ta'],
  'stories_en': ['stories_en'],
  'stories_ta': ['stories_ta'],
  'cod_en': ['cod_english'],
  'cod_ta': ['cod_tamil'],
  'prayer_quotes_en': ['prayer_quotes_en'],
  'quotes_en': ['quotes_en'],
  'church_ages_en': ['church_ages_en'],
  'church_ages_ta': ['church_ages_ta'],
  'special_books_catalog_en': ['special_books_catalog_en', 'special_books_en'],
  'special_books_catalog_ta': ['special_books_catalog_ta', 'special_books_ta'],
};

final Map<String, String> _standardDbDisplayNames = {
  'bible_en': 'Bible English',
  'bible_ta': 'Bible Tamil',
  'sermons_en': 'Sermons English',
  'sermons_ta': 'Sermons Tamil',
  'tracts_en': 'Tracts English',
  'tracts_ta': 'Tracts Tamil',
  'stories_en': 'Stories English',
  'stories_ta': 'Stories Tamil',
  'cod_en': 'COD English',
  'cod_ta': 'COD Tamil',
  'prayer_quotes_en': 'Prayer Quotes English',
  'quotes_en': 'English Quotes',
  'church_ages_en': 'Church Ages English',
  'church_ages_ta': 'Church Ages Tamil',
  'special_books_catalog_en': 'Special Books English',
  'special_books_catalog_ta': 'Special Books Tamil',
  'bridemessage_db_en-ta': 'Bride Message DB',
};

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
  final keysToCheck = <String>[
    _versionPrefKey(db.id),
    _updateVersionPrefKey(db.id),
  ];

  // Add keys for all possible aliases of this database
  final aliases = _standardDbAliases[db.id];
  if (aliases != null) {
    for (final alias in aliases) {
      keysToCheck.add('onboarding.db.version.$alias.db');
      keysToCheck.add('onboarding.db.version.$alias');
      keysToCheck.add('updates.db.version.$alias.db');
      keysToCheck.add('updates.db.version.$alias');
    }
  }

  // Find the highest version directly assigned to this specific database
  final directVersions = keysToCheck
      .map((k) => prefs.get(k)?.toString().trim())
      .whereType<String>()
      .where((v) => v.isNotEmpty)
      .toList();

  String? bestDirectVersion;
  if (directVersions.isNotEmpty) {
    directVersions.sort(_compareSemver);
    bestDirectVersion = directVersions.last;
  }

  // Find the highest version of any generic bundle
  final bundleKeys = [
    _updateVersionPrefKey('bridemessage_db'),
    _updateVersionPrefKey('bridemessage_db_en-ta'),
    _versionPrefKey('bridemessage_db'),
    _versionPrefKey('bridemessage_db_en-ta'),
  ];
  
  final bundleVersions = bundleKeys
      .map((k) => prefs.get(k)?.toString().trim())
      .whereType<String>()
      .where((v) => v.isNotEmpty)
      .toList();
      
  // For the bundle itself, we also derive version from its components if necessary
  if (db.id.startsWith('bridemessage_db')) {
    final componentVersions = _genericBundleComponentKeys
        .map((fileName) => prefs.get('onboarding.db.version.$fileName')?.toString().trim())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toList();
    bundleVersions.addAll(componentVersions);
  }

  String? bestBundleVersion;
  if (bundleVersions.isNotEmpty) {
    bundleVersions.sort(_compareSemver);
    bestBundleVersion = bundleVersions.last;
  }

  // If this IS the generic bundle, return its calculated version
  if (db.id.startsWith('bridemessage_db')) {
    return bestBundleVersion ?? bestDirectVersion;
  }

  // For individual databases, return the highest between its direct version and the bundle version
  if (bestDirectVersion != null && bestBundleVersion != null) {
    return _compareSemver(bestDirectVersion, bestBundleVersion) > 0 ? bestDirectVersion : bestBundleVersion;
  }
  
  return bestBundleVersion ?? bestDirectVersion;

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
        return installedFileIds.any((id) => id.endsWith('.db') || _standardDbAliases.values.any((aliases) => aliases.contains(id)));
      }
      
      final aliases = _standardDbAliases[dbId];
      if (aliases != null) {
        for (final alias in aliases) {
          if (installedFileIds.contains(alias)) return true;
        }
      }
      
      return false;
    }

    // Ensure all standard databases are present in the 'available' list, even if not in manifest
    final availableIds = available.map((d) => d.id).toSet();
    for (final standardId in _standardDbDisplayNames.keys) {
      if (!availableIds.contains(standardId)) {
        available.add(DatabaseInfo(
          id: standardId,
          displayName: _standardDbDisplayNames[standardId]!,
          version: '?',
          isMandatory: false,
          installStrategy: 'generic',
          downloadUrl: '', // Unknown unless in manifest
          sha256: '',
          fileSize: 0,
          publishedAt: '',
          bundledVersion: 1,
          isSingleDatabase: standardId != 'bridemessage_db_en-ta',
        ));
      }
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

    bool isAliasOfStandard(String fileId) {
      return _standardDbAliases.values.any((aliases) => aliases.contains(fileId));
    }

    // Add local-only ones (if any were not in server list)
    for (final id in installedFileIds) {
      if (id == 'app_metadata') continue;
      if (!statusMap.containsKey(id) && !isAliasOfStandard(id)) {
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
