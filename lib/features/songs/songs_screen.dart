import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../common/widgets/cards.dart';
import '../common/widgets/chips.dart';
import 'providers/songs_provider.dart';
import 'utils/song_search_utils.dart';

class SongsScreen extends ConsumerStatefulWidget {
  const SongsScreen({super.key});

  @override
  ConsumerState<SongsScreen> createState() => _SongsScreenState();
}

class _SongsScreenState extends ConsumerState<SongsScreen> {
  String _query = '';
  bool _isSearchExpanded = false;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(songsProvider);
    final notifier = ref.read(songsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_isSearchExpanded) {
              setState(() {
                _isSearchExpanded = false;
                _searchController.clear();
                _query = '';
              });
              notifier.onClearSearch();
            } else {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/');
              }
            }
          },
        ),
        title: _isSearchExpanded
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search songs, lyrics...',
                  border: InputBorder.none,
                ),
                textInputAction: TextInputAction.search,
                onChanged: (value) {
                  setState(() {
                    _query = value;
                  });
                  notifier.onSearchQueryChanged(value);
                },
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Only Believe Songs'),
                  Text(
                    '1196 hymns',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
        actions: _isSearchExpanded
            ? [
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _query = '';
                      });
                      notifier.onClearSearch();
                    },
                  ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.manage_search),
                  tooltip: 'Advanced Search',
                  onPressed: () => context.push('/search?tab=songs'),
                ),
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () {
                    setState(() {
                      _isSearchExpanded = true;
                      _searchController.text =
                          state is SongsSuccess ? state.query : _query;
                    });
                  },
                ),
              ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                if (!_isSearchExpanded) ...[
                  PillToggleChip(
                    label: 'All',
                    icon: Icons.music_note,
                    selected: state is SongsSuccess && !state.showFavoritesOnly,
                    onTap: () {
                      if (state is SongsSuccess && state.showFavoritesOnly) {
                        notifier.toggleFavoritesFilter();
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  PillToggleChip(
                    label: 'Favorites',
                    icon: Icons.favorite,
                    selected: state is SongsSuccess && state.showFavoritesOnly,
                    onTap: () {
                      notifier.toggleFavoritesFilter();
                    },
                  ),
                ] else ...[
                  PillToggleChip(
                    label: 'Lyrics',
                    icon: Icons.library_music,
                    selected:
                        state is SongsSuccess ? state.searchLyrics : false,
                    onTap: notifier.toggleSearchLyrics,
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: _buildBodyForState(
              state,
              notifier,
              theme,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBodyForState(
    SongsUiState state,
    SongsNotifier notifier,
    ThemeData theme,
  ) {
    if (state is SongsLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state is SongsError) {
      return Center(
        child: Text(
          state.message,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.error),
        ),
      );
    }

    final success = state as SongsSuccess;
    if (success.songs.isEmpty) {
      final isSearch = success.isSearchActive;
      final isFavs = success.showFavoritesOnly;
      final message = () {
        if (isSearch) return 'No results for "${success.query}"';
        if (isFavs) return 'No favorite songs yet.';
        return 'No songs found.';
      }();
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    final label = () {
      if (success.isSearchActive) {
        final base =
            success.searchLyrics ? 'lyrics results' : 'results';
        return '${success.songs.length} $base for "${success.query}"';
      }
      return '${success.songs.length} of ${success.totalCount} hymns';
    }();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: Text(
            label,
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              final metrics = notification.metrics;
              if (!success.isSearchActive &&
                  success.hasMore &&
                  metrics.pixels >=
                      metrics.maxScrollExtent - 200) {
                notifier.loadMore();
              }
              return false;
            },
            child: ListView.separated(
              controller: _scrollController,
              itemCount: success.songs.length,
              separatorBuilder: (context, index) =>
                  const Divider(height: 1),
              itemBuilder: (context, index) {
                final hymn = success.songs[index];
                final subtitle = success.isSearchActive &&
                        success.searchLyrics
                    ? buildSongSearchSubtitle(
                        firstLine: hymn.firstLine,
                        lyrics: hymn.lyrics,
                        query: _query,
                      )
                    : hymn.firstLine;
                return SongListCard(
                  number: hymn.hymnNo,
                  title: hymn.title,
                  subtitle: subtitle,
                  keyBadge: hymn.chord.isEmpty ? null : hymn.chord,
                  isFavorite: hymn.isFavorite,
                  highlightQuery: _isSearchExpanded ? _query : null,
                  onTap: () {
                    context.push(
                      '/song-detail',
                      extra: hymn.hymnNo,
                    );
                  },
                  onToggleFavorite: () =>
                      notifier.toggleFavorite(hymn.hymnNo),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

}
