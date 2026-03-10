import 'database_manager.dart';
import 'fts_query_builder.dart';
import 'fts_search_sqlite3.dart';
import 'models/sermon_models.dart';
import 'models/sermon_search_result.dart';

class SermonRepository {
  final DatabaseManager _dbManager;
  final String languageCode;
  final String version;

  SermonRepository(this._dbManager, this.languageCode, this.version);

  String get dbFileName => 'sermons_$version.db';

  Future<List<SermonEntity>> getSermonsPage({
    int limit = 50,
    int offset = 0,
    int? year,
    String? searchQuery,
    String sortBy = 'year_asc',
    int? yearFrom,
    int? yearTo,
  }) async {
    final db = await _dbManager.getDatabase(dbFileName);

    String sql = 'SELECT * FROM sermons WHERE language = ?';
    final args = <dynamic>[languageCode];

    if (year != null) {
      sql += ' AND year = ?';
      args.add(year);
    } else if (yearFrom != null || yearTo != null) {
      if (yearFrom != null) {
        sql += ' AND year >= ?';
        args.add(yearFrom);
      }
      if (yearTo != null) {
        sql += ' AND year <= ?';
        args.add(yearTo);
      }
    }

    if (searchQuery != null && searchQuery.isNotEmpty) {
      sql +=
          ' AND (title LIKE ? OR location LIKE ? OR id LIKE ? OR CAST(year AS TEXT) LIKE ?)';
      args.add('%$searchQuery%');
      args.add('%$searchQuery%');
      args.add('%$searchQuery%');
      args.add('%$searchQuery%');
    }

    String orderClause;
    if (sortBy == 'year_desc') {
      orderClause =
          'ORDER BY COALESCE(date, year || \'-12-31\') DESC, title ASC';
    } else if (sortBy == 'name_asc') {
      orderClause = 'ORDER BY title ASC';
    } else if (sortBy == 'name_desc') {
      orderClause = 'ORDER BY title DESC';
    } else {
      orderClause = '''
ORDER BY
  CASE WHEN date IS NOT NULL AND date != '' THEN 0
       WHEN year IS NOT NULL THEN 1 ELSE 2 END,
  COALESCE(date, year || '-12-31') ASC,
  title ASC''';
    }

    sql += ' $orderClause LIMIT ? OFFSET ?';

    args.add(limit);
    args.add(offset);

    final results = await db.rawQuery(sql, args);
    return results.map((e) => SermonEntity.fromMap(e)).toList();
  }

  Future<List<int>> getAvailableYears() async {
    final db = await _dbManager.getDatabase(dbFileName);
    final results = await db.rawQuery(
      'SELECT DISTINCT year FROM sermons WHERE year IS NOT NULL AND language = ? ORDER BY year ASC',
      [languageCode],
    );
    return results.map((e) => e['year'] as int).toList();
  }

  Future<List<SermonParagraphEntity>> getParagraphsForSermon(
    String sermonId,
  ) async {
    final db = await _dbManager.getDatabase(dbFileName);
    final results = await db.rawQuery(
      'SELECT * FROM sermon_paragraphs WHERE sermon_id = ? ORDER BY id ASC',
      [sermonId],
    );
    return results.map((e) => SermonParagraphEntity.fromMap(e)).toList();
  }

  Future<SermonEntity?> getSermonById(String id) async {
    final db = await _dbManager.getDatabase(dbFileName);
    final results = await db.rawQuery(
      'SELECT * FROM sermons WHERE id = ? LIMIT 1',
      [id],
    );
    return results.isEmpty ? null : SermonEntity.fromMap(results.first);
  }

  /// Returns the sermon immediately before (direction = -1) or after (direction = +1)
  /// the given [currentId] in the same chronological order used by [getSermonsPage].
  Future<SermonEntity?> getAdjacentSermon(
      String currentId, int direction) async {
    final db = await _dbManager.getDatabase(dbFileName);
    final rows = await db.rawQuery(
      '''SELECT id FROM sermons WHERE language = ?
         ORDER BY
           CASE WHEN date IS NOT NULL AND date != '' THEN 0
                WHEN year IS NOT NULL THEN 1 ELSE 2 END,
           COALESCE(date, year || '-12-31') ASC,
           title ASC''',
      [languageCode],
    );
    final ids = rows.map((r) => r['id'] as String).toList();
    final idx = ids.indexOf(currentId);
    if (idx == -1) return null;
    final nextIdx = idx + direction;
    if (nextIdx < 0 || nextIdx >= ids.length) return null;
    final results = await db.rawQuery(
        'SELECT * FROM sermons WHERE id = ?', [ids[nextIdx]]);
    return results.isEmpty ? null : SermonEntity.fromMap(results.first);
  }

  /// Full-text search across sermon paragraphs using FTS5 (via sqlite3 for FTS5 support).
  Future<List<SermonSearchResult>> searchSermons({
    required String query,
    required int limit,
    required int offset,
    bool exactMatch = false,
    bool anyWord = false,
    bool prefixOnly = false,
  }) async {
    final matchPattern = FtsQueryBuilder.buildMatchQuery(
      query,
      exactMatch: exactMatch,
      anyWord: anyWord,
      prefixOnly: prefixOnly,
    );
    final path = await _dbManager.getDatabasePath(dbFileName);
    return searchSermonFts(
      dbPath: path,
      languageCode: languageCode,
      matchPattern: matchPattern,
      limit: limit,
      offset: offset,
    );
  }
}
