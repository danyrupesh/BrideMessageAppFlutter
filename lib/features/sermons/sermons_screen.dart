import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'providers/sermon_provider.dart';
import 'providers/sermon_flow_provider.dart';
import '../reader/models/reader_tab.dart';
import '../common/widgets/cards.dart';
import '../onboarding/onboarding_screen.dart';
import 'widgets/sermon_filters_sheet.dart';
import '../help/widgets/help_button.dart';
import '../../core/database/models/sermon_models.dart';
import '../../core/database/models/sermon_search_result.dart';
import '../search/providers/search_provider.dart';

enum _SermonAction { open, openInNewTab, setBmMain }

class SermonListScreen extends ConsumerStatefulWidget {
  const SermonListScreen({
    super.key,
    this.autoResume = false,
    this.initialQuery,
    this.titlePrefix,
    this.customTitle,
    this.hideFilters = false,
    this.allowedIds,
    this.categoryFilter,
  });

  final bool autoResume;
  final String? initialQuery;
  final String? titlePrefix;
  final String? customTitle;
  final bool hideFilters;
  final List<String>? allowedIds;
  final String? categoryFilter;

  @override
  ConsumerState<SermonListScreen> createState() => _SermonListScreenState();
}

class _SermonListScreenState extends ConsumerState<SermonListScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  bool _autoResumeChecked = false;

  bool get _isDesktopPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
        return true;
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  bool _isMissingSermonDbError(String? error) {
    if (error == null) return false;
    final lower = error.toLowerCase();
    return lower.contains('sermon database is not installed') ||
        (lower.contains('database file not found') &&
            lower.contains('sermons_') &&
            lower.contains('.db'));
  }

  ReaderTab _tabForSermon(SermonEntity sermon) {
    return ReaderTab(
      type: ReaderContentType.sermon,
      title: sermon.title,
      sermonId: sermon.id,
    );
  }

  void _openSermon(SermonEntity sermon) {
    ref.read(sermonFlowProvider.notifier).openSermon(_tabForSermon(sermon));
    context.push('/sermon-reader');
  }

  void _replaceActiveSermon(SermonEntity sermon) {
    final notifier = ref.read(sermonFlowProvider.notifier);
    final flowState = ref.read(sermonFlowProvider);
    final replaceIndex = flowState.tabs.indexWhere(
      (tab) => tab.type == ReaderContentType.sermon,
    );
    if (replaceIndex == -1) {
      notifier.openSermon(_tabForSermon(sermon));
    } else {
      notifier.replaceSermonTab(replaceIndex, _tabForSermon(sermon));
    }
    context.push('/sermon-reader');
  }

  void _openSermonInNewTab(SermonEntity sermon) {
    final notifier = ref.read(sermonFlowProvider.notifier);
    final flowState = ref.read(sermonFlowProvider);
    if (flowState.hasSermon) {
      notifier.addSermonTab(_tabForSermon(sermon));
    } else {
      notifier.openSermon(_tabForSermon(sermon));
    }
    context.push('/sermon-reader');
  }

  void _setBmMainSermon(SermonEntity sermon) {
    final notifier = ref.read(sermonFlowProvider.notifier);
    final flowState = ref.read(sermonFlowProvider);
    final replaceIndex = flowState.tabs.indexWhere(
      (tab) => tab.type == ReaderContentType.sermon,
    );
    if (replaceIndex == -1) {
      notifier.openSermon(_tabForSermon(sermon));
    } else {
      notifier.replaceSermonTab(replaceIndex, _tabForSermon(sermon));
    }
    notifier.setBmMode(true);
    context.push('/sermon-reader');
  }

  Future<void> _showSermonActionsSheet(SermonEntity sermon) async {
    final action = await showModalBottomSheet<_SermonAction>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: const Text('Open'),
                onTap: () => Navigator.pop(ctx, _SermonAction.open),
              ),
              ListTile(
                leading: const Icon(Icons.tab),
                title: const Text('Open in new tab'),
                onTap: () => Navigator.pop(ctx, _SermonAction.openInNewTab),
              ),
              ListTile(
                leading: const Icon(Icons.auto_awesome_motion),
                title: const Text('Set as BM main sermon'),
                onTap: () => Navigator.pop(ctx, _SermonAction.setBmMain),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    switch (action) {
      case _SermonAction.open:
        _openSermon(sermon);
        break;
      case _SermonAction.openInNewTab:
        _openSermonInNewTab(sermon);
        break;
      case _SermonAction.setBmMain:
        _setBmMainSermon(sermon);
        break;
      case null:
        return;
    }
  }

  void _showSermonInteractionInfo() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sermon List Interactions'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Single click/tap: open sermon'),
            SizedBox(height: 6),
            Text('Double-click (desktop): replace current sermon in reader'),
            SizedBox(height: 6),
            Text('Long-press (mobile): open sermon actions'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

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

    // Apply an initial search filter when provided (e.g. COD-specific screens).
    final initialQuery = widget.initialQuery?.trim();
    final titlePrefix = widget.titlePrefix?.trim();
    final categoryFilter = widget.categoryFilter?.trim();
    final hasCategoryFilter =
        categoryFilter != null && categoryFilter.isNotEmpty;
    if (widget.allowedIds != null && widget.allowedIds!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref
            .read(sermonListProvider.notifier)
            .filterSermons(
              year: null,
              query: '',
              titlePrefix: null,
              allowedIds: widget.allowedIds,
              categoryFilter: widget.categoryFilter,
            );
      });
    } else if (hasCategoryFilter) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref
            .read(sermonListProvider.notifier)
            .filterSermons(
              year: null,
              query: '',
              titlePrefix: null,
              categoryFilter: categoryFilter,
            );
      });
    } else if (titlePrefix != null && titlePrefix.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref
            .read(sermonListProvider.notifier)
            .filterSermons(
              year: null,
              query: '',
              titlePrefix: titlePrefix,
              categoryFilter: widget.categoryFilter,
            );
      });
    } else if (initialQuery != null && initialQuery.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _searchController.text = initialQuery;
        ref
            .read(sermonListProvider.notifier)
            .filterSermons(
              year: null,
              query: initialQuery,
              categoryFilter: widget.categoryFilter,
            );
      });
    } else if (!widget.hideFilters) {
      // Generic Sermon Library entry: ensure we start from the default
      // unfiltered list (1947–1965) instead of reusing any previous COD
      // or search filters that may be cached in the provider.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _searchController.clear();
        ref.read(sermonListProvider.notifier).resetToInitial();
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    if (widget.hideFilters) {
      // Leaving COD view: restore default sermon list state.
      ref.read(sermonListProvider.notifier).resetToInitial();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sermonListProvider);
    final searchType = ref.watch(searchProvider).searchType;
    final yearsAsync = ref.watch(availableYearsProvider);
    final flowState = ref.watch(sermonFlowProvider);
    final lang = ref.watch(selectedSermonLangProvider);
    final sermonDbExists = ref.watch(sermonDatabaseExistsProvider(lang));
    final totalCountAsync = ref.watch(sermonStoredCountByLangProvider(lang));
    final categoryCountAsync = widget.categoryFilter == null
        ? null
        : ref.watch(
            sermonStoredCountByLangAndCategoryProvider((
              lang: lang,
              category: widget.categoryFilter!,
            )),
          );
    final theme = Theme.of(context);
    final hasAllowedIds =
        widget.allowedIds != null && widget.allowedIds!.isNotEmpty;

    final isContentSearch = state.searchType == SearchType.all;
    final resultsCount = isContentSearch ? state.searchResults.length : state.sermons.length;

    final countLabel = hasAllowedIds
        ? (state.searchQuery.trim().isEmpty
            ? '$resultsCount sermons'
            : '$resultsCount matches')
        : (state.searchQuery.trim().isEmpty
            ? '$resultsCount sermons'
            : '$resultsCount results');

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            Flexible(
              child: Text(
                widget.customTitle ?? 'Sermon Library',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            if (!widget.hideFilters)
              SegmentedButton<SearchType>(
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                segments: const [
                  ButtonSegment<SearchType>(
                    value: SearchType.prefix,
                    label: Text('Title', style: TextStyle(fontSize: 13)),
                    icon: Icon(Icons.title, size: 18),
                  ),
                  ButtonSegment<SearchType>(
                    value: SearchType.all,
                    label: Text('Content', style: TextStyle(fontSize: 13)),
                    icon: Icon(Icons.article_outlined, size: 18),
                  ),
                ],
                selected: {state.searchType},
                onSelectionChanged: (newSelection) {
                  ref.read(sermonListProvider.notifier).setSearchType(newSelection.first);
                },
              ),
            const Spacer(),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'How to open sermons',
            onPressed: _showSermonInteractionInfo,
          ),
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () => context.go('/'),
          ),
          const HelpButton(topicId: 'sermons'),
          if (!widget.hideFilters)
            IconButton(
              icon: const Icon(Icons.filter_list),
              onPressed: () => SermonFiltersSheet.show(context, ref),
            ),
          if (widget.hideFilters)
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () => context.push('/settings'),
            ),
        ],
      ),
      floatingActionButton: widget.hideFilters
          ? null
          : FloatingActionButton.extended(
              onPressed: () => SermonFiltersSheet.show(context, ref),
              icon: const Icon(Icons.filter_list),
              label: const Text('Filter'),
            ),
      body: Column(
        children: [

          // Search Input
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: state.searchType == SearchType.all
                    ? 'Search inside sermon text...'
                    : 'Search title, year, ID, location...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _debounce?.cancel();
                          ref.read(sermonListProvider.notifier).filterSermons(
                                year: state.selectedYear,
                                query: '',
                                titlePrefix: widget.titlePrefix,
                                searchType: state.searchType,
                              );
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onChanged: (val) {
                setState(() {});
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 500), () {
                  ref.read(sermonListProvider.notifier).filterSermons(
                        year: state.selectedYear,
                        query: val,
                        titlePrefix: widget.titlePrefix,
                        searchType: state.searchType,
                      );
                });
              },
            ),
          ),

          // Year Filters
          if (!widget.hideFilters && state.searchType != SearchType.all) ...[
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
                        ref.read(sermonListProvider.notifier).filterSermons(
                              year: null,
                              query: _searchController.text,
                              titlePrefix: widget.titlePrefix,
                              searchType: state.searchType,
                            );
                      },
                    ),
                    const SizedBox(width: 8),
                    ...years.map(
                      (y) => Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: FilterChip(
                          label: Text(y.toString()),
                          selected: state.selectedYear == y,
                          onSelected: (val) {
                            ref.read(sermonListProvider.notifier).filterSermons(
                                  year: y,
                                  query: _searchController.text,
                                  titlePrefix: widget.titlePrefix,
                                  searchType: state.searchType,
                                );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              loading: () => const SizedBox.shrink(),
              error: (err, _) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 8),
          ],

          // Results Meta (Count and Advanced Search Link)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  countLabel,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    final query = _searchController.text.trim();
                    final queryParam = query.isEmpty ? '' : '&q=${Uri.encodeComponent(query)}';
                    context.push(
                      widget.hideFilters
                        ? '/search?tab=cod$queryParam'
                        : '/search?tab=sermons$queryParam',
                    );
                  },
                  child: const Text('Advanced Search'),
                ),
              ],
            ),
          ),

          // Main Listing Area
          Expanded(
            child: sermonDbExists.maybeWhen(
              data: (exists) => !exists,
              orElse: () => false,
            )
                ? _buildDbMissingView(theme)
                : _buildSermonList(state),
          ),
        ],
      ),
    );
  }

  Widget _buildSermonList(SermonListState state) {
    if (state.sermons.isEmpty && state.searchResults.isEmpty && !state.isLoading) {
      return const Center(child: Text("No sermons found."));
    }

    final isContentSearch = state.searchType == SearchType.all;
    final itemCount = isContentSearch ? state.searchResults.length : state.sermons.length;

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: itemCount + (state.isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == itemCount) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (isContentSearch) {
          final res = state.searchResults[index];
          return SermonResultCard(
            id: res.sermonId,
            title: res.title,
            date: res.date,
            metaRightBadge: res.year?.toString(),
            location: res.location,
            highlightQuery: state.searchQuery,
            snippet: _buildSnippetWidget(res.snippet),
            onTap: () => _openSermonFromSearchResult(res),
          );
        } else {
          final sermon = state.sermons[index];
          return SermonResultCard(
            id: sermon.id,
            title: sermon.title,
            date: sermon.date,
            duration: sermon.duration,
            location: sermon.location,
            metaRightBadge: sermon.year?.toString(),
            subtitle: sermon.totalParagraphs != null ? '${sermon.totalParagraphs} ¶' : null,
            highlightQuery: state.searchQuery,
            onTap: () => _openSermon(sermon),
            onDoubleTap: _isDesktopPlatform ? () => _replaceActiveSermon(sermon) : null,
            onLongPress: _isDesktopPlatform ? null : () => _showSermonActionsSheet(sermon),
          );
        }
      },
    );
  }

  Widget _buildSnippetWidget(String snippetHtml) {
    final theme = Theme.of(context);
    final parts = snippetHtml.split(RegExp(r'<b>|</b>'));
    final spans = <TextSpan>[];
    for (var i = 0; i < parts.length; i++) {
      final isBold = i % 2 == 1;
      spans.add(TextSpan(
        text: parts[i],
        style: isBold
            ? TextStyle(
                fontWeight: FontWeight.bold,
                backgroundColor: theme.colorScheme.tertiaryContainer.withOpacity(0.4),
                color: theme.colorScheme.onTertiaryContainer,
              )
            : null,
      ));
    }
    return RichText(
      text: TextSpan(
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.4,
        ),
        children: spans,
      ),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }

  void _openSermonFromSearchResult(SermonSearchResult res) {
    final tab = ReaderTab(
      type: ReaderContentType.sermon,
      title: res.title,
      sermonId: res.sermonId,
      initialFocusParagraph: res.paragraphNumber,
    );
    ref.read(sermonFlowProvider.notifier).openSermon(tab);
    context.push('/sermon-reader');
  }

  Widget _buildDbMissingView(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 44),
            const SizedBox(height: 10),
            Text(
              'Sermon database is not installed',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Import Tamil/English sermons database to continue.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const OnboardingScreen(
                      showImportDirectly: true,
                    ),
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
}
