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
import '../../core/database/models/sermon_models.dart';

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
  });

  final bool autoResume;
  final String? initialQuery;
  final String? titlePrefix;
  final String? customTitle;
  final bool hideFilters;
  final List<String>? allowedIds;

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
            );
      });
    } else if (titlePrefix != null && titlePrefix.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref
            .read(sermonListProvider.notifier)
            .filterSermons(year: null, query: '', titlePrefix: titlePrefix);
      });
    } else if (initialQuery != null && initialQuery.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _searchController.text = initialQuery;
        ref
            .read(sermonListProvider.notifier)
            .filterSermons(year: null, query: initialQuery);
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
    final yearsAsync = ref.watch(availableYearsProvider);
    final flowState = ref.watch(sermonFlowProvider);
    final lang = ref.watch(selectedSermonLangProvider);
    final sermonDbExists = ref.watch(sermonDatabaseExistsProvider(lang));
    final totalCountAsync = ref.watch(sermonStoredCountByLangProvider(lang));
    final theme = Theme.of(context);
    final hasAllowedIds =
        widget.allowedIds != null && widget.allowedIds!.isNotEmpty;

    final countLabel = hasAllowedIds
        ? (state.searchQuery.trim().isEmpty
              ? '${state.sermons.length} sermons'
              : '${state.sermons.length} shown · ${widget.allowedIds!.length} total sermons')
        : totalCountAsync.when(
            data: (total) {
              if (state.selectedYear == null &&
                  state.searchQuery.trim().isEmpty) {
                return '$total sermons';
              }
              return '${state.sermons.length} shown · $total total sermons';
            },
            loading: () => '${state.sermons.length} sermons',
            error: (err, st) => '${state.sermons.length} sermons',
          );

    if (widget.autoResume && !_autoResumeChecked && flowState.isInitialized) {
      _autoResumeChecked = true;
      if (flowState.hasSermon) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          context.push('/sermon-reader');
        });
      }
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(widget.customTitle ?? 'Sermon Library'),
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
      body:
          sermonDbExists.maybeWhen(
            data: (exists) => !exists,
            orElse: () => false,
          )
          ? Center(
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
            )
          : Column(
              children: [
                if (state.loadError != null)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Card(
                      color: theme.colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
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
                            if (_isMissingSermonDbError(state.loadError)) ...[
                              const SizedBox(height: 10),
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
                                      titlePrefix: widget.titlePrefix,
                                    );
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onChanged: (val) {
                      setState(() {});
                      _debounce?.cancel();
                      _debounce = Timer(const Duration(milliseconds: 400), () {
                        ref
                            .read(sermonListProvider.notifier)
                            .filterSermons(
                              year: state.selectedYear,
                              query: val,
                              titlePrefix: widget.titlePrefix,
                            );
                      });
                    },
                  ),
                ),
                if (!widget.hideFilters) ...[
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
                                    titlePrefix: widget.titlePrefix,
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
                                  ref
                                      .read(sermonListProvider.notifier)
                                      .filterSermons(
                                        year: y,
                                        query: _searchController.text,
                                        titlePrefix: widget.titlePrefix,
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
                        onPressed: () => context.push(
                          widget.hideFilters ? '/search?tab=cod' : '/search',
                        ),
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
                          itemCount:
                              state.sermons.length + (state.isLoading ? 1 : 0),
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
                              metaRightBadge: sermon.year?.toString(),
                              subtitle: sermon.totalParagraphs != null
                                  ? '${sermon.totalParagraphs} ¶'
                                  : null,
                              highlightQuery: state.searchQuery,
                              onTap: () => _openSermon(sermon),
                              onDoubleTap: _isDesktopPlatform
                                  ? () => _replaceActiveSermon(sermon)
                                  : null,
                              onLongPress: _isDesktopPlatform
                                  ? null
                                  : () => _showSermonActionsSheet(sermon),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
