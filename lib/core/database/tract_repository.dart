import 'database_manager.dart';
import 'models/tract_models.dart';

class TractRepository {
  TractRepository(this._dbManager, this.langCode);

  final DatabaseManager _dbManager;
  final String langCode;

  String get dbFileName => 'tracts_$langCode.db';

  Future<List<TractEntity>> listTracts({String? query}) async {
    final db = await _dbManager.getDatabase(dbFileName);
    final args = <Object?>[langCode];
    var sql = '''
      SELECT id, lang, title, content
      FROM tracts
      WHERE lang = ?
    ''';
    final trimmed = query?.trim() ?? '';
    if (trimmed.isNotEmpty) {
      sql += ' AND (title LIKE ? OR content LIKE ? OR id LIKE ?)';
      final q = '%$trimmed%';
      args.addAll([q, q, q]);
    }
    sql += ' ORDER BY id ASC';
    final rows = await db.rawQuery(sql, args);
    return rows.map((row) => TractEntity.fromMap(row)).toList();
  }
}
