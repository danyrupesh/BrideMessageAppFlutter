import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'database_manager.dart';
import 'models/special_book_models.dart';

/// Reads from special_books_catalog_{lang}.db (catalog layer).
/// Only contains book metadata + chapter titles — no HTML content.
class SpecialBooksCatalogRepository {
  SpecialBooksCatalogRepository({required this.lang});

  final String lang;

  String get _dbFileName => 'special_books_catalog_$lang.db';

  final DatabaseManager _dbManager = DatabaseManager();

  Future<Database?> get _db async {
    try {
      return await _dbManager.getDatabase(_dbFileName);
    } catch (_) {
      return null;
    }
  }

  Future<bool> get isAvailable async {
    final db = await _db;
    if (db == null) return false;
    try {
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='books'",
      );
      return tables.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<List<SpecialBook>> listBooks({String? searchQuery}) async {
    final db = await _db;
    if (db == null) return [];
    try {
      if (searchQuery == null || searchQuery.trim().isEmpty) {
        final rows = await db.rawQuery(
          'SELECT * FROM books WHERE lang = ? ORDER BY sort_order ASC, title ASC',
          [lang],
        );
        return rows.map(SpecialBook.fromMap).toList();
      }

      final query = searchQuery.trim();
      try {
        final ftsQuery = query
            .split(RegExp(r'\s+'))
            .map((w) => '"$w"*')
            .join(' AND ');
        final ftsRows = await db.rawQuery(
          'SELECT rowid FROM books_fts WHERE books_fts MATCH ? LIMIT 200',
          [ftsQuery],
        );
        if (ftsRows.isEmpty) return [];
        final rowIds = ftsRows.map((r) => r['rowid']).toList();
        final placeholders = rowIds.map((_) => '?').join(',');
        final rows = await db.rawQuery(
          'SELECT * FROM books WHERE lang = ? AND rowid IN ($placeholders) ORDER BY sort_order ASC',
          [lang, ...rowIds],
        );
        return rows.map(SpecialBook.fromMap).toList();
      } catch (_) {
        final like = '%$query%';
        final rows = await db.rawQuery(
          'SELECT * FROM books WHERE lang = ? AND (title LIKE ? OR description LIKE ?) ORDER BY sort_order ASC',
          [lang, like, like],
        );
        return rows.map(SpecialBook.fromMap).toList();
      }
    } catch (e) {
      debugPrint('SpecialBooksCatalogRepository.listBooks error: $e');
      return [];
    }
  }

  Future<SpecialBook?> getBook(String id) async {
    final db = await _db;
    if (db == null) return null;
    try {
      final rows = await db.query(
        'books',
        where: 'id = ? AND lang = ?',
        whereArgs: [id, lang],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return SpecialBook.fromMap(rows.first);
    } catch (e) {
      debugPrint('SpecialBooksCatalogRepository.getBook error: $e');
      return null;
    }
  }

  Future<List<BookChapterTitle>> listChapterTitles(String bookId) async {
    final db = await _db;
    if (db == null) return [];
    try {
      final rows = await db.rawQuery(
        'SELECT * FROM book_chapters WHERE book_id = ? ORDER BY order_index ASC',
        [bookId],
      );
      return rows.map(BookChapterTitle.fromMap).toList();
    } catch (e) {
      debugPrint('SpecialBooksCatalogRepository.listChapterTitles error: $e');
      return [];
    }
  }

  Future<bool> hasChapterContent(String bookId) async {
    final db = await _db;
    if (db == null) return false;
    try {
      final rows = await db.rawQuery(
        "SELECT COUNT(*) AS c FROM chapters WHERE book_id = ? LIMIT 1",
        [bookId],
      );
      final count = (rows.first['c'] as int?) ?? 0;
      return count > 0;
    } catch (_) {
      return false;
    }
  }

  Future<BookChapterContent?> getChapterContent(String chapterId) async {
    final db = await _db;
    if (db == null) return null;
    try {
      final rows = await db.query(
        'chapters',
        where: 'id = ?',
        whereArgs: [chapterId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return BookChapterContent.fromMap(rows.first);
    } catch (_) {
      return null;
    }
  }

  /// Returns bookId → context-snippet for every book whose chapter content
  /// or chapter title contains [query].  Only the first matching chapter per
  /// book is used to build the snippet.
  Future<Map<String, String>> searchBooksWithSnippets(
    String query, {
    int limit = 100,
  }) async {
    final db = await _db;
    if (db == null) return {};
    final q = query.trim();
    if (q.isEmpty) return {};
    try {
      final like = '%$q%';
      final rows = await db.rawQuery(
        '''
        SELECT book_id, content_text FROM chapters
        WHERE content_text LIKE ? OR title LIKE ?
        ORDER BY book_id ASC
        LIMIT ?
        ''',
        [like, like, limit],
      );
      final result = <String, String>{};
      for (final row in rows) {
        final bookId = row['book_id'] as String;
        if (result.containsKey(bookId)) continue;
        final raw = ((row['content_text'] as String?) ?? '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        final lq = q.toLowerCase();
        final idx = raw.toLowerCase().indexOf(lq);
        String snippet;
        if (idx == -1) {
          snippet = raw.length > 120 ? '${raw.substring(0, 120)}…' : raw;
        } else {
          final s = (idx - 40).clamp(0, raw.length);
          final e = (idx + q.length + 80).clamp(0, raw.length);
          snippet =
              '${s > 0 ? '…' : ''}${raw.substring(s, e)}${e < raw.length ? '…' : ''}';
        }
        result[bookId] = snippet;
      }
      return result;
    } catch (e) {
      debugPrint('searchBooksWithSnippets error: $e');
      return {};
    }
  }

  Future<List<BookChapterContent>> searchChapters(
    String bookId,
    String query, {
    int limit = 50,
  }) async {
    final db = await _db;
    if (db == null) return [];
    final q = query.trim();
    if (q.isEmpty) return [];
    try {
      final like = '%$q%';
      final rows = await db.rawQuery(
        '''
        SELECT * FROM chapters
        WHERE book_id = ?
          AND (title LIKE ? OR content_text LIKE ?)
        ORDER BY order_index ASC
        LIMIT ?
        ''',
        [bookId, like, like, limit],
      );
      return rows.map(BookChapterContent.fromMap).toList();
    } catch (_) {
      return [];
    }
  }
}
