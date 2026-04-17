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
import '../../onboarding/onboarding_screen.dart';

class BibleResultsTab extends ConsumerWidget {
  const BibleResultsTab({super.key});

  bool _isMissingBibleDbError(String? error) {
    if (error == null) return false;
    final lower = error.toLowerCase();
    return lower.contains('bible database is not installed') ||
        (lower.contains('database file not found') &&
            lower.contains('bible_') &&
            lower.contains('.db'));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(searchProvider);
    final notifier = ref.read(searchProvider.notifier);
    final booksAsync = ref.watch(bibleBooksForLangProvider(state.languageCode));
    final bibleDbExists = ref.watch(
      bibleDatabaseExistsByLangProvider(state.languageCode),
    );

    if (bibleDbExists.maybeWhen(
      data: (exists) => !exists,
      orElse: () => false,
    )) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_off_outlined, size: 46),
              const SizedBox(height: 10),
              Text(
                'Bible database is not installed',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Import Tamil/English Bible database to search Bible content.',
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
      if (_isMissingBibleDbError(state.error)) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.folder_off_outlined, size: 46),
                const SizedBox(height: 10),
                Text(
                  'Bible database is not installed',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Import Tamil/English Bible database to search Bible content.',
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

    final results = state.bibleResults;
    final books = booksAsync.asData?.value ?? const <Map<String, dynamic>>[];
    Map<String, dynamic>? selectedBook;
    for (final book in books) {
      if (book['book_index'] == state.bibleBookIndex) {
        selectedBook = book;
        break;
      }
    }
    final chapterCount = (selectedBook?['chapters'] as int?) ?? 0;
    final chapterOptions = List<int>.generate(chapterCount, (index) => index + 1);

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chapter range',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int?>(
              isExpanded: true,
              value: state.bibleBookIndex,
              decoration: const InputDecoration(
                labelText: 'Book',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('All books'),
                ),
                ...books.map(
                  (book) => DropdownMenuItem<int?>(
                    value: book['book_index'] as int,
                    child: Text(book['book'] as String),
                  ),
                ),
              ],
              onChanged: books.isEmpty ? null : notifier.updateBibleBookIndex,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    isExpanded: true,
                    value: state.bibleChapterFrom,
                    decoration: const InputDecoration(
                      labelText: 'From chapter',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Any'),
                      ),
                      ...chapterOptions.map(
                        (chapter) => DropdownMenuItem<int?>(
                          value: chapter,
                          child: Text(chapter.toString()),
                        ),
                      ),
                    ],
                    onChanged: selectedBook == null
                        ? null
                        : notifier.updateBibleChapterFrom,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    isExpanded: true,
                    value: state.bibleChapterTo,
                    decoration: const InputDecoration(
                      labelText: 'To chapter',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Any'),
                      ),
                      ...chapterOptions.map(
                        (chapter) => DropdownMenuItem<int?>(
                          value: chapter,
                          child: Text(chapter.toString()),
                        ),
                      ),
                    ],
                    onChanged: selectedBook == null
                        ? null
                        : notifier.updateBibleChapterTo,
                  ),
                ),
              ],
            ),
            if (state.bibleBookIndex != null ||
                state.bibleChapterFrom != null ||
                state.bibleChapterTo != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: notifier.clearBibleChapterRange,
                  child: const Text('Clear range'),
                ),
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
