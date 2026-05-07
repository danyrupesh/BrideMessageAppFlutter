import 'database_manager.dart';
import 'models/quote_models.dart';

class PrayerQuoteRepository {
  PrayerQuoteRepository(this._dbManager);

  final DatabaseManager _dbManager;

  static const String _dbFileName = 'prayer_quotes_en.db';

  Future<List<PrayerQuoteEntity>> listQuotes({
    String? sourceType,
    String? sourceGroup,
    String? query,
    int limit = 200,
    int offset = 0,
  }) async {
    final db = await _dbManager.getDatabase(_dbFileName);
    final args = <Object?>[];

    final whereClauses = <String>['lang = ?'];
    args.add('en');

    if (sourceType != null && sourceType.isNotEmpty) {
      whereClauses.add('source_type = ?');
      args.add(sourceType);
    }
    if (sourceGroup != null && sourceGroup.isNotEmpty) {
      whereClauses.add('source_group = ?');
      args.add(sourceGroup);
    }

    final trimmed = query?.trim() ?? '';
    if (trimmed.isNotEmpty) {
      try {
        final ftsQuery = trimmed
            .split(RegExp(r'\s+'))
            .map((w) => '"$w"*')
            .join(' AND ');
        final ftsRows = await db.rawQuery(
          'SELECT rowid FROM prayer_quotes_fts WHERE prayer_quotes_fts MATCH ? LIMIT ? OFFSET ?',
          [ftsQuery, limit, offset],
        );
        if (ftsRows.isEmpty) return [];
        final rowIds = ftsRows.map((r) => r['rowid']).toList();
        final placeholders = rowIds.map((_) => '?').join(',');
        whereClauses.add('rowid IN ($placeholders)');
        args.addAll(rowIds);
        final rows = await db.rawQuery(
          'SELECT * FROM prayer_quotes WHERE ${whereClauses.join(' AND ')} ORDER BY updated_at DESC',
          args,
        );
        return rows.map((r) => PrayerQuoteEntity.fromMap(r)).toList();
      } catch (_) {
        final like = '%$trimmed%';
        whereClauses.add('(quote_plain LIKE ? OR reference_plain LIKE ? OR author_name_raw LIKE ? OR source_group LIKE ?)');
        args.addAll([like, like, like, like]);
      }
    }

    final sql = '''
      SELECT * FROM prayer_quotes
      WHERE ${whereClauses.join(' AND ')}
      ORDER BY updated_at DESC
      LIMIT ? OFFSET ?
    ''';
    args.addAll([limit, offset]);
    final rows = await db.rawQuery(sql, args);
    return rows.map((r) => PrayerQuoteEntity.fromMap(r)).toList();
  }

  Future<List<String>> getSourceTypes() async {
    final db = await _dbManager.getDatabase(_dbFileName);
    final rows = await db.rawQuery(
      "SELECT DISTINCT source_type FROM prayer_quotes WHERE source_type IS NOT NULL AND source_type != '' ORDER BY source_type ASC",
    );
    return rows.map((r) => r['source_type'] as String).toList();
  }

  Future<List<String>> getSourceGroups(String sourceType) async {
    final db = await _dbManager.getDatabase(_dbFileName);
    final rows = await db.rawQuery(
      "SELECT DISTINCT source_group FROM prayer_quotes WHERE source_type = ? AND source_group IS NOT NULL AND source_group != '' ORDER BY source_group ASC",
      [sourceType],
    );
    return rows.map((r) => r['source_group'] as String).toList();
  }
}
