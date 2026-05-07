import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'metadata/installed_database_model.dart';
import 'metadata/installed_database_registry.dart';

/// Manages multiple SQLite databases for the Bride Message App
/// Handles caching connections, read-only modes, and path resolution.
class DatabaseManager {
  static final DatabaseManager _instance = DatabaseManager._internal();
  factory DatabaseManager() => _instance;
  DatabaseManager._internal();

  // Cache open databases (Key = db file name)
  final Map<String, Database> _databases = {};
  final Map<String, Future<Database>> _openingDatabases = {};

  /// Clear cached database instances
  void clearCache() {
    for (final db in _databases.values) {
      if (db.isOpen) db.close();
    }
    _databases.clear();
    _openingDatabases.clear();
  }

  /// Get the full file path for a database file (for use with sqlite3 etc.)
  Future<String> getDatabasePath(String fileName) async {
    final dbDir = await getDatabaseDirectoryPath();
    return p.join(dbDir.path, fileName);
  }

  /// Get the physical directory where databases are stored
  Future<Directory> getDatabaseDirectoryPath() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dbDir = Directory(p.join(docsDir.path, 'databases'));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }
    return dbDir;
  }

  /// Open a database in read-only mode, or return cached instance
  Future<Database> getDatabase(String fileName) async {
    if (_databases.containsKey(fileName)) {
      return _databases[fileName]!;
    }

    final opening = _openingDatabases[fileName];
    if (opening != null) {
      return opening;
    }

    final openFuture = _openDatabaseInternal(fileName);
    _openingDatabases[fileName] = openFuture;
    try {
      final db = await openFuture;
      _databases[fileName] = db;
      return db;
    } finally {
      _openingDatabases.remove(fileName);
    }
  }

  Future<Database> _openDatabaseInternal(String fileName) async {
    if (_databases.containsKey(fileName)) {
      return _databases[fileName]!;
    }

    final dbDir = await getDatabaseDirectoryPath();
    final path = p.join(dbDir.path, fileName);

    if (!await File(path).exists()) {
      throw FileSystemException("Database file not found", path);
    }

    // Since these databases are massive and prepackaged, open them in ReadOnly mode
    // sqflite handles native execution asynchronously on a background thread,
    // guaranteeing smooth UI framing without needing manual Dart Isolates.
    return openDatabase(path, readOnly: true, singleInstance: true);
  }

  /// Close and remove a cached database
  Future<void> closeDatabase(String fileName) async {
    final db = _databases.remove(fileName);
    if (db != null && db.isOpen) {
      await db.close();
    }
  }

  /// Logs SQLite version and compile options (e.g. FTS5) for the engine used by sqflite.
  /// Call once at startup to diagnose "no such module: fts5" on device.
  static Future<void> logSqliteDiagnostics() async {
    try {
      final dbDir = await DatabaseManager().getDatabaseDirectoryPath();
      final entities = await dbDir.list().toList();
      final dbFiles = entities.where((e) => e.path.endsWith('.db')).toList();
      if (dbFiles.isEmpty) {
        debugPrint('SqliteDiagnostics: No .db files in ${dbDir.path}');
        return;
      }
      final firstPath = dbFiles.first.path;
      final db = await openDatabase(firstPath, readOnly: true);
      try {
        final version = await db.rawQuery('SELECT sqlite_version()');
        final opts = await db.rawQuery('PRAGMA compile_options');
        debugPrint(
          'SqliteDiagnostics: version=${version.isNotEmpty ? version.first.values.first : "?"}',
        );
        debugPrint(
          'SqliteDiagnostics: compile_options=${opts.map((r) => r.values.first).toList()}',
        );
      } finally {
        await db.close();
      }
    } catch (e) {
      debugPrint('SqliteDiagnostics: $e');
    }
  }

  /// Safely delete a database and its temp files (-wal, -shm)
  Future<void> deleteDatabaseFiles(String fileName) async {
    await closeDatabase(fileName);

    final dbDir = await getDatabaseDirectoryPath();
    final path = p.join(dbDir.path, fileName);

    final mainFile = File(path);
    final walFile = File('$path-wal');
    final shmFile = File('$path-shm');
    final journalFile = File('$path-journal');

    if (await mainFile.exists()) await mainFile.delete();
    if (await walFile.exists()) await walFile.delete();
    if (await shmFile.exists()) await shmFile.delete();
    if (await journalFile.exists()) await journalFile.delete();
  }

  /// Delete a database by ID: removes files and clears version tracking
  Future<void> deleteDatabase(String databaseId) async {
    // Common database file names to delete
    final possibleFileNames = [
      '$databaseId.db',
      'bridemessage_db_en-ta.db',
      'bridemessage_db_en.db',
      'bridemessage_db_ta.db',
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

    // Delete physical files
    for (final fileName in possibleFileNames) {
      try {
        await closeDatabase(fileName);
        await deleteDatabaseFiles(fileName);
      } catch (e) {
        debugPrint('Could not delete file $fileName: $e');
      }
    }

    // Clear version tracking from SharedPreferences using comprehensive key scanning
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();
      
      final patterns = [
        'onboarding.db.version.$databaseId',
        'updates.db.version.$databaseId',
        'onboarding.db.version.${databaseId.replaceAll('_', '.')}',
        'onboarding.db.version.$databaseId.db',
        'db_version_$databaseId',
        'installed_$databaseId',
      ];

      for (final key in allKeys) {
        bool shouldRemove = false;
        if (key.contains(databaseId)) {
          shouldRemove = true;
        } else {
          for (final pattern in patterns) {
            if (key == pattern) {
              shouldRemove = true;
              break;
            }
          }
        }
        
        if (shouldRemove) {
          debugPrint('Registry: Removing SharedPreferences key: $key');
          await prefs.remove(key);
        }
      }
      
      // Explicitly remove common bundle-related keys if this is a bundle component
      if (databaseId.contains('church_ages') || databaseId.contains('sermons') || databaseId.contains('bible')) {
         await prefs.remove('onboarding.db.version.bridemessage_db');
         await prefs.remove('onboarding.db.version.bridemessage_db_en-ta');
      }

    } catch (e) {
      debugPrint('Could not clear SharedPreferences: $e');
    }

    // Clear from metadata registry if applicable
    try {
      final registry = InstalledDatabaseRegistry();
      // Try to delete from ALL possible categories just in case of mis-registration
      for (final type in DbType.values) {
        // Try with full ID
        await registry.delete(type, databaseId);
        
        // Try with language code suffix if applicable
        if (databaseId.contains('_')) {
          final code = databaseId.split('_').last;
          await registry.delete(type, code);
        }
      }
    } catch (e) {
      debugPrint('Could not clear registry for $databaseId: $e');
    }

    // Finally, clear cache to ensure no stale connections remain
    clearCache();
  }

  /// List all database files currently on the device
  Future<List<File>> listInstalledDatabaseFiles() async {
    final dbDir = await getDatabaseDirectoryPath();
    if (!await dbDir.exists()) return [];
    
    final entities = await dbDir.list().toList();
    return entities
        .whereType<File>()
        .where((f) => f.path.endsWith('.db'))
        .toList();
  }
}

