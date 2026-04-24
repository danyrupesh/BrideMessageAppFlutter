import 'dart:typed_data';

import 'database_manager.dart';
import 'models/story_models.dart';

class StoryRepository {
  StoryRepository(this._dbManager, this.langCode);

  final DatabaseManager _dbManager;
  final String langCode;

  String get dbFileName => 'stories_$langCode.db';

  Future<List<StoryEntity>> listStories({
    required StorySectionType section,
    String? query,
    bool searchContent = false,
  }) async {
    final db = await _dbManager.getDatabase(dbFileName);
    final trimmed = query?.trim() ?? '';
    final tableName = section.tableName;

    if (trimmed.isEmpty) {
      final rows = await db.rawQuery('''
        SELECT id, lang, title, content
        FROM $tableName
        WHERE lang = ?
        ORDER BY id ASC
      ''', [langCode]);
      return rows.map((row) => StoryEntity.fromMap(row, section)).toList();
    }

    try {
      // Create wildcard search for each term
      final terms = trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
      final String ftsQuery;
      if (searchContent) {
        ftsQuery = terms.map((w) => '"$w"*').join(' AND ');
      } else {
        ftsQuery = terms.map((w) => 'title:"$w"*').join(' AND ');
      }

      final ftsRows = await db.rawQuery('''
        SELECT rowid FROM ${tableName}_fts
        WHERE ${tableName}_fts MATCH ?
        LIMIT 300
      ''', [ftsQuery]);
      
      if (ftsRows.isEmpty) return [];
      
      final rowIds = ftsRows.map((row) => row['rowid']).toList();
      final placeholders = rowIds.map((_) => '?').join(',');
      final rows = await db.rawQuery('''
        SELECT id, lang, title, content
        FROM $tableName
        WHERE lang = ? AND rowid IN ($placeholders)
        ORDER BY id ASC
      ''', [langCode, ...rowIds]);
      return rows.map((row) => StoryEntity.fromMap(row, section)).toList();
    } catch (_) {
      // Fallback for older DB versions without FTS tables
      final like = '%$trimmed%';
      final String condition = searchContent
          ? '(id LIKE ? OR title LIKE ? OR content LIKE ?)'
          : '(id LIKE ? OR title LIKE ?)';
      final List<String> args = searchContent
          ? [langCode, like, like, like]
          : [langCode, like, like];

      final rows = await db.rawQuery('''
        SELECT id, lang, title, content
        FROM $tableName
        WHERE lang = ? AND $condition
        ORDER BY id ASC
      ''', args);
      return rows.map((row) => StoryEntity.fromMap(row, section)).toList();
    }
  }

  Future<StoryEntity?> getById({
    required StorySectionType section,
    required String id,
  }) async {
    final db = await _dbManager.getDatabase(dbFileName);
    final rows = await db.query(
      section.tableName,
      where: 'id = ? AND lang = ?',
      whereArgs: [id, langCode],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return StoryEntity.fromMap(rows.first, section);
  }

  /// Fetch a WebP image BLOB from the `images` table by [key].
  /// Returns `null` if the key is not found (e.g. DB was not yet optimised).
  Future<Uint8List?> imageForKey(String key) async {
    try {
      final db = await _dbManager.getDatabase(dbFileName);
      final rows = await db.rawQuery(
        'SELECT data FROM images WHERE key = ? LIMIT 1',
        [key],
      );
      if (rows.isEmpty) return null;
      final raw = rows.first['data'];
      if (raw == null) return null;
      if (raw is Uint8List) return raw;
      if (raw is List<int>) return Uint8List.fromList(raw);
      return null;
    } catch (_) {
      // images table may not exist in older DB versions — safe no-op
      return null;
    }
  }
}
