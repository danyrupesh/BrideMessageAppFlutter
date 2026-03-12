import 'package:sqflite/sqflite.dart';
import 'database_manager.dart';
import 'fts_query_builder.dart';
import 'fts_search_sqlite3.dart';
import 'models/bible_search_result.dart';

class BibleRepository {
  final DatabaseManager _dbManager;
  final String languageCode; // e.g. "en" or "ta"
  final String version; // e.g. "kjv" or "bsi"

  BibleRepository(this._dbManager, this.languageCode, this.version);

  /// Helper to get the generated DB filename
  String get dbFileName => 'bible_$version.db';

  Future<List<BibleSearchResult>> getVersesByChapter(
    String book,
    int chapter,
  ) async {
    final db = await _dbManager.getDatabase(dbFileName);
    final sql = '''
      SELECT 
          id,
          language,
          book,
          book_index,
          chapter,
          verse,
          text
      FROM bible_verses
      WHERE book = ? AND chapter = ? AND language = ?
      ORDER BY verse ASC
    ''';

    final List<Map<String, dynamic>> results = await db.rawQuery(sql, [
      book,
      chapter,
      languageCode,
    ]);
    return results.map((e) => BibleSearchResult.fromMap(e)).toList();
  }

  Future<List<BibleSearchResult>> searchVerses({
    required String query,
    required int limit,
    required int offset,
    List<String>? bookFilters,
    bool exactMatch = false,
    bool anyWord = false,
    bool prefixOnly = false,
    bool accurateMatch = false,
    String scope = 'both',
    String sortOrder = 'bookOrder',
  }) async {
    final matchPattern = FtsQueryBuilder.buildMatchQuery(
      query,
      exactMatch: exactMatch,
      anyWord: anyWord,
      prefixOnly: prefixOnly,
    );
    final path = await _dbManager.getDatabasePath(dbFileName);
    return searchBibleFts(
      dbPath: path,
      languageCode: languageCode,
      matchPattern: matchPattern,
      limit: limit,
      offset: offset,
      bookFilters: bookFilters,
      scope: scope,
      sortOrder: sortOrder,
    );
  }

  /// Returns all distinct books with their chapter count and book_index,
  /// ordered canonically. Used by QuickNavigationSheet.
  Future<List<Map<String, dynamic>>> getDistinctBooks() async {
    final db = await _dbManager.getDatabase(dbFileName);
    final rows = await db.rawQuery(
      'SELECT book, book_index, COUNT(DISTINCT chapter) AS chapters '
      'FROM bible_verses WHERE language = ? GROUP BY book ORDER BY book_index',
      [languageCode],
    );
    // sqflite returns unmodifiable maps; convert to mutable copies.
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Returns how many verses exist in [book] [chapter].
  Future<int> getVerseCount(String book, int chapter) async {
    final db = await _dbManager.getDatabase(dbFileName);
    final result = await db.rawQuery(
      'SELECT COUNT(*) FROM bible_verses '
      'WHERE book = ? AND chapter = ? AND language = ?',
      [book, chapter, languageCode],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> countSearchResults(
    String query, {
    List<String>? bookFilters,
    String scope = 'both',
  }) async {
    final matchPattern = FtsQueryBuilder.buildMatchQuery(query);
    final path = await _dbManager.getDatabasePath(dbFileName);
    return countBibleFts(
      dbPath: path,
      matchPattern: matchPattern,
      bookFilters: bookFilters,
      scope: scope,
    );
  }
}
