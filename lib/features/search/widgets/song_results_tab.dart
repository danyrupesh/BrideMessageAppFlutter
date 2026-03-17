import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/search_provider.dart';
import '../../common/widgets/cards.dart';
import '../../songs/utils/song_search_utils.dart';

class SongResultsTab extends ConsumerWidget {
  const SongResultsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(searchProvider);

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null) {
      return Center(
        child: Text(
          'Error: ${state.error}',
          style: const TextStyle(color: Colors.red),
        ),
      );
    }
    if (state.query.isEmpty || state.query.length <= 2) {
      return const Center(child: Text('Type at least 3 characters to search'));
    }
    final results = state.songResults;
    if (results.isEmpty) {
      return Center(child: Text('No songs found for "${state.query}"'));
    }

    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final hymn = results[index];
        return SongListCard(
          number: hymn.hymnNo,
          title: hymn.title,
          subtitle: buildSongSearchSubtitle(
            firstLine: hymn.firstLine,
            lyrics: hymn.lyrics,
            query: state.query,
          ),
          keyBadge: hymn.chord.isEmpty ? null : hymn.chord,
          isFavorite: hymn.isFavorite,
          highlightQuery: state.query,
          onTap: () {
            context.push(
              '/song-detail',
              extra: hymn.hymnNo,
            );
          },
          onToggleFavorite: null,
        );
      },
    );
  }
}
