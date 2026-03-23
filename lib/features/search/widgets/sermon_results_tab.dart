import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/search_provider.dart';
import '../../reader/models/reader_tab.dart';
import '../../sermons/providers/sermon_flow_provider.dart';
import '../../../core/database/models/sermon_search_result.dart';
import '../../common/widgets/cards.dart';
import '../../common/widgets/fts_highlight_text.dart';

class SermonResultsTab extends ConsumerWidget {
  const SermonResultsTab({super.key});

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
    final results = state.sermonResults;
    if (results.isEmpty) {
      return Center(child: Text('No sermons found for "${state.query}"'));
    }

    final hasMore = state.sermonResults.length < state.sermonTotalCount;
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
        final SermonSearchResult r = results[index];
        return SermonResultCard(
          id: r.sermonId,
          title: r.title,
          date: r.date,
          duration: null,
          location: r.location,
          metaRightBadge: r.year?.toString(),
          subtitle: r.paragraphNumber != null ? '¶${r.paragraphNumber}' : null,
          snippet: FtsHighlightText(rawSnippet: r.snippet),
          onTap: () {
            ref
                .read(sermonFlowProvider.notifier)
                .openSermonForLanguage(
                  state.languageCode,
                  ReaderTab(
                    type: ReaderContentType.sermon,
                    title: r.title,
                    sermonId: r.sermonId,
                    initialSearchQuery: state.query,
                    initialFocusParagraph: r.paragraphNumber,
                    openedFromSearch: true,
                  ),
                );
            context.push('/sermon-reader');
          },
        );
      },
    );
  }
}
