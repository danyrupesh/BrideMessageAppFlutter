import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../database_manager.dart';
import '../models/special_book_models.dart';

/// Tracks which per-book content databases have been downloaded and installed.
/// Stored in app_metadata.db alongside the existing installed_databases table.
class SpecialBookDownloadRegistry {
  static SpecialBookDownloadRegistry? _instance;
  Database? _db;

  SpecialBookDownloadRegistry._();

  factory SpecialBookDownloadRegistry() {
    _instance ??= SpecialBookDownloadRegistry._();
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

    // Share app_metadata.db with InstalledDatabaseRegistry (same version 3).
    _db = await openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS installed_databases (
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
        await _createSpecialBookDownloadsTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          final columns = await db.rawQuery(
            'PRAGMA table_info(installed_databases)',
          );
          final hasRecordCount = columns.any(
            (row) =>
                (row['name']?.toString().toLowerCase() ?? '') == 'record_count',
          );
          if (!hasRecordCount) {
            await db.execute(
              'ALTER TABLE installed_databases ADD COLUMN record_count INTEGER',
            );
          }
        }
        if (oldVersion < 3) {
          await _createSpecialBookDownloadsTable(db);
        }
      },
    );
  }

  static Future<void> _createSpecialBookDownloadsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS special_book_downloads (
        book_id          TEXT NOT NULL,
        lang             TEXT NOT NULL,
        content_version  INTEGER,
        downloaded_at    TEXT,
        local_db_path    TEXT NOT NULL,
        PRIMARY KEY (book_id, lang)
      )
    ''');
  }

  Future<SpecialBookDownload?> get(String bookId, String lang) async {
    try {
      final db = await _database;
      final rows = await db.query(
        'special_book_downloads',
        where: 'book_id = ? AND lang = ?',
        whereArgs: [bookId, lang],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return SpecialBookDownload.fromMap(rows.first);
    } catch (e) {
      debugPrint('SpecialBookDownloadRegistry.get error: $e');
      return null;
    }
  }

  Future<List<SpecialBookDownload>> getAll() async {
    try {
      final db = await _database;
      final rows = await db.query('special_book_downloads');
      return rows.map(SpecialBookDownload.fromMap).toList();
    } catch (e) {
      debugPrint('SpecialBookDownloadRegistry.getAll error: $e');
      return [];
    }
  }

  Future<bool> isDownloaded(String bookId, String lang) async {
    final record = await get(bookId, lang);
    if (record == null) return false;
    return File(record.localDbPath).existsSync();
  }

  Future<void> upsert(SpecialBookDownload download) async {
    final db = await _database;
    await db.insert(
      'special_book_downloads',
      download.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> remove(String bookId, String lang) async {
    final db = await _database;
    await db.delete(
      'special_book_downloads',
      where: 'book_id = ? AND lang = ?',
      whereArgs: [bookId, lang],
    );
  }
}
