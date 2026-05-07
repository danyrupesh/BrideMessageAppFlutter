import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'database_manager.dart';
import 'models/special_book_models.dart';

/// Reads from a downloaded per-book content DB.
/// File: databases/special_book_{bookId}_{lang}.db
/// Only available after the user downloads the per-book content ZIP.
class SpecialBooksContentRepository {
  SpecialBooksContentRepository({
    required this.bookId,
    required this.lang,
  });

  final String bookId;
  final String lang;

  String get dbFileName {
    final safeId = bookId.replaceAll(RegExp(r'[^a-z0-9_\-]'), '_');
    return 'special_book_${safeId}_$lang.db';
  }

  final DatabaseManager _dbManager = DatabaseManager();

  Future<Database?> get _db async {
    try {
      return await _dbManager.getDatabase(dbFileName);
    } catch (_) {
      return null;
    }
  }

  Future<bool> get isAvailable async {
    final db = await _db;
    if (db == null) return false;
    try {
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='chapters'",
      );
      return tables.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<List<BookChapterContent>> listChapters() async {
    final db = await _db;
    if (db == null) return [];
    try {
      final rows = await db.rawQuery(
        'SELECT * FROM chapters WHERE book_id = ? ORDER BY order_index ASC',
        [bookId],
      );
      return rows.map(BookChapterContent.fromMap).toList();
    } catch (e) {
      debugPrint('SpecialBooksContentRepository.listChapters error: $e');
      return [];
    }
  }

  Future<BookChapterContent?> getChapter(String chapterId) async {
    final db = await _db;
    if (db == null) return null;
    try {
      final rows = await db.query(
        'chapters',
        where: 'id = ? AND book_id = ?',
        whereArgs: [chapterId, bookId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return BookChapterContent.fromMap(rows.first);
    } catch (e) {
      debugPrint('SpecialBooksContentRepository.getChapter error: $e');
      return null;
    }
  }

  Future<List<BookChapterContent>> searchChapters(
    String query, {
    int limit = 50,
  }) async {
    final db = await _db;
    if (db == null) return [];
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    try {
      final like = '%$trimmed%';
      final rows = await db.rawQuery(
        '''
        SELECT * FROM chapters
        WHERE book_id = ?
          AND (title LIKE ? OR content_text LIKE ? OR content_html LIKE ?)
        ORDER BY order_index ASC
        LIMIT ?
        ''',
        [bookId, like, like, like, limit],
      );
      return rows.map(BookChapterContent.fromMap).toList();
    } catch (e) {
      debugPrint('SpecialBooksContentRepository.searchChapters error: $e');
      return [];
    }
  }

  Future<int> get contentVersion async {
    final db = await _db;
    if (db == null) return 0;
    try {
      final rows = await db.rawQuery(
        'SELECT content_version FROM book_meta WHERE book_id = ? LIMIT 1',
        [bookId],
      );
      if (rows.isEmpty) return 0;
      return (rows.first['content_version'] as int?) ?? 0;
    } catch (_) {
      return 0;
    }
  }
}
