import 'dart:io';

import 'package:sqflite/sqflite.dart';
import 'package:sqlite3/sqlite3.dart' hide Database;

import 'database_manager.dart';
import 'fts_query_builder.dart';
import 'models/cod_models.dart';
import '../utils/tamil_normalizer.dart';

class CodRepository {
  final DatabaseManager _dbManager;
  final String languageCode;

  CodRepository(this._dbManager, {required this.languageCode});

  String get _dbFileName =>
      languageCode == 'ta' ? 'cod_tamil.db' : 'cod_english.db';

  Future<Database> _openDb() => _dbManager.getDatabase(_dbFileName);

  String get _seriesLabel => languageCode == 'ta' ? 'COD Tamil' : 'COD English';

  Map<String, dynamic> _rowToMap(List<String> columnNames, Row row) {
    final map = <String, dynamic>{};
    for (var i = 0; i < columnNames.length; i++) {
      map[columnNames[i]] = row.columnAt(i);
    }
    return map;
  }

  Future<List<CodQuestion>> _searchQuestionsFts({
    required String search,
    String? category,
    bool onlyWithScriptures = false,
  }) async {
    final matchPattern = FtsQueryBuilder.buildMatchQuery(search);
    final normalizedLike = search.trim().toLowerCase();
    final normalizedPrefix = '$normalizedLike%';
    final dbPath = await _dbManager.getDatabasePath(_dbFileName);
    if (!await File(dbPath).exists()) return <CodQuestion>[];

    final db = sqlite3.open(dbPath, mode: OpenMode.readOnly);
    try {
      final args = <Object?>[
        matchPattern,
        matchPattern,
        _seriesLabel,
        normalizedPrefix,
        '%$normalizedLike%',
        normalizedPrefix,
        '%$normalizedLike%',
      ];
      final where = <String>[];
      if (category != null && category.isNotEmpty) {
        where.add('c.slug = ?');
        args.add(category);
      }

      if (onlyWithScriptures) {
        where.add('q.scriptures = 1');
      }

      final whereClause = where.isNotEmpty
          ? 'WHERE ${where.join(' AND ')}'
          : '';

      final sql =
          '''
        WITH title_match AS (
          SELECT id FROM questions_fts WHERE questions_fts MATCH ?
        ),
        content_match AS (
          SELECT question_id AS id FROM answers_fts WHERE answers_fts MATCH ?
        ),
        matches AS (
          SELECT id, 0 AS rank_priority FROM title_match
          UNION ALL
          SELECT id, 1 AS rank_priority FROM content_match
        ),
        merged_matches AS (
          SELECT
            id,
            MIN(rank_priority) AS rank_priority
          FROM matches
          GROUP BY id
        )
        SELECT
          q.id,
          q.number,
          q.title,
          q.title_short,
          c.slug AS category,
          ? AS series,
          t.topic_slug AS topic_slug,
          t.topic_title AS topic_title,
          NULL AS page_ref
        FROM merged_matches m
        JOIN questions q ON q.id = m.id
        JOIN categories_lookup c ON q.category_id = c.id
        LEFT JOIN topics_lookup t ON q.topic_id = t.id
        $whereClause
        ORDER BY
          CASE
            WHEN lower(COALESCE(q.title_short, '')) LIKE ? THEN 0
            WHEN lower(COALESCE(q.title_short, '')) LIKE ? THEN 1
            WHEN lower(q.title) LIKE ? THEN 2
            WHEN lower(q.title) LIKE ? THEN 3
            ELSE 4
          END,
          m.rank_priority ASC,
          COALESCE(q.number, 99999) ASC,
          q.title ASC
      ''';

      final result = db.select(sql, args);
      final columnNames = result.columnNames;
      final ftsRows = result
          .map((row) => CodQuestion.fromMap(_rowToMap(columnNames, row)))
          .toList();
      if (ftsRows.isNotEmpty) return ftsRows;
      // Fallback for environments where FTS tokenization/indexing does not
      // match some Unicode scripts reliably (e.g., Tamil partial-word search).
      return _searchQuestionsLike(
        search: search,
        category: category,
        onlyWithScriptures: onlyWithScriptures,
      );
    } catch (_) {
      // Best-effort fallback for platforms where FTS5 is unavailable/limited.
      return _searchQuestionsLike(
        search: search,
        category: category,
        onlyWithScriptures: onlyWithScriptures,
      );
    } finally {
      db.close();
    }
  }

