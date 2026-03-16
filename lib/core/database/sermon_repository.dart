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
    String? titlePrefix,
    String? titleContains,
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

    if (titlePrefix != null && titlePrefix.isNotEmpty) {
      sql += ' AND title LIKE ?';
      args.add('$titlePrefix%');
    }

    if (titleContains != null && titleContains.isNotEmpty) {
      sql += ' AND title LIKE ?';
      args.add('%$titleContains%');
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

  Future<int> getSermonCount() async {
    final db = await _dbManager.getDatabase(dbFileName);
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM sermons WHERE language = ?',
      [languageCode],
    );
    if (rows.isEmpty) return 0;
    final value = rows.first['c'];
    return (value is int) ? value : (value as num?)?.toInt() ?? 0;
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
    String currentId,
    int direction,
  ) async {
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
    final results = await db.rawQuery('SELECT * FROM sermons WHERE id = ?', [
      ids[nextIdx],
    ]);
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
    bool accurateMatch = false,
    String sortOrder = 'relevance',
    String? titlePrefix,
  }) async {
    final matchPattern = FtsQueryBuilder.buildMatchQuery(
      query,
      exactMatch: exactMatch,
      anyWord: anyWord,
      prefixOnly: prefixOnly,
    );
    final path = await _dbManager.getDatabasePath(dbFileName);
    final ftsResults = await searchSermonFts(
      dbPath: path,
      languageCode: languageCode,
      matchPattern: matchPattern,
      limit: limit,
      offset: offset,
      sortOrder: sortOrder,
      titlePrefix: titlePrefix,
    );
    if (ftsResults.isNotEmpty) return ftsResults;

    return _searchSermonsFallback(
      query: query,
      limit: limit,
      offset: offset,
      exactMatch: exactMatch,
      anyWord: anyWord,
      prefixOnly: prefixOnly,
      sortOrder: sortOrder,
      titlePrefix: titlePrefix,
    );
  }

  Future<List<SermonSearchResult>> _searchSermonsFallback({
    required String query,
    required int limit,
    required int offset,
    required bool exactMatch,
    required bool anyWord,
    required bool prefixOnly,
    String sortOrder = 'relevance',
    String? titlePrefix,
  }) async {
    final normalizedQuery = query.replaceAll(RegExp(r'[^\w\s]'), ' ').trim();
    if (normalizedQuery.isEmpty) return const [];

    final db = await _dbManager.getDatabase(dbFileName);
    final where = StringBuffer('s.language = ?');
    final args = <dynamic>[languageCode];

    final tokens = normalizedQuery
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();

    if (titlePrefix != null && titlePrefix.isNotEmpty) {
      where.write(' AND s.title LIKE ?');
      args.add('$titlePrefix%');
    }

    if (exactMatch || prefixOnly || tokens.length <= 1) {
      where.write(' AND LOWER(p.text) LIKE ?');
      final exactToken = exactMatch || tokens.isEmpty
          ? normalizedQuery
          : tokens.first;
      args.add('%${exactToken.toLowerCase()}%');
    } else {
      final separator = anyWord ? ' OR ' : ' AND ';
      final conditions = List.generate(
        tokens.length,
        (_) => 'LOWER(p.text) LIKE ?',
      );
      where.write(' AND (${conditions.join(separator)})');
      for (final token in tokens) {
        args.add('%${token.toLowerCase()}%');
      }
    }

    // Detect whether sermon_paragraphs has a paragraph_number column so we can
    // support databases that omit it without failing the entire search.
    final pragmaRows =
        await db.rawQuery('PRAGMA table_info(sermon_paragraphs)');
    final hasParagraphNumber = pragmaRows.any(
      (row) => (row['name'] as String?) == 'paragraph_number',
    );

    final paragraphSelect =
        hasParagraphNumber ? 'p.paragraph_number,' : 'NULL AS paragraph_number,';
    final paragraphOrder =
        hasParagraphNumber ? 'COALESCE(p.paragraph_number, 0) ASC,' : '';

    final sql = '''
      SELECT
        s.id AS sermon_id,
        s.title,
        s.language,
        s.date,
        s.year,
        s.location,
        $paragraphSelect
        p.paragraph_label,
        p.text
      FROM sermon_paragraphs p
      JOIN sermons s ON p.sermon_id = s.id
      WHERE __WHERE__
      ORDER BY
        CASE WHEN s.date IS NOT NULL AND s.date != '' THEN 0
             WHEN s.year IS NOT NULL THEN 1 ELSE 2 END,
        COALESCE(s.date, s.year || '-12-31') ASC,
        s.title ASC,
        $paragraphOrder
        p.id ASC
      LIMIT ? OFFSET ?
    ''';

    args
      ..add(limit)
      ..add(offset);

    final rows = await db.rawQuery(
      sql.replaceFirst('__WHERE__', where.toString()),
      args,
    );
    return rows.map((row) {
      final text = (row['text'] as String? ?? '').trim();
      return SermonSearchResult(
        sermonId: (row['sermon_id']?.toString()) ?? '',
        title: (row['title'] as String?) ?? '',
        language: (row['language'] as String?) ?? '',
        date: row['date'] as String?,
        year: row['year'] as int?,
        location: row['location'] as String?,
        paragraphNumber: row['paragraph_number'] as int?,
        paragraphLabel: row['paragraph_label'] as String?,
        snippet: _buildFallbackSnippet(
          text,
          query: normalizedQuery,
          exactMatch: exactMatch,
          anyWord: anyWord,
        ),
        rank: null,
      );
    }).toList();
  }

  String _buildFallbackSnippet(
    String text, {
    required String query,
    required bool exactMatch,
    required bool anyWord,
  }) {
    final normalizedText = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalizedText.isEmpty) return '';

    final lowerText = normalizedText.toLowerCase();
    final tokens = query
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .map((token) => token.toLowerCase())
        .toList();

    int matchStart = -1;
    int matchLength = 0;

    if (exactMatch && query.isNotEmpty) {
      final phrase = query.toLowerCase();
      matchStart = lowerText.indexOf(phrase);
      if (matchStart >= 0) matchLength = phrase.length;
    } else if (tokens.isNotEmpty) {
      final searchTokens = anyWord ? tokens : tokens;
      for (final token in searchTokens) {
        final idx = lowerText.indexOf(token);
        if (idx >= 0 && (matchStart == -1 || idx < matchStart)) {
          matchStart = idx;
          matchLength = token.length;
        }
      }
    }

    if (matchStart < 0 || matchLength <= 0) {
      return normalizedText.length <= 140
          ? normalizedText
          : '${normalizedText.substring(0, 137)}...';
    }

    final snippetStart = (matchStart - 60).clamp(0, normalizedText.length);
    final snippetEnd = (matchStart + matchLength + 60).clamp(
      0,
      normalizedText.length,
    );
    final prefix = snippetStart > 0 ? '...' : '';
    final suffix = snippetEnd < normalizedText.length ? '...' : '';
    final before = normalizedText.substring(snippetStart, matchStart);
    final match = normalizedText.substring(
      matchStart,
      matchStart + matchLength,
    );
    final after = normalizedText.substring(
      matchStart + matchLength,
      snippetEnd,
    );
    return '$prefix$before<b>$match</b>$after$suffix';
  }
}
