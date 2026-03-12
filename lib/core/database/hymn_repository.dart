import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import 'database_manager.dart';
import 'hymn_favorites_store.dart';
import 'models/hymn_models.dart';

class HymnRepository {
  HymnRepository(this._dbManager, this._favoritesStore);

  final DatabaseManager _dbManager;
  final HymnFavoritesStore _favoritesStore;

  static const String _dbFileName = 'hymn.db';

  Future<Database> _openDb() => _dbManager.getDatabase(_dbFileName);

  Future<int> getSongCount() async {
    final db = await _openDb();
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM Hymns');
    if (rows.isEmpty) return 0;
    final value = rows.first['c'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  Future<List<Hymn>> getAllSongs() async {
    final db = await _openDb();
    final rows = await db.rawQuery(
      'SELECT * FROM Hymns ORDER BY HymnNo ASC',
    );
    final favorites = await _favoritesStore.loadFavorites();
    return rows
        .map(
          (row) => Hymn.fromRow(
            row,
            isFavorite: favorites.contains(row['HymnNo'] as int),
          ),
        )
        .toList();
  }

  Future<Hymn?> getSongByNo(int hymnNo) async {
    final db = await _openDb();
    final rows = await db.rawQuery(
      'SELECT * FROM Hymns WHERE HymnNo = ? LIMIT 1',
      [hymnNo],
    );
    if (rows.isEmpty) return null;
    final favorites = await _favoritesStore.loadFavorites();
    return Hymn.fromRow(
      rows.first,
      isFavorite: favorites.contains(hymnNo),
    );
  }

  Future<Hymn?> getNextSong(int currentNo) async {
    final db = await _openDb();
    final rows = await db.rawQuery(
      'SELECT * FROM Hymns WHERE HymnNo > ? ORDER BY HymnNo ASC LIMIT 1',
      [currentNo],
    );
    if (rows.isEmpty) return null;
    final hymnNo = rows.first['HymnNo'] as int;
    final favorites = await _favoritesStore.loadFavorites();
    return Hymn.fromRow(
      rows.first,
      isFavorite: favorites.contains(hymnNo),
    );
  }

  Future<Hymn?> getPreviousSong(int currentNo) async {
    final db = await _openDb();
    final rows = await db.rawQuery(
      'SELECT * FROM Hymns WHERE HymnNo < ? ORDER BY HymnNo DESC LIMIT 1',
      [currentNo],
    );
    if (rows.isEmpty) return null;
    final hymnNo = rows.first['HymnNo'] as int;
    final favorites = await _favoritesStore.loadFavorites();
    return Hymn.fromRow(
      rows.first,
      isFavorite: favorites.contains(hymnNo),
    );
  }

  Future<List<Hymn>> searchSongs(
    String query, {
    bool searchLyrics = false,
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await _openDb();
    final favorites = await _favoritesStore.loadFavorites();

    final cleaned = query.trim().toLowerCase();
    if (cleaned.isEmpty) return const [];

    final like = '%$cleaned%';
    final args = <Object?>[like, like];
    final buffer = StringBuffer(
      'SELECT * FROM Hymns '
      'WHERE LOWER(HymnTitle) LIKE ? '
      'OR LOWER(FirstIndexSearch) LIKE ?',
    );

    if (searchLyrics) {
      buffer.write(' OR LOWER(HymnLyrics) LIKE ?');
      args.add(like);
    }

    buffer.write(' ORDER BY HymnNo ASC LIMIT ? OFFSET ?');
    args.addAll([limit, offset]);

    final rows = await db.rawQuery(buffer.toString(), args);
    return rows
        .map(
          (row) => Hymn.fromRow(
            row,
            isFavorite: favorites.contains(row['HymnNo'] as int),
          ),
        )
        .toList();
  }

  Future<void> toggleFavorite(int hymnNo) =>
      _favoritesStore.toggleFavorite(hymnNo);
}

final hymnRepositoryProvider = Provider<HymnRepository>((ref) {
  return HymnRepository(
    DatabaseManager(),
    HymnFavoritesStore(),
  );
});

