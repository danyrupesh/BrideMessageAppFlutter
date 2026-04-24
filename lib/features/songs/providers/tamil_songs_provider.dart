import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/tamil_song_models.dart';
import '../../../core/database/tamil_song_repository.dart';

class TamilSongsFilter {
  final String query;
  final TamilSongSort sortBy;
  final int? artistId;
  final int? tagId;
  final bool pptOnly;
  final bool lyricsOnly;
  final bool featuredOnly;
  final bool searchContent;

  TamilSongsFilter({
    this.query = '',
    this.sortBy = TamilSongSort.nameAz,
    this.artistId,
    this.tagId,
    this.pptOnly = false,
    this.lyricsOnly = false,
    this.featuredOnly = false,
    this.searchContent = false,
  });

  TamilSongsFilter copyWith({
    String? query,
    TamilSongSort? sortBy,
    int? artistId,
    int? tagId,
    bool? pptOnly,
    bool? lyricsOnly,
    bool? featuredOnly,
    bool? searchContent,
  }) {
    return TamilSongsFilter(
      query: query ?? this.query,
      sortBy: sortBy ?? this.sortBy,
      artistId: artistId == -1 ? null : (artistId ?? this.artistId),
      tagId: tagId == -1 ? null : (tagId ?? this.tagId),
      pptOnly: pptOnly ?? this.pptOnly,
      lyricsOnly: lyricsOnly ?? this.lyricsOnly,
      featuredOnly: featuredOnly ?? this.featuredOnly,
      searchContent: searchContent ?? this.searchContent,
    );
  }
}

class TamilSongsState {
  final List<TamilSong> songs;
  final bool isLoading;
  final String? error;
  final bool hasMore;
  final TamilSongsFilter filter;

  TamilSongsState({
    required this.songs,
    this.isLoading = false,
    this.error,
    this.hasMore = true,
    required this.filter,
  });

  TamilSongsState copyWith({
    List<TamilSong>? songs,
    bool? isLoading,
    String? error,
    bool? hasMore,
    TamilSongsFilter? filter,
  }) {
    return TamilSongsState(
      songs: songs ?? this.songs,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      hasMore: hasMore ?? this.hasMore,
      filter: filter ?? this.filter,
    );
  }
}

class TamilSongsNotifier extends Notifier<TamilSongsState> {
  static const int _limit = 50;

  @override
  TamilSongsState build() {
    // Initial load
    Future.microtask(() => loadSongs());
    return TamilSongsState(songs: [], filter: TamilSongsFilter());
  }

  TamilSongRepository get _repository => ref.read(tamilSongRepositoryProvider);

  Future<void> loadSongs({bool refresh = true}) async {
    if (state.isLoading) return;

    if (refresh) {
      state = state.copyWith(isLoading: true, songs: [], hasMore: true);
    } else if (!state.hasMore) {
      return;
    }

    try {
      final songs = await _repository.searchSongs(
        query: state.filter.query,
        sortBy: state.filter.sortBy,
        artistId: state.filter.artistId,
        tagId: state.filter.tagId,
        pptOnly: state.filter.pptOnly,
        lyricsOnly: state.filter.lyricsOnly,
        featuredOnly: state.filter.featuredOnly,
        searchContent: state.filter.searchContent,
        limit: _limit,
        offset: refresh ? 0 : state.songs.length,
      );

      state = state.copyWith(
        isLoading: false,
        songs: refresh ? songs : [...state.songs, ...songs],
        hasMore: songs.length == _limit,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void updateFilter(TamilSongsFilter filter) {
    state = state.copyWith(filter: filter);
    loadSongs(refresh: true);
  }

  void setQuery(String query) {
    if (state.filter.query == query) return;
    state = state.copyWith(filter: state.filter.copyWith(query: query));
    loadSongs(refresh: true);
  }

  void togglePptOnly() {
    updateFilter(state.filter.copyWith(pptOnly: !state.filter.pptOnly));
  }

  void toggleLyricsOnly() {
    updateFilter(state.filter.copyWith(lyricsOnly: !state.filter.lyricsOnly));
  }

  void toggleFeaturedOnly() {
    updateFilter(state.filter.copyWith(featuredOnly: !state.filter.featuredOnly));
  }

  void toggleSearchContent() {
    updateFilter(state.filter.copyWith(searchContent: !state.filter.searchContent));
  }

  void setSort(TamilSongSort sort) {
    updateFilter(state.filter.copyWith(sortBy: sort));
  }

  void setArtist(int? artistId) {
    updateFilter(state.filter.copyWith(artistId: artistId ?? -1));
  }

  void setTag(int? tagId) {
    updateFilter(state.filter.copyWith(tagId: tagId ?? -1));
  }
  
  void clearFilters() {
    updateFilter(TamilSongsFilter(query: state.filter.query));
  }
}

final tamilSongsProvider = NotifierProvider<TamilSongsNotifier, TamilSongsState>(TamilSongsNotifier.new);

final tamilArtistsProvider = FutureProvider<List<TamilArtist>>((ref) async {
  return ref.watch(tamilSongRepositoryProvider).getAllArtists();
});

final tamilTagsProvider = FutureProvider<List<TamilTag>>((ref) async {
  return ref.watch(tamilSongRepositoryProvider).getAllTags();
});

final tamilSongDetailProvider = FutureProvider.family<TamilSong?, int>((ref, id) async {
  return ref.watch(tamilSongRepositoryProvider).getSongById(id);
});
