import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/hymn_repository.dart';
import '../../../core/database/models/hymn_models.dart';

sealed class SongsUiState {
  const SongsUiState();
}

class SongsLoading extends SongsUiState {
  const SongsLoading();
}

class SongsSuccess extends SongsUiState {
  final List<Hymn> songs;
  final String query;
  final bool isSearchActive;
  final bool showFavoritesOnly;
  final int totalCount;
  final bool hasMore;
  final bool searchLyrics;

  const SongsSuccess({
    required this.songs,
    required this.query,
    required this.isSearchActive,
    required this.showFavoritesOnly,
    required this.totalCount,
    required this.hasMore,
    required this.searchLyrics,
  });
}

class SongsError extends SongsUiState {
  final String message;
  const SongsError(this.message);
}

class SongsNotifier extends Notifier<SongsUiState> {
  static const int _pageSize = 20;

  HymnRepository get _repo => ref.read(hymnRepositoryProvider);

  String _query = '';
  bool _showFavoritesOnly = false;
  bool _searchLyrics = false;
  int _displayCount = _pageSize;
  int _songCount = 0;
  List<Hymn> _all = [];

  @override
  SongsUiState build() {
    _loadInitial();
    return const SongsLoading();
  }

  Future<void> _loadInitial() async {
    try {
      _songCount = await _repo.getSongCount();
      _all = await _repo.getAllSongs();
      _emit();
    } catch (e) {
      state = SongsError(e.toString());
    }
  }

  void onSearchQueryChanged(String query) {
    _query = query;
    _displayCount = _pageSize;
    _reload();
  }

  void onClearSearch() {
    _query = '';
    _searchLyrics = false;
    _displayCount = _pageSize;
    _reload();
  }

  void toggleFavoritesFilter() {
    _showFavoritesOnly = !_showFavoritesOnly;
    _emit();
  }

  void toggleSearchLyrics() {
    _searchLyrics = !_searchLyrics;
    _reload();
  }

  void loadMore() {
    final current = state;
    if (_query.isNotEmpty || current is! SongsSuccess) return;
    if (!current.hasMore) return;
    _displayCount += _pageSize;
    _emit();
  }

  Future<void> toggleFavorite(int hymnNo) async {
    await _repo.toggleFavorite(hymnNo);
    await _reload();
  }

  Future<void> _reload() async {
    try {
      if (_query.isEmpty) {
        _all = await _repo.getAllSongs();
      } else {
        _all = await _repo.searchSongs(
          _query,
          searchLyrics: _searchLyrics,
          limit: 200,
          offset: 0,
        );
      }
      _emit();
    } catch (e) {
      state = SongsError(e.toString());
    }
  }

  void _emit() {
    final filtered =
        _showFavoritesOnly ? _all.where((h) => h.isFavorite).toList() : _all;
    final paginated =
        _query.isEmpty ? filtered.take(_displayCount).toList() : filtered;
    state = SongsSuccess(
      songs: paginated,
      query: _query,
      isSearchActive: _query.isNotEmpty,
      showFavoritesOnly: _showFavoritesOnly,
      totalCount: _songCount,
      hasMore: _query.isEmpty && paginated.length < filtered.length,
      searchLyrics: _searchLyrics,
    );
  }
}

final songsProvider =
    NotifierProvider<SongsNotifier, SongsUiState>(SongsNotifier.new);

