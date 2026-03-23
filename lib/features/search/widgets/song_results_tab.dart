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
    final notifier = ref.read(searchProvider.notifier);

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

    final hasMore = state.songResults.length < state.songTotalCount;
    final showFooter = hasMore || state.isLoadingMore;

    return ListView.separated(
      itemCount: results.length + (showFooter ? 1 : 0),
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index >= results.length) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
            child: Center(
              child: state.isLoadingMore
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : FilledButton.tonal(
                      onPressed: notifier.loadMoreCurrentTab,
                      child: const Text('Load more'),
                    ),
            ),
          );
        }
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
            context.push('/song-detail', extra: hymn.hymnNo);
          },
          onToggleFavorite: null,
        );
      },
    );
  }
}
