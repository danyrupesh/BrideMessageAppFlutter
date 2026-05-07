import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/search_provider.dart';
import '../../../core/database/models/sermon_search_result.dart';
import '../../common/widgets/cards.dart';
import '../../common/widgets/fts_highlight_text.dart';
import '../../onboarding/onboarding_screen.dart';
import '../../cod/providers/cod_provider.dart';

class CodResultsTab extends ConsumerWidget {
  const CodResultsTab({super.key});

  bool _isMissingCodDbError(String? error) {
    if (error == null) return false;
    final lower = error.toLowerCase();
    return lower.contains('cod database is not installed') ||
        (lower.contains('database file not found') &&
            (lower.contains('cod_english.db') ||
                lower.contains('cod_tamil.db')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(searchProvider);
    final notifier = ref.read(searchProvider.notifier);
    final codDbExists = ref.watch(
      codDatabaseExistsProvider(state.languageCode),
    );

    if (codDbExists.maybeWhen(data: (exists) => !exists, orElse: () => false)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_off_outlined, size: 46),
              const SizedBox(height: 10),
              Text(
                'COD database is not installed',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Import COD English / COD Tamil database to search COD content.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          const OnboardingScreen(showImportDirectly: true),
                    ),
                  );
                },
                icon: const Icon(Icons.cloud_download_outlined),
                label: const Text('Import Database'),
              ),
            ],
          ),
        ),
      );
    }

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null) {
      if (_isMissingCodDbError(state.error)) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.folder_off_outlined, size: 46),
                const SizedBox(height: 10),
                Text(
                  'COD database is not installed',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Import COD English / COD Tamil database to search COD content.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            const OnboardingScreen(showImportDirectly: true),
                      ),
                    );
                  },
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('Import Database'),
                ),
              ],
            ),
          ),
        );
      }
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
          date: r.date ?? '',
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
