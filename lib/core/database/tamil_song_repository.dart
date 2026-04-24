import 'package:sqflite/sqflite.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'database_manager.dart';
import '../../features/songs/models/tamil_song_models.dart';

class TamilSongRepository {
  TamilSongRepository(this._dbManager);

  final DatabaseManager _dbManager;
  static const String _dbFileName = 'songs.db';

  Future<Database> _openDb() => _dbManager.getDatabase(_dbFileName);

  Future<List<TamilArtist>> getAllArtists() async {
    final db = await _openDb();
    final rows = await db.rawQuery('SELECT * FROM artists ORDER BY name ASC');
    return rows.map((row) => TamilArtist.fromRow(row)).toList();
  }

  Future<List<TamilTag>> getAllTags() async {
    final db = await _openDb();
    final rows = await db.rawQuery('SELECT * FROM tags ORDER BY name ASC');
    return rows.map((row) => TamilTag.fromRow(row)).toList();
  }

  Future<List<TamilSong>> searchSongs({
    String? query,
    TamilSongSort sortBy = TamilSongSort.nameAz,
    int? artistId,
    int? tagId,
    bool pptOnly = false,
    bool lyricsOnly = false,
    bool featuredOnly = false,
    bool searchContent = false,
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await _openDb();
    final args = <Object?>[];
    final conditions = <String>['is_active = 1'];

    if (query != null && query.trim().isNotEmpty) {
      final q = '%${query.trim().toLowerCase()}%';
      if (searchContent) {
        conditions.add('(LOWER(s.name) LIKE ? OR LOWER(s.tamil_name) LIKE ? OR LOWER(s.lyrics_preview) LIKE ? OR LOWER(s.full_lyrics) LIKE ?)');
        args.addAll([q, q, q, q]);
      } else {
        conditions.add('(LOWER(s.name) LIKE ? OR LOWER(s.tamil_name) LIKE ? OR CAST(s.numeric_id AS TEXT) LIKE ?)');
        args.addAll([q, q, q]);
      }
    }

    if (artistId != null) {
      conditions.add('s.artist_id = ?');
      args.add(artistId);
    }

    if (tagId != null) {
      conditions.add('s.id IN (SELECT song_id FROM song_tags WHERE tag_id = ?)');
      args.add(tagId);
    }

    if (pptOnly) {
      conditions.add('s.has_ppt = 1');
    }

    if (lyricsOnly) {
      conditions.add('s.has_lyrics = 1');
    }

    if (featuredOnly) {
      conditions.add('s.is_featured = 1');
    }

    String orderBy;
    switch (sortBy) {
      case TamilSongSort.nameAz:
        orderBy = 's.name ASC';
        break;
      case TamilSongSort.songNo:
        orderBy = 's.numeric_id ASC';
        break;
      case TamilSongSort.mostViewed:
        orderBy = 's.view_count DESC';
        break;
      case TamilSongSort.mostDownloaded:
        orderBy = 's.download_count DESC';
        break;
      case TamilSongSort.latest:
        orderBy = 's.created_at DESC';
        break;
    }

    final queryStr = '''
      SELECT s.*, a.name as artist_name 
      FROM songs s
      LEFT JOIN artists a ON s.artist_id = a.id
      WHERE ${conditions.join(' AND ')}
      ORDER BY $orderBy
      LIMIT ? OFFSET ?
    ''';
    args.addAll([limit, offset]);

    final rows = await db.rawQuery(queryStr, args);
    return rows.map((row) => TamilSong.fromRow(row)).toList();
  }

  Future<TamilSong?> getSongById(int id) async {
    final db = await _openDb();
    final rows = await db.rawQuery('''
      SELECT s.*, a.name as artist_name 
      FROM songs s
      LEFT JOIN artists a ON s.artist_id = a.id
      WHERE s.id = ? LIMIT 1
    ''', [id]);
    
    if (rows.isEmpty) return null;
    return TamilSong.fromRow(rows.first);
  }

  Future<TamilSong?> getNextSong(int currentId, {
    String? query,
    TamilSongSort sortBy = TamilSongSort.nameAz,
    int? artistId,
    int? tagId,
    bool pptOnly = false,
    bool lyricsOnly = false,
    bool featuredOnly = false,
  }) async {
    // This is a bit complex because we need to respect the current filters
    // For simplicity, we can fetch the list and find the next index, 
    // or we can implement a specific query if we know the order.
    // Let's implement it by fetching the list for now, or just songNo based for simple next/prev.
    
    // If it's songNo sort, it's easy:
    if (sortBy == TamilSongSort.songNo) {
       final db = await _openDb();
       final current = await getSongById(currentId);
       if (current == null || current.numericId == null) return null;
       
       final rows = await db.rawQuery('''
         SELECT s.*, a.name as artist_name 
         FROM songs s
         LEFT JOIN artists a ON s.artist_id = a.id
         WHERE s.numeric_id > ? AND s.is_active = 1
         ORDER BY s.numeric_id ASC LIMIT 1
       ''', [current.numericId]);
       
       if (rows.isEmpty) return null;
       return TamilSong.fromRow(rows.first);
    }
    
    return null; // Fallback or more complex logic needed
  }

  Future<TamilSong?> getPreviousSong(int currentId, {
    TamilSongSort sortBy = TamilSongSort.songNo,
  }) async {
    if (sortBy == TamilSongSort.songNo) {
       final db = await _openDb();
       final current = await getSongById(currentId);
       if (current == null || current.numericId == null) return null;
       
       final rows = await db.rawQuery('''
         SELECT s.*, a.name as artist_name 
         FROM songs s
         LEFT JOIN artists a ON s.artist_id = a.id
         WHERE s.numeric_id < ? AND s.is_active = 1
         ORDER BY s.numeric_id DESC LIMIT 1
       ''', [current.numericId]);
       
       if (rows.isEmpty) return null;
       return TamilSong.fromRow(rows.first);
    }
    return null;
  }
}

final tamilSongRepositoryProvider = Provider<TamilSongRepository>((ref) {
  return TamilSongRepository(DatabaseManager());
});
