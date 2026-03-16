import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/search_provider.dart';
import '../../reader/models/reader_tab.dart';
import '../../sermons/providers/sermon_flow_provider.dart';
import '../../../core/database/models/sermon_search_result.dart';
import '../../common/widgets/cards.dart';
import '../../common/widgets/fts_highlight_text.dart';

class CodResultsTab extends ConsumerWidget {
  const CodResultsTab({super.key});

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
    final results = state.codResults;
    if (results.isEmpty) {
      return Center(child: Text('No COD results for "${state.query}"'));
    }

    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final SermonSearchResult r = results[index];
        return SermonResultCard(
          id: r.sermonId,
          title: r.title,
          date: r.date,
          duration: null,
          location: r.location,
          metaRightBadge: r.year?.toString(),
          subtitle: r.paragraphNumber != null ? '¶${r.paragraphNumber}' : null,
          highlightQuery: state.query,
          snippet: r.snippet.trim().isNotEmpty
              ? FtsHighlightText(rawSnippet: r.snippet)
              : null,
          onTap: () {
            ref.read(sermonFlowProvider.notifier).openSermonForLanguage(
                  state.languageCode,
                  ReaderTab(
                    type: ReaderContentType.sermon,
                    title: r.title,
                    sermonId: r.sermonId,
                    initialSearchQuery: state.query,
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
