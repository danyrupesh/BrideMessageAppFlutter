import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../database_manager.dart';
import 'installed_database_model.dart';

/// SQLite-backed registry for tracking installed databases.
/// Equivalent to Android's MetadataDatabase + InstalledDatabaseDao.
///
/// Stored in [app_metadata.db] inside the app's databases directory.
class InstalledDatabaseRegistry {
  static InstalledDatabaseRegistry? _instance;
  Database? _db;

  InstalledDatabaseRegistry._();

  factory InstalledDatabaseRegistry() {
    _instance ??= InstalledDatabaseRegistry._();
    return _instance!;
  }

  Future<Database> get _database async {
    if (_db != null && _db!.isOpen) return _db!;
    await _init();
    return _db!;
  }

  Future<void> _init() async {
    final dbDir = await DatabaseManager().getDatabaseDirectoryPath();
    final path = p.join(dbDir.path, 'app_metadata.db');
    _db = await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE installed_databases (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            code TEXT NOT NULL,
            display_name TEXT NOT NULL,
            language TEXT NOT NULL,
            installed_date INTEGER NOT NULL,
            file_size INTEGER NOT NULL,
            record_count INTEGER,
            is_default INTEGER NOT NULL DEFAULT 0
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE installed_databases ADD COLUMN record_count INTEGER',
          );
        }
      },
    );
  }

  /// Count installed entries by type.
  Future<int> countByType(DbType type) async {
    final db = await _database;
    final typeStr = _typeStr(type);
    final result = await db.rawQuery(
      'SELECT COUNT(*) FROM installed_databases WHERE type = ?',
      [typeStr],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get the default database for a given type + language.
  Future<InstalledDatabase?> getDefault(DbType type, String language) async {
    final db = await _database;
    final rows = await db.query(
      'installed_databases',
      where: 'type = ? AND is_default = 1 AND language = ?',
      whereArgs: [_typeStr(type), language],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return InstalledDatabase.fromMap(rows.first);
  }

  /// Get the first (any) installed database of given type + language (fallback).
  Future<InstalledDatabase?> getFirstByTypeAndLanguage(
    DbType type,
    String language,
  ) async {
    final db = await _database;
    final rows = await db.query(
      'installed_databases',
      where: 'type = ? AND language = ?',
      whereArgs: [_typeStr(type), language],
      orderBy: 'is_default DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return InstalledDatabase.fromMap(rows.first);
  }

  /// Get all installed databases of given type + language.
  Future<List<InstalledDatabase>> getByTypeAndLanguage(
    DbType type,
    String language,
  ) async {
    final db = await _database;
    final rows = await db.query(
      'installed_databases',
      where: 'type = ? AND language = ?',
      whereArgs: [_typeStr(type), language],
      orderBy: 'is_default DESC',
    );
    return rows.map(InstalledDatabase.fromMap).toList();
  }

  /// Get all installed databases.
  Future<List<InstalledDatabase>> getAll() async {
    final db = await _database;
    final rows = await db.query('installed_databases');
    return rows.map(InstalledDatabase.fromMap).toList();
  }

  /// Insert or replace an entry (replaces existing for same type+code).
  Future<void> upsert(InstalledDatabase installed) async {
    final db = await _database;
    await db.delete(
      'installed_databases',
      where: 'type = ? AND code = ?',
      whereArgs: [_typeStr(installed.type), installed.code],
    );
    await db.insert('installed_databases', installed.toMap());
  }

  /// Remove metadata for a specific type+code.
  Future<void> delete(DbType type, String code) async {
    final db = await _database;
    await db.delete(
      'installed_databases',
      where: 'type = ? AND code = ?',
      whereArgs: [_typeStr(type), code],
    );
  }

  /// Clear isDefault flag for all entries of given type + language.
  Future<void> clearDefaultForLanguage(DbType type, String language) async {
    final db = await _database;
    await db.update(
      'installed_databases',
      {'is_default': 0},
      where: 'type = ? AND language = ?',
      whereArgs: [_typeStr(type), language],
    );
  }

  /// Returns true if metadata has any Bible or Sermon entry.
  /// Optional legacy fallback scans known filenames when metadata is empty.
  Future<bool> hasAnyContent({bool allowFileFallback = false}) async {
    try {
      final bibleCount = await countByType(DbType.bible);
      final sermonCount = await countByType(DbType.sermon);
      if (bibleCount > 0 || sermonCount > 0) return true;
    } catch (e) {
      debugPrint('InstalledDatabaseRegistry.hasAnyContent error: $e');
    }
    if (allowFileFallback) {
      return _fileScanFallback();
    }
    return false;
  }

  /// Scans for known standard DB filenames as a fallback.
  Future<bool> _fileScanFallback() async {
    try {
      final dbDir = await DatabaseManager().getDatabaseDirectoryPath();
      const knownFiles = [
        'bible_kjv.db',
        'bible_bsi.db',
        'sermons_en.db',
        'sermons_ta.db',
      ];
      for (final name in knownFiles) {
        if (await File(p.join(dbDir.path, name)).exists()) return true;
      }
    } catch (_) {}
    return false;
  }

  String _typeStr(DbType type) => type == DbType.bible ? 'BIBLE' : 'SERMON';
}
