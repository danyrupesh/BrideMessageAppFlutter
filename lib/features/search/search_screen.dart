import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'providers/search_history_provider.dart';
import 'providers/search_provider.dart';
import '../../core/database/metadata/installed_content_provider.dart';
import '../../core/database/metadata/installed_database_model.dart';
import 'package:path/path.dart' as p;
import '../../core/database/database_manager.dart';
import '../../features/onboarding/services/selective_database_importer.dart';
import 'widgets/search_filters.dart';
import 'widgets/bible_results_tab.dart';
import 'widgets/sermon_results_tab.dart';
import 'widgets/cod_results_tab.dart';
import 'widgets/song_results_tab.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({
    super.key,
    this.initialTab,
    this.fresh = false,
    this.initialQuery,
  });

  final String? initialTab;
  final bool fresh;
  final String? initialQuery;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _searchController;
  late final ProviderSubscription<String> _querySync;
  late final ProviderSubscription<SearchTab> _tabSync;
  bool _syncingQuery = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _searchController = TextEditingController();
    final initial = _parseInitialTab(widget.initialTab);
    if (initial != null) {
      _tabController.index = _tabIndexFor(initial);
    }
    final existingQuery = ref.read(searchProvider).query;
    if (!widget.fresh && existingQuery.isNotEmpty) {
      _searchController.text = existingQuery;
    }

    _querySync = ref.listenManual<String>(
      searchProvider.select((state) => state.query),
      (_, next) {
        if (!mounted || _searchController.text == next) return;
        _syncingQuery = true;
        _searchController.value = _searchController.value.copyWith(
          text: next,
          selection: TextSelection.fromPosition(
            TextPosition(offset: next.length),
          ),
          composing: TextRange.empty,
        );
        _syncingQuery = false;
      },
    );

    _tabSync = ref.listenManual<SearchTab>(
      searchProvider.select((state) => state.activeTab),
      (_, next) {
        if (!mounted) return;
        final desired = _tabIndexFor(next);
        if (_tabController.index == desired) return;
        _tabController.animateTo(desired);
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final notifier = ref.read(searchProvider.notifier);
      // Warm FTS indexes on first search screen open (mirrors Android's SearchViewModel.warmUp).
      _warmFts();
      if (widget.fresh) {
        notifier.reset(activeTab: initial ?? SearchTab.bible);
        _syncingQuery = true;
        _searchController.clear();
        _syncingQuery = false;
      } else if (initial != null) {
        _tabController.index = _tabIndexFor(initial);
        notifier.updateTab(initial);
      }

      final incomingQuery = widget.initialQuery?.trim();
      if (incomingQuery != null && incomingQuery.isNotEmpty) {
        _syncingQuery = true;
        _searchController.value = _searchController.value.copyWith(
          text: incomingQuery,
          selection: TextSelection.fromPosition(
            TextPosition(offset: incomingQuery.length),
          ),
          composing: TextRange.empty,
        );
        _syncingQuery = false;
        notifier.updateQuery(incomingQuery);
      }
    });
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        final notifier = ref.read(searchProvider.notifier);
        notifier.updateTab(_tabForIndex(_tabController.index));
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
    _querySync.close();
    _tabSync.close();
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchProvider);
    final history = ref.watch(searchHistoryProvider);
    final bibleInstalledAsync = ref.watch(
      defaultInstalledDbProvider((DbType.bible, searchState.languageCode)),
    );
    final sermonInstalledAsync = ref.watch(
      defaultInstalledDbProvider((DbType.sermon, searchState.languageCode)),
    );

    final bibleFallback =
        bibleInstalledAsync.hasError ||
        bibleInstalledAsync.maybeWhen(
          data: (v) => v == null,
          orElse: () => false,
        );
    final sermonFallback =
        sermonInstalledAsync.hasError ||
        sermonInstalledAsync.maybeWhen(
          data: (v) => v == null,
          orElse: () => false,
        );
    final showFallbackNotice =
        (searchState.activeTab == SearchTab.bible && bibleFallback) ||
        (searchState.activeTab == SearchTab.sermon && sermonFallback) ||
        (searchState.activeTab == SearchTab.all &&
            (bibleFallback || sermonFallback));

    final fallbackParts = <String>[];
    if (bibleFallback) fallbackParts.add('Bible');
    if (sermonFallback) fallbackParts.add('Sermon');
    final fallbackLabel = fallbackParts.join(' + ');

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Bride Message Search'),
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () => context.go('/'),
          ),
          IconButton(
            icon: const Icon(Icons.cloud_outlined),
            tooltip: 'Import databases',
            onPressed: () => context.push('/onboarding'),
          ),
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
                hintText: 'Search Bible, Sermons, COD, Songs',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: searchState.query.trim().isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'Clear',
                        onPressed: () {
                          _syncingQuery = true;
                          _searchController.clear();
                          _syncingQuery = false;
                          ref.read(searchProvider.notifier).updateQuery('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              onChanged: (val) {
                if (_syncingQuery) return;
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
          const SearchFilters(),
          if (showFallbackNotice)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.tertiaryContainer.withAlpha(100),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.tertiary.withAlpha(140),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.onTertiaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$fallbackLabel metadata missing. Using fallback database mapping.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 4.0,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _resultsLabel(searchState),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Bible'),
              Tab(text: 'Sermons'),
              Tab(text: 'COD'),
              Tab(text: 'Songs'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                BibleResultsTab(),
                SermonResultsTab(),
                CodResultsTab(),
                SongResultsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  SearchTab? _parseInitialTab(String? raw) {
    if (raw == null) return null;
    switch (raw.toLowerCase()) {
      case 'bible':
        return SearchTab.bible;
      case 'sermon':
      case 'sermons':
        return SearchTab.sermon;
      case 'cod':
        return SearchTab.cod;
      case 'songs':
      case 'song':
        return SearchTab.songs;
      default:
        return null;
    }
  }

  int _tabIndexFor(SearchTab tab) {
    switch (tab) {
      case SearchTab.bible:
        return 0;
      case SearchTab.sermon:
        return 1;
      case SearchTab.cod:
        return 2;
      case SearchTab.songs:
        return 3;
      case SearchTab.all:
        return 0;
    }
  }

  SearchTab _tabForIndex(int index) {
    switch (index) {
      case 0:
        return SearchTab.bible;
      case 1:
        return SearchTab.sermon;
      case 2:
        return SearchTab.cod;
      case 3:
        return SearchTab.songs;
      default:
        return SearchTab.bible;
    }
  }

  String _resultsLabel(SearchState state) {
    String withLoaded(int loaded, int total, String label) {
      if (total <= 0) return 'Found 0 $label';
      if (loaded >= total) return 'Found $total $label';
      return 'Found $total $label (showing $loaded)';
    }

    switch (state.activeTab) {
      case SearchTab.bible:
        return withLoaded(
          state.bibleResults.length,
          state.bibleTotalCount,
          'Bible verses',
        );
      case SearchTab.sermon:
        return withLoaded(
          state.sermonResults.length,
          state.sermonTotalCount,
          'sermon occurrences',
        );
      case SearchTab.cod:
        return withLoaded(
          state.codResults.length,
          state.codTotalCount,
          'COD occurrences',
        );
      case SearchTab.songs:
        return withLoaded(
          state.songResults.length,
          state.songTotalCount,
          'songs',
        );
      case SearchTab.all:
        return 'Found ${state.bibleResults.length} Bible verses and ${state.sermonResults.length} sermon occurrences';
    }
  }
}
