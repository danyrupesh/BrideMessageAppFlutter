import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/search_provider.dart';
import '../../../core/database/models/sermon_search_result.dart';
import '../../common/widgets/cards.dart';
import '../../common/widgets/fts_highlight_text.dart';

class CodResultsTab extends ConsumerWidget {
  const CodResultsTab({super.key});

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
    final results = state.codResults;
    if (results.isEmpty) {
      return Center(child: Text('No COD results for "${state.query}"'));
    }

    final hasMore = state.codResults.length < state.codTotalCount;
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
        final subParts = <String>[
          if (r.paragraphLabel != null && r.paragraphLabel!.trim().isNotEmpty)
            r.paragraphLabel!.trim(),
          if (r.paragraphNumber != null) '¶${r.paragraphNumber}',
        ];
        return SermonResultCard(
          id: r.sermonId,
          leadingIdOverride: r.displayLeadingId,
          title: r.title,
          date: r.date,
          duration: null,
          location: r.location,
          metaRightBadge: r.year?.toString(),
          subtitle: subParts.isEmpty ? null : subParts.join(' · '),
          highlightQuery: state.query,
          snippet: r.snippet.trim().isNotEmpty
              ? FtsHighlightText(rawSnippet: r.snippet)
              : null,
          onTap: () {
            final lang = state.languageCode;
            final q = state.query.trim();
            final qp = <String, String>{
              'lang': lang,
              if (r.codAnswerParagraphId != null)
                'para': '${r.codAnswerParagraphId}',
              if (q.isNotEmpty) 'q': q,
            };
            context.push(
              Uri(
                path: '/cod/detail/${Uri.encodeComponent(r.sermonId)}',
                queryParameters: qp,
              ).toString(),
            );
          },
        );
      },
    );
  }
}