  Future<List<CodQuestion>> _searchQuestionsLike({
    required String search,
    String? category,
    bool onlyWithScriptures = false,
  }) async {
    final db = await _openDb();
    final normalized = search.trim();
    if (normalized.isEmpty) return <CodQuestion>[];

    final where = <String>[
      '''
      (
        q.title LIKE ? COLLATE NOCASE
        OR COALESCE(q.title_short, '') LIKE ? COLLATE NOCASE
        OR EXISTS (
          SELECT 1
          FROM answers a
          WHERE a.question_id = q.id
            AND COALESCE(a.plain_text, '') LIKE ? COLLATE NOCASE
        )
      )
      ''',
    ];
    final whereArgs = <Object?>[
      '%$normalized%',
      '%$normalized%',
      '%$normalized%',
    ];

    if (category != null && category.isNotEmpty) {
      where.add('c.slug = ?');
      whereArgs.add(category);
    }

    if (onlyWithScriptures) {
      where.add('q.scriptures = 1');
    }

    final rows = await db.rawQuery(
      '''
      SELECT
        q.id,
        q.number,
        q.title,
        q.title_short,
        c.slug AS category,
        ? AS series,
        t.topic_slug AS topic_slug,
        t.topic_title AS topic_title,
        NULL AS page_ref
      FROM questions q
      JOIN categories_lookup c ON q.category_id = c.id
      LEFT JOIN topics_lookup t ON q.topic_id = t.id
      WHERE ${where.join(' AND ')}
      ORDER BY
        CASE
          WHEN lower(COALESCE(q.title_short, '')) LIKE ? THEN 0
          WHEN lower(COALESCE(q.title_short, '')) LIKE ? THEN 1
          WHEN lower(q.title) LIKE ? THEN 2
          WHEN lower(q.title) LIKE ? THEN 3
          ELSE 4
        END,
        COALESCE(q.number, 99999) ASC,
        q.title ASC
      ''',
      <Object?>[
        _seriesLabel,
        ...whereArgs,
        '${normalized.toLowerCase()}%',
        '%${normalized.toLowerCase()}%',
        '${normalized.toLowerCase()}%',
        '%${normalized.toLowerCase()}%',
      ],
    );

    return rows.map((row) => CodQuestion.fromMap(row)).toList();
  }

  Future<List<CodQuestion>> getQuestions({
    String? category,
    String? search,
    bool? onlyWithScriptures,
  }) async {
    final normalizedSearch = search?.trim();
    if (normalizedSearch != null && normalizedSearch.isNotEmpty) {
      return _searchQuestionsFts(
        search: normalizedSearch,
        category: category,
        onlyWithScriptures: onlyWithScriptures == true,
      );
    }

    final db = await _openDb();
    final where = <String>[];
    final whereArgs = <Object?>[];

    if (category != null && category.isNotEmpty) {
      where.add('c.slug = ?');
      whereArgs.add(category);
    }

    if (onlyWithScriptures == true) {
      where.add('q.scriptures = 1');
    }

    final whereClause = where.isNotEmpty ? 'WHERE ${where.join(' AND ')}' : '';

    final rows = await db.rawQuery(
      '''
      SELECT
        q.id,
        q.number,
        q.title,
        q.title_short,
        c.slug AS category,
        ? AS series,
        t.topic_slug AS topic_slug,
        t.topic_title AS topic_title,
        NULL AS page_ref
      FROM questions q
      JOIN categories_lookup c ON q.category_id = c.id
      LEFT JOIN topics_lookup t ON q.topic_id = t.id
      $whereClause
      ORDER BY
        COALESCE(q.number, 99999) ASC,
        q.title ASC
      ''',
      <Object?>[_seriesLabel, ...whereArgs],
    );

    return rows.map((row) => CodQuestion.fromMap(row)).toList();
  }

  Future<CodQuestion?> getQuestion(String id) async {
    final db = await _openDb();
    final rows = await db.rawQuery(
      '''
      SELECT
        q.id,
        q.number,
        q.title,
        q.title_short,
        c.slug AS category,
        ? AS series,
        t.topic_slug AS topic_slug,
        t.topic_title AS topic_title,
        NULL AS page_ref
      FROM questions q
      JOIN categories_lookup c ON q.category_id = c.id
      LEFT JOIN topics_lookup t ON q.topic_id = t.id
      WHERE q.id = ?
      LIMIT 1
      ''',
      [_seriesLabel, id],
    );
    if (rows.isEmpty) return null;
    return CodQuestion.fromMap(rows.first);
  }

  Future<List<CodAnswerParagraph>> getAnswerParagraphs(
    String questionId,
  ) async {
    final db = await _openDb();
    final rows = await db.query(
      'answers',
      where: 'question_id = ?',
      whereArgs: [questionId],
      orderBy: 'order_index ASC, id ASC',
    );
    return rows.map((row) => CodAnswerParagraph.fromMap(row)).toList();
  }

