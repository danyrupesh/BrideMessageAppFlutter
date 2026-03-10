import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../common/widgets/cards.dart';
import '../common/widgets/chips.dart';

class SongsScreen extends StatefulWidget {
  const SongsScreen({super.key});

  @override
  State<SongsScreen> createState() => _SongsScreenState();
}

class _SongsScreenState extends State<SongsScreen> {
  bool _showFavoritesOnly = false;
  String _query = '';

  // Placeholder demo data; wire to real repository later.
  final _songs = List.generate(
    20,
    (index) => (
      number: index + 1,
      title: index == 0 ? 'ONLY BELIEVE' : 'Sample Hymn ${index + 1}',
      firstLine: 'Fear not, little flock,',
      key: index.isEven ? 'C' : 'Ab',
      isFavorite: index.isEven,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final filtered = _songs.where((song) {
      if (_showFavoritesOnly && !song.isFavorite) return false;
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return song.title.toLowerCase().contains(q) ||
          song.firstLine.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Only Believe Songs'),
            Text(
              '1196 hymns',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () async {
              final result = await showSearch<String?>(
                context: context,
                delegate: _SongSearchDelegate(initial: _query),
              );
              if (result != null) {
                setState(() {
                  _query = result;
                });
              }
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
                PillToggleChip(
                  label: 'All',
                  icon: Icons.music_note,
                  selected: !_showFavoritesOnly,
                  onTap: () {
                    setState(() {
                      _showFavoritesOnly = false;
                    });
                  },
                ),
                const SizedBox(width: 8),
                PillToggleChip(
                  label: 'Favorites',
                  icon: Icons.favorite,
                  selected: _showFavoritesOnly,
                  onTap: () {
                    setState(() {
                      _showFavoritesOnly = true;
                    });
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: filtered.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final song = filtered[index];
                return SongListCard(
                  number: song.number,
                  title: song.title,
                  subtitle: song.firstLine,
                  keyBadge: song.key,
                  isFavorite: song.isFavorite,
                  onTap: () {
                    // TODO: Navigate to song lyrics reader when implemented.
                  },
                  onToggleFavorite: () {
                    setState(() {
                      final idx =
                          _songs.indexWhere((element) => element.number == song.number);
                      if (idx != -1) {
                        final current = _songs[idx];
                        _songs[idx] = (
                          number: current.number,
                          title: current.title,
                          firstLine: current.firstLine,
                          key: current.key,
                          isFavorite: !current.isFavorite,
                        );
                      }
                    });
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SongSearchDelegate extends SearchDelegate<String?> {
  _SongSearchDelegate({String initial = ''}) : super(searchFieldLabel: 'Search songs') {
    query = initial;
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    if (query.isEmpty) return null;
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () => query = '',
      ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    // Return the query to the SongsScreen, which will filter its list.
    return Center(
      child: ElevatedButton(
        onPressed: () => close(context, query),
        child: Text('Search for "$query"'),
      ),
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return const SizedBox.shrink();
  }
}

