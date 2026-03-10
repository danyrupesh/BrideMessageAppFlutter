import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'providers/sermon_provider.dart';
import 'providers/sermon_flow_provider.dart';
import '../reader/models/reader_tab.dart';
import '../common/widgets/cards.dart';
import 'widgets/sermon_filters_sheet.dart';

class SermonListScreen extends ConsumerStatefulWidget {
  const SermonListScreen({super.key});

  @override
  ConsumerState<SermonListScreen> createState() => _SermonListScreenState();
}

class _SermonListScreenState extends ConsumerState<SermonListScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        ref.read(sermonListProvider.notifier).loadMore();
      }
    });
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sermonListProvider);
    final yearsAsync = ref.watch(availableYearsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Sermon Library'),
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () => context.go('/'),
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () => SermonFiltersSheet.show(context, ref),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => SermonFiltersSheet.show(context, ref),
        icon: const Icon(Icons.filter_list),
        label: const Text('Filter'),
      ),
      body: Column(
        children: [
          if (state.loadError != null)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Card(
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          state.loadError!,
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                            fontSize: 12,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search title, year, ID, location...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _debounce?.cancel();
                          ref
                              .read(sermonListProvider.notifier)
                              .filterSermons(
                                year: state.selectedYear,
                                query: '',
                              );
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (val) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 400), () {
                  ref
                      .read(sermonListProvider.notifier)
                      .filterSermons(year: state.selectedYear, query: val);
                });
              },
            ),
          ),

          yearsAsync.when(
            data: (years) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  FilterChip(
                    label: const Text('All Years'),
                    selected: state.selectedYear == null,
                    onSelected: (val) {
                      ref
                          .read(sermonListProvider.notifier)
                          .filterSermons(
                            year: null,
                            query: _searchController.text,
                          );
                    },
                  ),
                  const SizedBox(width: 8),
                  ...years
                      .map(
                        (y) => Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: FilterChip(
                            label: Text(y.toString()),
                            selected: state.selectedYear == y,
                            onSelected: (val) {
                              ref
                                  .read(sermonListProvider.notifier)
                                  .filterSermons(
                                    year: y,
                                    query: _searchController.text,
                                  );
                            },
                          ),
                        ),
                      )
                      .toList(),
                ],
              ),
            ),
            loading: () => const SizedBox.shrink(),
            error: (err, _) => const SizedBox.shrink(),
          ),

          const SizedBox(height: 8),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${state.sermons.length} sermons',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                TextButton(
                  onPressed: () => context.push('/search'),
                  child: const Text('Advanced Search'),
                ),
              ],
            ),
          ),

          Expanded(
            child: state.sermons.isEmpty && !state.isLoading
                ? const Center(child: Text("No sermons found."))
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: state.sermons.length + (state.isLoading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == state.sermons.length) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }

                      final sermon = state.sermons[index];
                      return SermonResultCard(
                        id: sermon.id,
                        title: sermon.title,
                        date: sermon.date,
                        duration: sermon.duration,
                        location: sermon.location,
                        metaRightBadge:
                            sermon.year != null ? sermon.year.toString() : null,
                        subtitle: sermon.totalParagraphs != null
                            ? '${sermon.totalParagraphs} ¶'
                            : null,
                        onTap: () {
                          ref.read(sermonFlowProvider.notifier).openSermon(
                                ReaderTab(
                                  type: ReaderContentType.sermon,
                                  title: sermon.title,
                                  sermonId: sermon.id,
                                ),
                              );
                          context.push('/sermon-reader');
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
