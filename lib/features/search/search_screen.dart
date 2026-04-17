import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../help/widgets/help_button.dart';
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

  // ── Build ──────────────────────────────────────────────────────────────

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
          const HelpButton(topicId: 'search'),
          IconButton(
            icon: const Icon(Icons.cloud_outlined),
            tooltip: 'Import databases',
            onPressed: () => context.push('/onboarding'),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Row 1: Search bar + language toggle ───────────────────────
          _buildSearchRow(searchState),

          // ── Row 2: History chips (only when idle) ────────────────────
          if (history.isNotEmpty && searchState.query.isEmpty)
            _buildHistoryChips(history),

          // ── Row 3: Tabs (raised immediately below search) ────────────
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Bible'),
              Tab(text: 'Sermons'),
              Tab(text: 'COD'),
              Tab(text: 'Songs'),
            ],
          ),

          // ── Row 4: Results count + filter button ─────────────────────
          _buildResultsBar(searchState),

          // ── Row 5: Fallback notice (rare) ─────────────────────────────
          if (showFallbackNotice)
            _buildFallbackNotice(fallbackLabel),

          // ── Row 6: Results (takes all remaining height) ───────────────
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

  // ── Helpers ────────────────────────────────────────────────────────────

  /// Search field with compact padding + language toggle + help icon.
  Widget _buildSearchRow(SearchState searchState) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search Bible, Sermons, COD, Songs',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: searchState.query.trim().isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        tooltip: 'Clear',
                        onPressed: () {
                          _syncingQuery = true;
                          _searchController.clear();
                          _syncingQuery = false;
                          ref
                              .read(searchProvider.notifier)
                              .updateQuery('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                isDense: true,
              ),
              onChanged: (val) {
                if (_syncingQuery) return;
                ref.read(searchProvider.notifier).updateQuery(val);
              },
            ),
          ),
          const SizedBox(width: 6),
          _buildLanguageToggle(searchState),
        ],
      ),
    );
  }

  /// Compact pill toggle for EN / TA, no extra row needed.
  Widget _buildLanguageToggle(SearchState searchState) {
    final notifier = ref.read(searchProvider.notifier);
    final isEn = searchState.languageCode == 'en';
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _langPill('EN', isEn, () {
            if (!isEn) notifier.toggleLanguage();
          }),
          _langPill('TA', !isEn, () {
            if (isEn) notifier.toggleLanguage();
          }),
        ],
      ),
    );
  }

  Widget _langPill(String label, bool selected, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? cs.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? cs.onPrimary : cs.onSurface,
          ),
        ),
      ),
    );
  }

  /// Previous-query chips shown when the field is empty.
  Widget _buildHistoryChips(List<String> history) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: history
              .map(
                (q) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    label: Text(q),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onPressed: () {
                      _searchController.text = q;
                      ref.read(searchProvider.notifier).updateQuery(q);
                    },
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  /// Single compact row: result count + active filter badges + ⚙ button.
  Widget _buildResultsBar(SearchState searchState) {
    final isDirtyMode = searchState.searchType != SearchType.all;
    final isDirtyRank =
        searchState.matchMode != MatchMode.exactMatch &&
        searchState.activeTab != SearchTab.songs;
    final hasActiveFilters = isDirtyMode || isDirtyRank;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 3, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _resultsLabel(searchState),
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Compact active-filter badges
          if (isDirtyMode)
            _filterBadge(_searchTypeLabel(searchState.searchType)),
          if (isDirtyRank) _filterBadge('Accurate'),
          // Filter icon — opens popup dialog
          IconButton(
            icon: hasActiveFilters
                ? Badge(
                    smallSize: 8,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: const Icon(Icons.tune, size: 20),
                  )
                : const Icon(Icons.tune, size: 20),
            tooltip: 'Search filters',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: () => showSearchFiltersSheet(context),
          ),
        ],
      ),
    );
  }

  Widget _filterBadge(String label) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: cs.onSecondaryContainer,
        ),
      ),
    );
  }

  Widget _buildFallbackNotice(String fallbackLabel) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 2, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .tertiaryContainer
            .withAlpha(100),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.tertiary.withAlpha(140),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 15,
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
    );
  }

  // ── Tab & query helpers ────────────────────────────────────────────────

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

  bool _isMissingCodDbError(String? error) {
    if (error == null) return false;
    final lower = error.toLowerCase();
    return lower.contains('cod database is not installed') ||
        (lower.contains('database file not found') &&
            (lower.contains('cod_english.db') ||
                lower.contains('cod_tamil.db')));
  }

  bool _isMissingBibleDbError(String? error) {
    if (error == null) return false;
    final lower = error.toLowerCase();
    return lower.contains('bible database is not installed') ||
        (lower.contains('database file not found') &&
            lower.contains('bible_') &&
            lower.contains('.db'));
  }

  bool _isMissingSermonDbError(String? error) {
    if (error == null) return false;
    final lower = error.toLowerCase();
    return lower.contains('sermon database is not installed') ||
        (lower.contains('database file not found') &&
            lower.contains('sermons_') &&
            lower.contains('.db'));
  }

  String _searchTypeLabel(SearchType type) {
    switch (type) {
      case SearchType.all:
        return 'Smart';
      case SearchType.exact:
        return 'Exact';
      case SearchType.any:
        return 'Any word';
      case SearchType.prefix:
        return 'Prefix';
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
        if (_isMissingBibleDbError(state.error)) {
          return 'Bible database not installed';
        }
        return withLoaded(
          state.bibleResults.length,
          state.bibleTotalCount,
          'Bible verses',
        );
      case SearchTab.sermon:
        if (_isMissingSermonDbError(state.error)) {
          return 'Sermon database not installed';
        }
        return withLoaded(
          state.sermonResults.length,
          state.sermonTotalCount,
          'sermon occurrences',
        );
      case SearchTab.cod:
        if (_isMissingCodDbError(state.error)) {
          return 'COD database not installed';
        }
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