  Future<List<String>> getCategories() async {
    final db = await _openDb();
    final rows = await db.rawQuery('''
      SELECT DISTINCT c.slug AS category
      FROM questions q
      JOIN categories_lookup c ON q.category_id = c.id
      WHERE c.slug IS NOT NULL AND c.slug != ''
      ORDER BY category ASC
      ''');
    return rows
        .map((row) => row['category'] as String?)
        .where((v) => v != null && v.isNotEmpty)
        .cast<String>()
        .toList();
  }

  Future<List<CodQuestion>> getQuestionsByLetter(
    String letter, {
    String? category,
  }) async {
    final db = await _openDb();

    final normalizedLetter = languageCode == 'ta'
        ? letter.trim()
        : letter.trim().toLowerCase();
    final where = <String>[
      languageCode == 'ta'
          ? "ltrim(q.title_short) LIKE ? || '%'"
          : "lower(ltrim(q.title_short)) LIKE ? || '%'",
    ];
    final args = <Object?>[_seriesLabel, normalizedLetter];

    if (category != null && category.isNotEmpty) {
      where.add('c.slug = ?');
      args.add(category);
    }

    final whereClause = 'WHERE ${where.join(' AND ')}';

    final rows = await db.rawQuery('''
      SELECT
        q.id,
        q.number,
        q.title,
        q.title_short,
        c.slug AS category,
        ? AS series,
        t.topic_slug AS topic_slug,
        t.topic_title AS topic_title,
        NULL AS page_ref
      FROM questions q
      JOIN categories_lookup c ON q.category_id = c.id
      LEFT JOIN topics_lookup t ON q.topic_id = t.id
      $whereClause
      ORDER BY
        COALESCE(q.number, 99999) ASC,
        q.title ASC
      ''', args);

    return rows.map((row) => CodQuestion.fromMap(row)).toList();
  }

  Future<List<CodQuestion>> getQuestionsByTopic(
    String topicSlug, {
    String? category,
    String? search,
    bool? onlyWithScriptures,
  }) async {
    final normalizedSearch = search?.trim();
    if (normalizedSearch != null && normalizedSearch.isNotEmpty) {
      final allMatches = await _searchQuestionsFts(
        search: normalizedSearch,
        category: category,
        onlyWithScriptures: onlyWithScriptures == true,
      );
      return allMatches.where((q) => q.topicSlug == topicSlug).toList();
    }

    final db = await _openDb();

    final where = <String>['t.topic_slug = ?'];
    final args = <Object?>[_seriesLabel, topicSlug];

    if (category != null && category.isNotEmpty) {
      where.add('c.slug = ?');
      args.add(category);
    }

    if (onlyWithScriptures == true) {
      where.add('q.scriptures = 1');
    }

    final whereClause = 'WHERE ${where.join(' AND ')}';

    final rows = await db.rawQuery('''
      SELECT
        q.id,
        q.number,
        q.title,
        q.title_short,
        c.slug AS category,
        ? AS series,
        t.topic_slug AS topic_slug,
        t.topic_title AS topic_title,
        NULL AS page_ref
      FROM questions q
      JOIN categories_lookup c ON q.category_id = c.id
      LEFT JOIN topics_lookup t ON q.topic_id = t.id
      $whereClause
      ORDER BY
        COALESCE(q.number, 99999) ASC,
        q.title ASC
      ''', args);

    if (rows.isNotEmpty) {
      return rows.map((row) => CodQuestion.fromMap(row)).toList();
    }

    return <CodQuestion>[];
  }

  Future<List<CodTopic>> getTopicList() async {
    final db = await _openDb();
    final rows = await db.rawQuery('''
      SELECT DISTINCT
        t.topic_slug AS topic_slug,
        t.topic_title AS topic_title
      FROM questions q
      JOIN topics_lookup t ON q.topic_id = t.id
      WHERE t.topic_slug IS NOT NULL AND t.topic_slug != ''
      ORDER BY t.topic_title ASC
      ''');
    final topics = rows.map((row) => CodTopic.fromMap(row)).toList();
    return topics;
  }

  Future<List<String>> getAvailableLetters() async {
    final db = await _openDb();
    final rows = await db.rawQuery('''
      SELECT DISTINCT
        ${languageCode == 'ta' ? "substr(ltrim(q.title_short), 1, 2)" : "lower(substr(ltrim(q.title_short), 1, 1))"} AS letter
      FROM questions q
      WHERE q.title_short IS NOT NULL AND ltrim(q.title_short) != ''
      ORDER BY letter ASC
      ''');
    return rows
        .map((row) => row['letter'] as String?)
        .where((v) => v != null && v.isNotEmpty)
        .cast<String>()
        .toList();
  }

  // ── Common Search: answer-body hits (reliable for Tamil; one row per paragraph)

  static String _escapeSqlLike(String input) {
    return input
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
  }

