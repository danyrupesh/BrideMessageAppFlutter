import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'providers/search_history_provider.dart';
import 'providers/search_provider.dart';
import '../../core/database/metadata/installed_content_provider.dart';
import 'package:path/path.dart' as p;
import '../../core/database/database_manager.dart';
import '../../features/onboarding/services/selective_database_importer.dart';
import 'widgets/search_filters.dart';
import 'widgets/bible_results_tab.dart';
import 'widgets/sermon_results_tab.dart';

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
    _tabController = TabController(length: 2, vsync: this);
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
    } else if (searchState.activeTab == SearchTab.sermon &&
        _tabController.index != 1) {
      _tabController.index = 1;
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.home),
          onPressed: () => context.go('/'),
        ),
        title: const Text('Bride Message Search'),
        actions: [
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
          const SearchFilters(),
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
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                BibleResultsTab(),
                SermonResultsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

}
