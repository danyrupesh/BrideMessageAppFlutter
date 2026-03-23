import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/search_provider.dart';
import '../../reader/providers/reader_provider.dart';
import '../../reader/models/reader_tab.dart';
import '../../../core/database/models/bible_search_result.dart';
import '../../common/widgets/cards.dart';
import '../../common/widgets/chips.dart';
import '../../common/widgets/fts_highlight_text.dart';

class BibleResultsTab extends ConsumerWidget {
  const BibleResultsTab({super.key});

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

    final results = state.bibleResults;

    if (results.isEmpty && !state.isLoading) {
      return Center(child: Text('No results found for "${state.query}"'));
    }

    // Group by book
    final Map<String, List<BibleSearchResult>> byBook = {};
    for (final r in results) {
      byBook.putIfAbsent(r.book, () => []).add(r);
    }

    final children = <Widget>[];

    // Bible-specific filter and sort rows (Both | OT | NT, Book order | Relevance)
    children.add(
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(
          children: [
            PillToggleChip(
              label: 'Both',
              selected: state.bibleScope == BibleScope.both,
              onTap: () => notifier.updateBibleScope(BibleScope.both),
            ),
            const SizedBox(width: 8),
            PillToggleChip(
              label: 'Old Test',
              selected: state.bibleScope == BibleScope.oldTest,
              onTap: () => notifier.updateBibleScope(BibleScope.oldTest),
            ),
            const SizedBox(width: 8),
            PillToggleChip(
              label: 'New Test',
              selected: state.bibleScope == BibleScope.newTest,
              onTap: () => notifier.updateBibleScope(BibleScope.newTest),
            ),
          ],
        ),
      ),
    );

    children.add(
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(
          children: [
            PillToggleChip(
              label: 'Book order',
              selected: state.sortOrder == SortOrder.bookOrder,
              onTap: () => notifier.updateSortOrder(SortOrder.bookOrder),
            ),
            const SizedBox(width: 8),
            PillToggleChip(
              label: 'Relevance',
              selected: state.sortOrder == SortOrder.relevance,
              onTap: () => notifier.updateSortOrder(SortOrder.relevance),
            ),
          ],
        ),
      ),
    );
    byBook.forEach((book, items) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            '$book (${items.length})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
      for (final r in items) {
        children.add(
          BibleResultCard(
            reference: '${r.book} ${r.chapter}:${r.verse}',
            book: r.book,
            chapter: r.chapter,
            verse: r.verse,
            snippet: FtsHighlightText(rawSnippet: r.highlighted ?? r.text),
            onTap: () {
              ref
                  .read(readerProvider.notifier)
                  .openTabForLanguage(
                    state.languageCode,
                    ReaderTab(
                      type: ReaderContentType.bible,
                      title: '${r.book} ${r.chapter}',
                      book: r.book,
                      chapter: r.chapter,
                      verse: r.verse,
                      initialSearchQuery: state.query,
                      openedFromSearch: true,
                    ),
                  );
              context.push('/reader');
            },
          ),
        );
      }
    });

    final hasMore = state.bibleResults.length < state.bibleTotalCount;
    if (hasMore || state.isLoadingMore) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
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
        ),
      );
    }

    return ListView(children: children);
  }
}
