import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/sermon_provider.dart';
import '../../../core/database/models/sermon_models.dart';

/// Modal bottom sheet that shows a searchable list of all sermons.
/// Mirrors the Android "Quick Navigation" drawer (PFA2 screenshot).
class SermonQuickNavSheet extends ConsumerStatefulWidget {
  final void Function(SermonEntity sermon) onSelected;
  final String? lang;

  const SermonQuickNavSheet({super.key, required this.onSelected, this.lang});

  @override
  ConsumerState<SermonQuickNavSheet> createState() =>
      _SermonQuickNavSheetState();
}

class _SermonQuickNavSheetState extends ConsumerState<SermonQuickNavSheet> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _listScrollController = ScrollController();
  String _query = '';
  Timer? _debounce;
  List<SermonEntity>? _searchResults;
  bool _searchLoading = false;
  List<SermonEntity> _forcedLangSermons = const [];
  bool _forcedLangLoading = false;
  bool _forcedLangHasMore = true;
  int _forcedLangOffset = 0;
  String? _forcedLangError;

  bool get _useForcedLang => widget.lang != null;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _listScrollController.addListener(() {
      if (_query.isNotEmpty || _searchLoading) return;
      if (!_listScrollController.hasClients) return;
      if (_listScrollController.position.pixels >=
          _listScrollController.position.maxScrollExtent - 200) {
        if (_useForcedLang) {
          _loadForcedLangMore();
        } else {
          ref.read(sermonListProvider.notifier).loadMore();
        }
      }
    });
    if (_useForcedLang) {
      _loadForcedLangInitial();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _listScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadForcedLangInitial() async {
    if (!_useForcedLang) return;
    setState(() {
      _forcedLangLoading = true;
      _forcedLangError = null;
      _forcedLangOffset = 0;
      _forcedLangHasMore = true;
      _forcedLangSermons = const [];
    });
    try {
      final repo = await ref.read(sermonRepositoryByLangProvider(widget.lang!).future);
      final results = await repo.getSermonsPage(limit: 50, offset: 0);
      if (!mounted) return;
      setState(() {
        _forcedLangSermons = results;
        _forcedLangOffset = results.length;
        _forcedLangHasMore = results.length == 50;
        _forcedLangLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _forcedLangError = e.toString();
        _forcedLangLoading = false;
      });
    }
  }

  Future<void> _loadForcedLangMore() async {
    if (!_useForcedLang || _forcedLangLoading || !_forcedLangHasMore) return;
    setState(() => _forcedLangLoading = true);
    try {
      final repo = await ref.read(sermonRepositoryByLangProvider(widget.lang!).future);
      final results = await repo.getSermonsPage(limit: 50, offset: _forcedLangOffset);
      if (!mounted) return;
      setState(() {
        _forcedLangSermons = [..._forcedLangSermons, ...results];
        _forcedLangOffset += results.length;
        _forcedLangHasMore = results.length == 50;
        _forcedLangLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _forcedLangLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final listState = _useForcedLang ? null : ref.watch(sermonListProvider);
    final defaultList = _useForcedLang ? _forcedLangSermons : listState!.sermons;
    final effectiveList = _searchResults ?? defaultList;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isWide = screenWidth >= 700;

    Widget content = _buildSheetContent(theme, listState, effectiveList);

    if (isWide) {
      final height = (screenHeight * 0.8).clamp(520.0, 720.0);
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SizedBox(
            height: height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: content,
            ),
          ),
        ),
      );
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: content,
        );
      },
    );
  }

  Widget _buildSheetContent(
    ThemeData theme,
    SermonListState? listState,
    List<SermonEntity> effectiveList,
  ) {
    final isLoading = _useForcedLang ? _forcedLangLoading : listState!.isLoading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Drag handle
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withAlpha(80),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        // Title row
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Quick Navigation',
                style:
                    theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),

        // Search bar
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: TextField(
            controller: _searchController,
            autofocus: false,
            decoration: InputDecoration(
              hintText: 'Search sermons...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _debounce?.cancel();
                        _searchController.clear();
                        setState(() {
                          _query = '';
                          _searchResults = null;
                          _searchLoading = false;
                        });
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onChanged: (val) {
              setState(() => _query = val);
              _debounce?.cancel();
              _debounce = Timer(
                const Duration(milliseconds: 400),
                () async {
                  if (!mounted) return;
                  if (_query.isEmpty) {
                    setState(() {
                      _searchResults = null;
                      _searchLoading = false;
                    });
                    return;
                  }
                  setState(() => _searchLoading = true);
                  try {
                    final repo = _useForcedLang
                        ? await ref.read(
                            sermonRepositoryByLangProvider(widget.lang!).future,
                          )
                        : await ref.read(sermonRepositoryProvider.future);
                    final results = await repo.getSermonsPage(
                      limit: 50,
                      offset: 0,
                      searchQuery: _query,
                      year: listState?.selectedYear,
                    );
                    if (mounted) {
                      setState(() {
                        _searchResults = results;
                        _searchLoading = false;
                      });
                    }
                  } catch (_) {
                    if (mounted) {
                      setState(() {
                        _searchResults = null;
                        _searchLoading = false;
                      });
                    }
                  }
                },
              );
            },
          ),
        ),

        const SizedBox(height: 4),

        // Sermon list
        Expanded(
          child: (isLoading && effectiveList.isEmpty) ||
                  _searchLoading
              ? const Center(child: CircularProgressIndicator())
              : effectiveList.isEmpty
                  ? Center(
                      child: Text(
                        _query.isEmpty
                            ? (_forcedLangError == null
                                  ? 'No sermons available.'
                                  : 'Unable to load sermons.')
                            : 'No results for "$_query".',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _listScrollController,
                      itemCount:
                          effectiveList.length + (isLoading ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == effectiveList.length) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }
                        final sermon = effectiveList[index];
                        return Column(
                          children: [
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 4),
                              title: Text(
                                sermon.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                [
                                  if (sermon.year != null)
                                    sermon.year.toString(),
                                  if (sermon.location != null &&
                                      sermon.location!.isNotEmpty)
                                    sermon.location!,
                                ].join(' • '),
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                              trailing: Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              onTap: () {
                                Navigator.pop(context);
                                widget.onSelected(sermon);
                              },
                            ),
                            Divider(
                              height: 1,
                              indent: 16,
                              endIndent: 16,
                              color: theme.colorScheme.outlineVariant
                                  .withAlpha(80),
                            ),
                          ],
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
