import 'database_manager.dart';
import 'models/church_ages_models.dart';
import 'fts_query_builder.dart';

class ChurchAgesRepository {
  ChurchAgesRepository(this._dbManager, this.langCode);

  final DatabaseManager _dbManager;
  final String langCode; // 'en' or 'ta'

  String get dbFileName => 'church_ages_$langCode.db';

  /// Get all chapters
  Future<List<ChurchAgesChapter>> getChapters() async {
    final db = await _dbManager.getDatabase(dbFileName);
    final rows = await db.query('chapters', orderBy: 'order_index ASC');
    return rows.map((r) => ChurchAgesChapter.fromMap(r)).toList();
  }

  /// Get topics as a flat list
  Future<List<ChurchAgesTopic>> getAllTopics() async {
    final db = await _dbManager.getDatabase(dbFileName);
    final rows = await db.query('topics', orderBy: 'order_index ASC');
    return rows.map((r) => ChurchAgesTopic.fromMap(r)).toList();
  }

  /// Get only top-level topics (chapters)
  Future<List<ChurchAgesTopic>> getRootTopics() async {
    final db = await _dbManager.getDatabase(dbFileName);
    final rows = await db.query(
      'chapters',
      orderBy: 'order_index ASC',
    );
    return rows.map((r) => ChurchAgesTopic(
      id: r['id'] as int,
      title: r['title'] as String,
      orderIndex: r['order_index'] as int,
      chapterId: r['id'] as int,
    )).toList();
  }

  /// Get topics hierarchically grouped by chapter or parent.
  /// This is useful for building the left-pane reading navigator.
  Future<List<ChurchAgesTopic>> getHierarchicalTopics() async {
    final chapters = await getChapters();
    final flatTopics = await getAllTopics();
    
    // Create map of all nodes (Chapters + Topics) to build the tree
    final Map<int, ChurchAgesTopic> idMap = {
      for (final c in chapters) c.id: ChurchAgesTopic(
        id: c.id,
        title: c.title,
        orderIndex: c.orderIndex,
        chapterId: c.id,
      )
    };
    
    for (final t in flatTopics) {
      idMap[t.id] = t;
    }
    
    final List<ChurchAgesTopic> roots = [];
    
    // First, identify root nodes (Chapters)
    for (final c in chapters) {
      roots.add(idMap[c.id]!);
    }
    
    // Then, attach topics to their parents (could be a Chapter or another Topic)
    for (final t in flatTopics) {
      if (t.parentId != null && idMap.containsKey(t.parentId)) {
        final parent = idMap[t.parentId!]!;
        final updatedParent = parent.copyWith(
          children: [...parent.children, idMap[t.id]!]
        );
        idMap[t.parentId!] = updatedParent;
      }
    }
    
    // Recursive function to get updated nodes with sorted children
    ChurchAgesTopic getUpdated(ChurchAgesTopic topic) {
      final latest = idMap[topic.id]!;
      final newChildren = latest.children.map((c) => getUpdated(c)).toList();
      newChildren.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      return latest.copyWith(children: newChildren);
    }
    
    final result = roots.map((r) => getUpdated(r)).toList();
    result.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      
    return result;
  }

  /// Get content for a specific topic
  Future<ChurchAgesContent?> getContent(int topicId) async {
    final db = await _dbManager.getDatabase(dbFileName);
    final rows = await db.query(
      'content',
      where: 'topic_id = ?',
      whereArgs: [topicId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ChurchAgesContent.fromMap(rows.first);
  }

  /// Search topics by title or content
  Future<List<ChurchAgesSearchResult>> search({
    required String query,
    required bool searchContent,
  }) async {
    final db = await _dbManager.getDatabase(dbFileName);
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    if (searchContent) {
      // Use FTS5
      final ftsQuery = FtsQueryBuilder.buildMatchQuery(trimmed);
      final sql = '''
        SELECT 
          f.topic_id, 
          t.title,
          c.title as chapter_title,
          snippet(fts_content, 2, '<b>', '</b>', '...', 64) as snippet
        FROM fts_content f
        JOIN topics t ON f.topic_id = t.id
        LEFT JOIN chapters c ON t.chapter_id = c.id
        WHERE fts_content MATCH ?
        ORDER BY rank
        LIMIT 200
      ''';
      
      final rows = await db.rawQuery(sql, [ftsQuery]);
      return rows.map((r) => ChurchAgesSearchResult.fromMap(r)).toList();
    } else {
      // Search titles only in Chapters (the "listed items")
      final likeQuery = '%$trimmed%';
      final sql = '''
        SELECT 
          id as topic_id,
          title,
          NULL as chapter_title,
          '' as snippet
        FROM chapters
        WHERE title LIKE ?
        ORDER BY order_index ASC
        LIMIT 200
      ''';
      
      final rows = await db.rawQuery(sql, [likeQuery]);
      return rows.map((r) => ChurchAgesSearchResult.fromMap(r)).toList();
    }
  }
}
