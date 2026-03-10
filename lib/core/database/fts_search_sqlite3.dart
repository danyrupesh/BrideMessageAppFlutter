import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'models/bible_search_result.dart';
import 'models/sermon_search_result.dart';

/// Runs FTS5 Bible and Sermon search using sqlite3 (bundled SQLite with FTS5 support).
/// Use this instead of sqflite for search to avoid "no such module: fts5" on Android.

/// Converts a sqlite3 Row + column names to Map for fromMap.
Map<String, dynamic> _rowToMap(List<String> columnNames, Row row) {
  final map = <String, dynamic>{};
  for (var i = 0; i < columnNames.length; i++) {
    final v = row.columnAt(i);
    map[columnNames[i]] = v;
  }
  return map;
}

/// Run Bible FTS search using sqlite3. Returns empty list if file missing or query fails.
Future<List<BibleSearchResult>> searchBibleFts({
  required String dbPath,
  required String languageCode,
  required String matchPattern,
  required int limit,
  required int offset,
  List<String>? bookFilters,
}) async {
  if (!await File(dbPath).exists()) return [];
  final db = sqlite3.open(dbPath, mode: OpenMode.readOnly);
  try {
    var sql = '''
      SELECT 
          v.id,
          v.language,
          v.book,
          v.book_index,
          v.chapter,
          v.verse,
          v.text,
          snippet(bible_fts, 2, '<b>', '</b>', '...', 64) AS highlighted,
          bm25(bible_fts) AS rank
      FROM bible_fts
      INNER JOIN bible_verses v ON bible_fts.rowid = v.id
      WHERE bible_fts MATCH ?
    ''';
    var args = <Object?>[matchPattern];
    if (bookFilters != null && bookFilters.isNotEmpty) {
      final placeholders = List.filled(bookFilters.length, '?').join(',');
      sql += ' AND v.book IN ($placeholders)';
      args.addAll(bookFilters);
    }
    sql += ' ORDER BY rank LIMIT ? OFFSET ?';
    args.addAll([limit, offset]);

    final result = db.select(sql, args);
    final columnNames = result.columnNames;
    return result.map((row) => BibleSearchResult.fromMap(_rowToMap(columnNames, row))).toList();
  } catch (e) {
    return [];
  } finally {
    db.close();
  }
}

/// Count Bible FTS results using sqlite3.
Future<int> countBibleFts({
  required String dbPath,
  required String matchPattern,
  List<String>? bookFilters,
}) async {
  if (!await File(dbPath).exists()) return 0;
  final db = sqlite3.open(dbPath, mode: OpenMode.readOnly);
  try {
    var sql = 'SELECT COUNT(*) FROM bible_fts WHERE bible_fts MATCH ?';
    var args = <Object?>[matchPattern];
    if (bookFilters != null && bookFilters.isNotEmpty) {
      sql = '''
        SELECT COUNT(*) 
        FROM bible_fts 
        INNER JOIN bible_verses v ON bible_fts.rowid = v.id 
        WHERE bible_fts MATCH ?
        AND v.book IN (${List.filled(bookFilters.length, '?').join(',')})
      ''';
      args.addAll(bookFilters);
    }
    final result = db.select(sql, args);
    if (result.isEmpty) return 0;
    final v = result.first.columnAt(0);
    return (v is int) ? v : (v as num).toInt();
  } catch (e) {
    return 0;
  } finally {
    db.close();
  }
}

/// Run Sermon FTS search using sqlite3. Returns empty list if file missing or query fails.
Future<List<SermonSearchResult>> searchSermonFts({
  required String dbPath,
  required String languageCode,
  required String matchPattern,
  required int limit,
  required int offset,
}) async {
  if (!await File(dbPath).exists()) return [];
  final db = sqlite3.open(dbPath, mode: OpenMode.readOnly);
  try {
    const sql = '''
      SELECT 
        s.id AS sermon_id,
        s.title,
        s.language,
        s.date,
        s.year,
        s.location,
        p.paragraph_number,
        p.paragraph_label,
        p.text,
        snippet(sermon_fts, 0, '<b>', '</b>', '...', 64) AS highlighted,
        bm25(sermon_fts) AS rank
      FROM sermon_fts
      JOIN sermon_paragraphs p ON sermon_fts.rowid = p.id
      JOIN sermons s ON p.sermon_id = s.id
      WHERE sermon_fts MATCH ?
        AND s.language = ?
      ORDER BY rank
      LIMIT ? OFFSET ?
    ''';
    final result = db.select(sql, [matchPattern, languageCode, limit, offset]);
    final columnNames = result.columnNames;
    return result.map((row) => SermonSearchResult.fromMap(_rowToMap(columnNames, row))).toList();
  } catch (e) {
    return [];
  } finally {
    db.close();
  }
}
