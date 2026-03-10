import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'providers/search_history_provider.dart';
import 'providers/search_provider.dart';
import '../../core/database/models/bible_search_result.dart';
import '../../core/database/models/sermon_search_result.dart';
import '../../core/database/metadata/installed_database_model.dart';
import '../../core/database/metadata/installed_content_provider.dart';
import 'package:path/path.dart' as p;
import '../../core/database/database_manager.dart';
import '../../features/onboarding/services/selective_database_importer.dart';
import '../reader/providers/reader_provider.dart';
import '../reader/models/reader_tab.dart';
import '../common/widgets/cards.dart';
import '../common/widgets/chips.dart';
import '../common/widgets/fts_highlight_text.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _searchController = TextEditingController();
    // Warm FTS indexes on first search screen open (mirrors Android's SearchViewModel.warmUp).
    WidgetsBinding.instance.addPostFrameCallback((_) => _warmFts());
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        final notifier = ref.read(searchProvider.notifier);
        if (_tabController.index == 0) {
          notifier.updateTab(SearchTab.bible);
        } else if (_tabController.index == 1) {
          notifier.updateTab(SearchTab.sermon);
        } else {
          notifier.updateTab(SearchTab.all);
        }
      }
    });
  }

  Future<void> _warmFts() async {
    try {
      final registry = ref.read(installedDbRegistryProvider);
      final importer = SelectiveDatabaseImporter();
      final all = await registry.getAll();
      if (all.isEmpty) return;
      final dbDir = await DatabaseManager().getDatabaseDirectoryPath();
      for (final installed in all) {
        final fullPath = p.join(dbDir.path, installed.dbFileName);
        importer.warmUpFts(fullPath, installed.type);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchProvider);
    final history = ref.watch(searchHistoryProvider);

    // Sync external state changes back to UI if needed
    if (searchState.activeTab == SearchTab.bible && _tabController.index != 0) {
      _tabController.index = 0;
    } else if (searchState.activeTab == SearchTab.sermon && _tabController.index != 1) {
      _tabController.index = 1;
    } else if (searchState.activeTab == SearchTab.all && _tabController.index != 2) {
      _tabController.index = 2;
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.home),
          onPressed: () => context.go('/'),
        ),
        title: const Text('Bride Message Search'),
        actions: const [
          Icon(Icons.cloud_outlined),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search Bible & Sermons',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              onChanged: (val) {
                ref.read(searchProvider.notifier).updateQuery(val);
              },
            ),
          ),
          if (history.isNotEmpty && searchState.query.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  children: history
                      .map(
                        (q) => ActionChip(
                          label: Text(q),
                          onPressed: () {
                            _searchController.text = q;
                            ref.read(searchProvider.notifier).updateQuery(q);
                          },
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          _buildSearchFilters(context, ref, searchState),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Found ${searchState.bibleResults.length} Bible verses and ${searchState.sermonResults.length} sermon occurrences',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Bible'),
              Tab(text: 'Sermons'),
              Tab(text: 'All'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildBibleResults(context, searchState),
                _buildSermonResults(context, searchState),
                _buildCombinedResults(context, searchState),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchFilters(BuildContext context, WidgetRef ref, SearchState state) {
    final notifier = ref.read(searchProvider.notifier);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              PillToggleChip(
                label: 'Smart',
                selected: state.searchType == SearchType.all,
                onTap: () => notifier.updateSearchType(SearchType.all),
              ),
              const SizedBox(width: 8),
              PillToggleChip(
                label: 'Exact Phrase',
                selected: state.searchType == SearchType.exact,
                onTap: () => notifier.updateSearchType(SearchType.exact),
              ),
              const SizedBox(width: 8),
              PillToggleChip(
                label: 'Any Word',
                selected: state.searchType == SearchType.any,
                onTap: () => notifier.updateSearchType(SearchType.any),
              ),
              const SizedBox(width: 8),
              PillToggleChip(
                label: 'Prefix',
                selected: state.searchType == SearchType.prefix,
                onTap: () => notifier.updateSearchType(SearchType.prefix),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: [
              PillToggleChip(
                label: 'Exact Match',
                selected: true,
                onTap: () {},
              ),
              const SizedBox(width: 8),
              PillToggleChip(
                label: 'Accurate',
                selected: false,
                onTap: () {},
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              PillToggleChip(
                label: 'EN',
                icon: Icons.book_outlined,
                selected: state.languageCode == 'en',
                onTap: () {
                  if (state.languageCode != 'en') {
                    notifier.toggleLanguage();
                  }
                },
              ),
              const SizedBox(width: 8),
              PillToggleChip(
                label: 'TA',
                icon: Icons.book_outlined,
                selected: state.languageCode == 'ta',
                onTap: () {
                  if (state.languageCode != 'ta') {
                    notifier.toggleLanguage();
                  }
                },
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.help_outline),
                onPressed: () {
                  // Placeholder for search help navigation
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBibleResults(BuildContext context, SearchState state) {
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
          children: const [
            // Static UI for now; wiring to filters can be added when OT/NT scopes are implemented
            PillToggleChip(
              label: 'Both',
              selected: true,
            ),
            SizedBox(width: 8),
            PillToggleChip(
              label: 'Old Test',
              selected: false,
            ),
            SizedBox(width: 8),
            PillToggleChip(
              label: 'New Test',
              selected: false,
            ),
          ],
        ),
      ),
    );

    children.add(
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(
          children: const [
            PillToggleChip(
              label: 'Book order',
              selected: true,
            ),
            SizedBox(width: 8),
            PillToggleChip(
              label: 'Relevance',
              selected: false,
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
              ref.read(readerProvider.notifier).openTab(
                    ReaderTab(
                      type: ReaderContentType.bible,
                      title: '${r.book} ${r.chapter}',
                      book: r.book,
                      chapter: r.chapter,
                    ),
                  );
              context.go('/reader');
            },
          ),
        );
      }
    });

    return ListView(
      children: children,
    );
  }

  Widget _buildSermonResults(BuildContext context, SearchState state) {
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
      return Center(child: Text('No sermons found for \"${state.query}\"'));
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
          onTap: () {
            ref.read(readerProvider.notifier).openTab(
                  ReaderTab(
                    type: ReaderContentType.sermon,
                    title: r.title,
                    sermonId: r.sermonId,
                  ),
                );
            context.go('/reader');
          },
        );
      },
    );
  }

  Widget _buildCombinedResults(BuildContext context, SearchState state) {
    // Simple implementation: show Bible results followed by Sermon results.
    return Column(
      children: [
        Expanded(child: _buildBibleResults(context, state)),
        const Divider(height: 1),
        SizedBox(
          height: 200,
          child: _buildSermonResults(context, state),
        ),
      ],
    );
  }

}