  static String _sqlLikeContains(String token) =>
      '%${_escapeSqlLike(token)}%';

  /// Searches [answers.plain_text] and returns up to [limit] matching paragraphs.
  Future<List<CodAnswerSearchHit>> searchAnswerParagraphHits({
    required String query,
    int limit = 50,
    CodSearchMatchMode matchMode = CodSearchMatchMode.allWords,
  }) async {
    final raw = query.trim();
    if (raw.isEmpty) return [];

    final List<String> tokens;
    switch (matchMode) {
      case CodSearchMatchMode.phrase:
        tokens = [raw];
        break;
      case CodSearchMatchMode.allWords:
      case CodSearchMatchMode.anyWord:
        tokens = raw.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
        if (tokens.isEmpty) return [];
        break;
    }

    final joiner = matchMode == CodSearchMatchMode.anyWord && tokens.length > 1
        ? ' OR '
        : ' AND ';
    final likeClause = tokens
        .map(
          (_) => "COALESCE(a.plain_text, '') LIKE ? ESCAPE '\\'",
        )
        .join(joiner);

    final args = <Object?>[
      for (final t in tokens) _sqlLikeContains(t),
      limit,
    ];

    final db = await _openDb();
    final rows = await db.rawQuery(
      '''
      SELECT
        a.id AS answer_id,
        a.question_id,
        a.order_index,
        a.para_label,
        a.plain_text,
        q.title AS qtitle,
        q.number AS qnumber
      FROM answers a
      JOIN questions q ON q.id = a.question_id
      WHERE $likeClause
      ORDER BY COALESCE(q.number, 999999) ASC, a.order_index ASC, a.id ASC
      LIMIT ?
      ''',
      args,
    );

    return rows.map((row) {
      final plain = row['plain_text'] as String? ?? '';
      return CodAnswerSearchHit(
        questionId: row['question_id'] as String,
        answerParagraphId: row['answer_id'] as int,
        orderIndex: row['order_index'] as int,
        paraLabel: row['para_label'] as String?,
        questionTitle: row['qtitle'] as String? ?? '',
        questionNumber: row['qnumber'] as int?,
        snippetHtml: _buildCodAnswerSnippetHtml(plain, raw, matchMode),
      );
    }).toList();
  }

  static String _ellipsizeForHtml(String s, int max) {
    if (s.length <= max) return s;
    return '${s.substring(0, max)}…';
  }

  static int _indexOfQuery(String haystack, String needle) {
    if (needle.isEmpty) return -1;
    var i = haystack.indexOf(needle);
    if (i >= 0) return i;
    i = haystack.toLowerCase().indexOf(needle.toLowerCase());
    if (i >= 0) return i;
    final nh = normalizeTamil(haystack);
    final nn = normalizeTamil(needle);
    final j = nh.indexOf(nn);
    if (j < 0) return -1;
    if (nh.length == haystack.length) return j;
    return haystack.indexOf(needle);
  }

  static (int start, int len)? _matchHighlightRange(
    String text,
    String query,
    CodSearchMatchMode mode,
  ) {
    if (query.isEmpty) return null;
    switch (mode) {
      case CodSearchMatchMode.phrase:
        final i = _indexOfQuery(text, query);
        if (i < 0) return null;
        return (i, query.length);
      case CodSearchMatchMode.allWords:
      case CodSearchMatchMode.anyWord:
        final words =
            query.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
        if (words.isEmpty) return null;
        int? bestStart;
        var bestLen = 0;
        for (final w in words) {
          final i = _indexOfQuery(text, w);
          if (i >= 0 && (bestStart == null || i < bestStart)) {
            bestStart = i;
            bestLen = w.length;
          }
        }
        if (bestStart == null) return null;
        return (bestStart, bestLen);
    }
  }

  static String _buildCodAnswerSnippetHtml(
    String plainText,
    String originalQuery,
    CodSearchMatchMode mode,
  ) {
    final text = plainText.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return '';

    final range = _matchHighlightRange(text, originalQuery.trim(), mode);
    if (range == null) {
      return _ellipsizeForHtml(text, 240);
    }
    final start = range.$1;
    final len = range.$2;
    const r = 88;
    final a = (start - r).clamp(0, text.length);
    final b = (start + len + r).clamp(0, text.length);
    final chunk = text.substring(a, b);
    final rel = start - a;
    if (rel + len > chunk.length) {
      return _ellipsizeForHtml(text, 240);
    }
    final before = chunk.substring(0, rel);
    final mid = chunk.substring(rel, rel + len);
    final after = chunk.substring(rel + len);
    return '${a > 0 ? '…' : ''}$before<b>$mid</b>$after${b < text.length ? '…' : ''}';
  }
}
