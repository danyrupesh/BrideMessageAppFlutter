import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart' show SharePlus, ShareParams;
import 'providers/sermon_flow_provider.dart';
import 'providers/sermon_provider.dart';
import 'widgets/sermon_quick_nav_sheet.dart';
import '../reader/models/reader_tab.dart';
import '../reader/providers/reader_provider.dart';
import '../reader/providers/typography_provider.dart';
import '../reader/widgets/quick_navigation_sheet.dart';
import '../reader/widgets/reader_settings_sheet.dart';
import '../../core/database/models/bible_search_result.dart';
import '../../core/database/models/sermon_models.dart';
import '../../core/database/models/sermon_search_result.dart';
import '../search/providers/search_provider.dart' show SearchType;
import '../common/widgets/fts_highlight_text.dart';

class SermonReaderScreen extends ConsumerStatefulWidget {
  const SermonReaderScreen({super.key});

  @override
  ConsumerState<SermonReaderScreen> createState() =>
      _SermonReaderScreenState();
}

class _SermonReaderScreenState extends ConsumerState<SermonReaderScreen> {
  // ── Scroll controller (preserves position across fullscreen toggle) ────────
  final ScrollController _scrollController = ScrollController();

  // ── In-page search ────────────────────────────────────────────────────────
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  List<GlobalKey> _verseKeys = [];
  List<int> _matchVerseIndices = [];
  int _currentMatchIndex = 0;
  int _totalMatches = 0;

  // ── Verse selection (Bible ref tabs) ─────────────────────────────────────
  final Set<int> _selectedVerseNumbers = {};
  final Set<int> _selectedParagraphIndices = {};
  List<BibleSearchResult> _currentVerses = [];

  // ── Search scope / All-sermons FTS ────────────────────────────────────────
  bool _searchAllSermons = false;
  SearchType _sermonSearchType = SearchType.all;
  List<SermonSearchResult> _allSermonResults = [];
  bool _allSermonSearchLoading = false;

  // ── Paragraph cache (for "This Sermon" in-page search) ───────────────────
  List<SermonParagraphEntity> _currentParagraphs = [];

  // ── UI state ──────────────────────────────────────────────────────────────
  bool _fabExpanded = false;
  bool _hideBottomTabs = false;

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ── Sermon navigation ─────────────────────────────────────────────────────

  Future<void> _openAdjacentSermon(int direction) async {
    final flow = ref.read(sermonFlowProvider);
    ReaderTab? sermonTab;
    if (flow.activeTab?.type == ReaderContentType.sermon) {
      sermonTab = flow.activeTab;
    } else {
      for (final tab in flow.tabs) {
        if (tab.type == ReaderContentType.sermon) {
          sermonTab = tab;
          break;
        }
      }
    }
    if (sermonTab?.sermonId == null) return;

    final adjacent = await ref.read(
      adjacentSermonProvider((sermonTab!.sermonId!, direction)).future,
    );
    if (adjacent == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                direction > 0 ? 'No next sermon.' : 'No previous sermon.'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
      return;
    }
    ref.read(sermonFlowProvider.notifier).addSermonTab(
          ReaderTab(
            type: ReaderContentType.sermon,
            title: adjacent.title,
            sermonId: adjacent.id,
          ),
        );
    // Reset scroll to top for the new sermon.
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    setState(() {
      _fabExpanded = false;
      _isSearching = false;
      _searchController.clear();
      _clearMatches();
      _currentVerses = [];
      _selectedParagraphIndices.clear();
    });
  }

  // ── Quick-nav — Bible ──────────────────────────────────────────────────────

  Future<void> _openQuickNav() async {
    setState(() => _fabExpanded = false);
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const QuickNavigationSheet(),
    );
    if (result == null) return;
    final verse = result['verse'] as int?;
    final newTab = ReaderTab(
      type: ReaderContentType.bible,
      title: verse != null
          ? "${result['book']} ${result['chapter']}:$verse"
          : "${result['book']} ${result['chapter']}",
      book: result['book'] as String,
      chapter: result['chapter'] as int,
      verse: verse,
    );
    if (result['newTab'] == true) {
      ref.read(sermonFlowProvider.notifier).addBibleTab(newTab);
    } else {
      final state = ref.read(sermonFlowProvider);
      if (state.activeTabIndex >= 1) {
        ref
            .read(sermonFlowProvider.notifier)
            .replaceBibleTab(state.activeTabIndex, newTab);
      } else {
        ref.read(sermonFlowProvider.notifier).addBibleTab(newTab);
      }
    }
    setState(() {
      _selectedVerseNumbers.clear();
      _selectedParagraphIndices.clear();
      _isSearching = false;
      _searchController.clear();
      _clearMatches();
    });
  }

  // ── Quick-nav — Sermon ─────────────────────────────────────────────────────

  Future<void> _openSermonQuickNav() async {
    setState(() => _fabExpanded = false);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SermonQuickNavSheet(
        onSelected: (sermon) {
          ref.read(sermonFlowProvider.notifier).addSermonTab(
                ReaderTab(
                  type: ReaderContentType.sermon,
                  title: sermon.title,
                  sermonId: sermon.id,
                ),
              );
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(0);
          }
          setState(() {
            _isSearching = false;
            _searchController.clear();
            _clearMatches();
            _currentVerses = [];
            _selectedParagraphIndices.clear();
          });
        },
      ),
    );
  }

  // ── All-Sermons FTS search ────────────────────────────────────────────────

  Future<void> _triggerAllSermonSearch() async {
    final q = _searchController.text.trim();
    if (q.length < 2) {
      setState(() {
        _allSermonResults = [];
        _allSermonSearchLoading = false;
      });
      return;
    }
    setState(() => _allSermonSearchLoading = true);
    try {
      final repo = await ref.read(sermonRepositoryProvider.future);
      final results = await repo.searchSermons(
        query: q,
        limit: 50,
        offset: 0,
        exactMatch: _sermonSearchType == SearchType.exact,
        anyWord: _sermonSearchType == SearchType.any,
      );
      if (mounted) {
        setState(() {
          _allSermonResults = results;
          _allSermonSearchLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _allSermonSearchLoading = false);
    }
  }

  void _openSermonFromResult(SermonSearchResult result) {
    ref.read(sermonFlowProvider.notifier).addSermonTab(
          ReaderTab(
            type: ReaderContentType.sermon,
            title: result.title,
            sermonId: result.sermonId,
          ),
        );
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    setState(() {
      _isSearching = false;
      _searchAllSermons = false;
      _searchController.clear();
      _clearMatches();
      _allSermonResults = [];
      _currentParagraphs = [];
      _selectedParagraphIndices.clear();
    });
  }

  // ── Close other tabs ───────────────────────────────────────────────────────

  void _closeOtherTabs() {
    final tabs = ref.read(sermonFlowProvider).tabs;
    // Close from highest index downward so indices stay stable.
    for (var i = tabs.length - 1; i >= 1; i--) {
      ref.read(sermonFlowProvider.notifier).closeTab(i);
    }
  }

  // ── In-page search helpers ────────────────────────────────────────────────

  void _computeMatches(String query) {
    // Unified match computation for both Bible verses and sermon paragraphs.
    final isSermonTab = ref.read(sermonFlowProvider).activeTabIndex == 0;
    final texts = isSermonTab
        ? _currentParagraphs.map((p) => p.text).toList()
        : _currentVerses.map((v) => v.text).toList();

    if (query.isEmpty || texts.isEmpty) {
      setState(() {
        _matchVerseIndices = [];
        _totalMatches = 0;
        _currentMatchIndex = 0;
      });
      return;
    }
    final pattern = RegExp(query, caseSensitive: false);
    final indices = <int>[];
    for (var i = 0; i < texts.length; i++) {
      final count = pattern.allMatches(texts[i]).length;
      for (var j = 0; j < count; j++) {
        indices.add(i);
      }
    }
    setState(() {
      _matchVerseIndices = indices;
      _totalMatches = indices.length;
      _currentMatchIndex = 0;
    });
    if (indices.isNotEmpty) _scrollToCurrentMatch();
  }

  void _clearMatches() {
    _matchVerseIndices = [];
    _totalMatches = 0;
    _currentMatchIndex = 0;
  }

  void _navigateToMatch(int direction) {
    if (_matchVerseIndices.isEmpty) return;
    setState(() {
      _currentMatchIndex =
          (_currentMatchIndex + direction) % _matchVerseIndices.length;
      if (_currentMatchIndex < 0) {
        _currentMatchIndex = _matchVerseIndices.length - 1;
      }
    });
    _scrollToCurrentMatch();
  }

  void _scrollToCurrentMatch() {
    if (_matchVerseIndices.isEmpty) return;
    final vi = _matchVerseIndices[_currentMatchIndex];
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (vi < _verseKeys.length) {
        final ctx = _verseKeys[vi].currentContext;
        if (ctx != null) {
          await Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            alignment: 0.2,
          );
          return;
        }
      }
      if (!_scrollController.hasClients || _verseKeys.isEmpty) return;
      final frac = vi / _verseKeys.length;
      final target = frac * _scrollController.position.maxScrollExtent;
      await _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || vi >= _verseKeys.length) return;
        final ctx2 = _verseKeys[vi].currentContext;
        if (ctx2 != null) {
          Scrollable.ensureVisible(
            ctx2,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: 0.2,
          );
        }
      });
    });
  }

  // ── Verse selection helpers ───────────────────────────────────────────────

  void _toggleVerseSelection(int verseNumber) {
    setState(() {
      if (_selectedVerseNumbers.contains(verseNumber)) {
        _selectedVerseNumbers.remove(verseNumber);
      } else {
        _selectedVerseNumbers.add(verseNumber);
      }
    });
  }

  void _shareSelectedVerses() {
    if (_selectedVerseNumbers.isEmpty || _currentVerses.isEmpty) return;
    final activeTab = ref.read(sermonFlowProvider).activeTab;
    final sorted = _selectedVerseNumbers.toList()..sort();
    final lines = sorted.map((vNum) {
      final verse = _currentVerses.firstWhere(
        (v) => v.verse == vNum,
        orElse: () => _currentVerses.first,
      );
      return '${activeTab?.book ?? verse.book} ${verse.chapter}:${verse.verse}  ${verse.text}';
    });
    SharePlus.instance.share(ShareParams(text: lines.join('\n\n')));
  }

  void _toggleParagraphSelection(int index) {
    setState(() {
      if (_selectedParagraphIndices.contains(index)) {
        _selectedParagraphIndices.remove(index);
      } else {
        _selectedParagraphIndices.add(index);
      }
    });
  }

  void _copySelectedParagraphs() {
    if (_selectedParagraphIndices.isEmpty || _currentParagraphs.isEmpty) return;
    final sorted = _selectedParagraphIndices.toList()..sort();
    final text = sorted
        .where((i) => i >= 0 && i < _currentParagraphs.length)
        .map((i) => _currentParagraphs[i].text)
        .join('\n\n');
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    setState(() => _selectedParagraphIndices.clear());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Paragraph copied'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  void _shareSelectedParagraphs() {
    if (_selectedParagraphIndices.isEmpty || _currentParagraphs.isEmpty) return;
    final sorted = _selectedParagraphIndices.toList()..sort();
    final text = sorted
        .where((i) => i >= 0 && i < _currentParagraphs.length)
        .map((i) => _currentParagraphs[i].text)
        .join('\n\n');
    if (text.isEmpty) return;
    SharePlus.instance.share(ShareParams(text: text));
    setState(() => _selectedParagraphIndices.clear());
  }

  // ── Highlighted text spans ────────────────────────────────────────────────

  List<TextSpan> _buildHighlightedSpans(
    String text,
    TextStyle baseStyle,
    TextStyle highlightStyle,
    TextStyle currentMatchStyle, {
    int? currentOccurrenceIndex,
  }) {
    // Don't highlight while browsing All-Sermons results — text not visible.
    if (!_isSearching || _searchAllSermons || _searchController.text.isEmpty) {
      return [TextSpan(text: text, style: baseStyle)];
    }
    final query = _searchController.text;
    final matches =
        RegExp(query, caseSensitive: false).allMatches(text).toList();
    if (matches.isEmpty) return [TextSpan(text: text, style: baseStyle)];

    final spans = <TextSpan>[];
    int start = 0;
    int occurrenceCounter = 0;
    for (final match in matches) {
      if (match.start > start) {
        spans.add(TextSpan(
            text: text.substring(start, match.start), style: baseStyle));
      }
      final isCurrent = occurrenceCounter == currentOccurrenceIndex;
      spans.add(TextSpan(
        text: text.substring(match.start, match.end),
        style: isCurrent ? currentMatchStyle : highlightStyle,
      ));
      occurrenceCounter++;
      start = match.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: baseStyle));
    }
    return spans;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final flowState = ref.watch(sermonFlowProvider);
    final typographyState = ref.watch(typographyProvider);
    final activeTab = flowState.activeTab;
    final isFullscreen = typographyState.isFullscreen;

    // Dismiss FAB when tapping elsewhere.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        if (_fabExpanded) setState(() => _fabExpanded = false);
      },
      child: Scaffold(
        appBar: isFullscreen
            ? null
            : (_isSearching
                ? _buildSearchAppBar(context)
                : _buildDefaultAppBar(context, activeTab, flowState)),
        body: activeTab == null
            ? const Center(
                child: Text('No sermon loaded. Return to sermon list.'))
            : _buildBody(activeTab, typographyState, flowState, isFullscreen),
        floatingActionButton:
            (activeTab == null || isFullscreen) ? null : _buildSpeedDial(),
        bottomNavigationBar: (!isFullscreen &&
                !_hideBottomTabs &&
                flowState.tabs.isNotEmpty)
            ? _buildBottomTabBar(context, flowState)
            : null,
      ),
    );
  }

  // ── Body wrapper ─────────────────────────────────────────────────────────

  Widget _buildBody(
    ReaderTab activeTab,
    TypographySettings typography,
    SermonFlowState flowState,
    bool isFullscreen,
  ) {
    // When searching, inject the scope chips row (and type chips for All Sermons)
    // above the content/results.
    if (_isSearching && !isFullscreen) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSearchChipsRow(),
          if (_searchAllSermons) _buildSearchTypeChipsRow(),
          Expanded(
            child: _searchAllSermons
                ? _buildAllSermonResults()
                : _buildTabContent(activeTab, typography, flowState),
          ),
        ],
      );
    }

    final content = _buildTabContent(activeTab, typography, flowState);
    if (isFullscreen) {
      return Stack(
        children: [
          content,
          Positioned(
            top: 12,
            right: 12,
            child: SafeArea(
              child: Material(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () =>
                      ref.read(typographyProvider.notifier).toggleFullscreen(),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.fullscreen_exit,
                        color: Colors.white, size: 22),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    // Show bottom-tabs restore button overlay when tabs are hidden.
    if (_hideBottomTabs) {
      return Stack(
        children: [
          content,
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Center(
              child: SafeArea(
                top: false,
                child: Material(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => setState(() => _hideBottomTabs = false),
                    child: const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.expand_more,
                              color: Colors.white, size: 18),
                          SizedBox(width: 4),
                          Text('Show Tabs',
                              style: TextStyle(
                                  color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return content;
  }

  // ── Speed-dial FAB ────────────────────────────────────────────────────────

  Widget _buildSpeedDial() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_fabExpanded) ...[
          _FabOption(
            label: 'Open Sermon',
            icon: Icons.import_contacts,
            onTap: _openSermonQuickNav,
          ),
          const SizedBox(height: 8),
          _FabOption(
            label: 'Open Bible',
            icon: Icons.menu_book_rounded,
            onTap: _openQuickNav,
          ),
          const SizedBox(height: 12),
        ],
        FloatingActionButton(
          onPressed: () => setState(() => _fabExpanded = !_fabExpanded),
          child: AnimatedRotation(
            turns: _fabExpanded ? 0.125 : 0,
            duration: const Duration(milliseconds: 200),
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }

  // ── App bars ──────────────────────────────────────────────────────────────

  AppBar _buildSearchAppBar(BuildContext context) {
    return AppBar(
      toolbarHeight: 76.0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () {
          setState(() {
            _isSearching = false;
            _searchAllSermons = false;
            _searchController.clear();
            _clearMatches();
            _allSermonResults = [];
          });
        },
      ),
      title: TextField(
        controller: _searchController,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'Search in content...',
          border: InputBorder.none,
        ),
        onChanged: (val) {
          _computeMatches(val);
          if (_searchAllSermons) _triggerAllSermonSearch();
        },
      ),
      actions: [
        if (_searchController.text.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              _searchController.clear();
              _computeMatches('');
              if (_searchAllSermons) _triggerAllSermonSearch();
            },
          ),
        // "This Sermon" mode: show match counter + up/down navigation.
        if (!_searchAllSermons) ...[
          if (_totalMatches > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '${_currentMatchIndex + 1}/$_totalMatches',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_up),
            onPressed:
                _totalMatches == 0 ? null : () => _navigateToMatch(-1),
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed:
                _totalMatches == 0 ? null : () => _navigateToMatch(1),
          ),
        ],
        // "All Sermons" mode: show loading indicator while searching.
        if (_searchAllSermons && _allSermonSearchLoading)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      ],
    );
  }

  // ── Search chips rows ─────────────────────────────────────────────────────

  Widget _buildSearchChipsRow() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(80),
          ),
        ),
      ),
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('This Sermon'),
            selected: !_searchAllSermons,
            onSelected: (_) {
              setState(() {
                _searchAllSermons = false;
                _allSermonResults = [];
              });
              // Re-run in-page search with current query.
              if (_searchController.text.isNotEmpty) {
                _computeMatches(_searchController.text);
              }
            },
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('All Sermons'),
            selected: _searchAllSermons,
            onSelected: (_) {
              setState(() => _searchAllSermons = true);
              _triggerAllSermonSearch();
            },
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.search, size: 22),
            tooltip: 'Global Search',
            onPressed: () => context.push('/search'),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: const Icon(Icons.home, size: 22),
            tooltip: 'Home',
            onPressed: () => context.go('/'),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchTypeChipsRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('Smart'),
            selected: _sermonSearchType == SearchType.all,
            onSelected: (_) {
              setState(() => _sermonSearchType = SearchType.all);
              _triggerAllSermonSearch();
            },
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('Exact Phrase'),
            selected: _sermonSearchType == SearchType.exact,
            onSelected: (_) {
              setState(() => _sermonSearchType = SearchType.exact);
              _triggerAllSermonSearch();
            },
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('Any Word'),
            selected: _sermonSearchType == SearchType.any,
            onSelected: (_) {
              setState(() => _sermonSearchType = SearchType.any);
              _triggerAllSermonSearch();
            },
          ),
        ],
      ),
    );
  }

  AppBar _buildDefaultAppBar(
    BuildContext context,
    ReaderTab? activeTab,
    SermonFlowState flowState,
  ) {
    final theme = Theme.of(context);
    final hasSelection = _selectedVerseNumbers.isNotEmpty;
    final hasParagraphSelection = _selectedParagraphIndices.isNotEmpty;
    final isOnBibleTab = flowState.activeTab?.type == ReaderContentType.bible;

    // Subtitle metadata for the sermon tab.
    Widget titleWidget;
    if (!isOnBibleTab && activeTab?.sermonId != null) {
      final sermonAsync =
          ref.watch(sermonByIdProvider(activeTab!.sermonId!));
      final SermonEntity? sermon =
          sermonAsync.maybeWhen(data: (v) => v, orElse: () => null);
      final subtitle = sermon == null
          ? null
          : [
              sermon.id,
              if (sermon.year != null) sermon.year.toString(),
              if (sermon.duration != null && sermon.duration!.isNotEmpty)
                sermon.duration!,
            ].join(' • ');

      titleWidget = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            activeTab.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          if (subtitle != null)
            Text(
              subtitle,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
        ],
      );
    } else if (isOnBibleTab) {
      titleWidget = InkWell(
        onTap: _openQuickNav,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(activeTab?.title ?? 'Bible Reference'),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      );
    } else {
      titleWidget = Text(activeTab?.title ?? 'Sermon',
          overflow: TextOverflow.ellipsis);
    }

    return AppBar(
      toolbarHeight: isOnBibleTab ? kToolbarHeight : 76.0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.pop(),
      ),
      title: titleWidget,
      actions: [
        if (hasSelection && isOnBibleTab) ...[
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _shareSelectedVerses,
          ),
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () =>
                setState(() => _selectedVerseNumbers.clear()),
          ),
        ] else if (!isOnBibleTab && hasParagraphSelection) ...[
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: _copySelectedParagraphs,
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _shareSelectedParagraphs,
          ),
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () =>
                setState(() => _selectedParagraphIndices.clear()),
          ),
        ] else ...[
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => setState(() => _isSearching = true),
          ),
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () => context.go('/'),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => ReaderSettingsSheet.show(context),
          ),
        ],
      ],
    );
  }

  // ── Tab content ───────────────────────────────────────────────────────────

  Widget _buildTabContent(
    ReaderTab tab,
    TypographySettings typography,
    SermonFlowState flowState,
  ) {
    // Bible reference tab
    if (tab.type == ReaderContentType.bible &&
        tab.book != null &&
        tab.chapter != null) {
      final asyncVerses = ref.watch(chapterVersesProvider(tab));
      return asyncVerses.when(
        data: (verses) {
          if (_currentVerses != verses) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() {
                _currentVerses = verses;
                _verseKeys =
                    List.generate(verses.length, (_) => GlobalKey());
                if (_isSearching && _searchController.text.isNotEmpty) {
                  _computeMatches(_searchController.text);
                } else {
                  _clearMatches();
                }
              });
              if (tab.verse != null) {
                final idx = tab.verse! - 1;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted || idx < 0 || idx >= _verseKeys.length) return;
                  final ctx = _verseKeys[idx].currentContext;
                  if (ctx != null) {
                    Scrollable.ensureVisible(ctx,
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeInOut,
                        alignment: 0.2);
                  }
                });
              }
            });
          }

          if (verses.isEmpty) {
            return const Center(
                child: Text('No verses found in this chapter.'));
          }

          final cs = Theme.of(context).colorScheme;
          final baseStyle =
              Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontSize: typography.fontSize,
                    height: typography.lineHeight,
                    fontFamily: typography.fontFamily,
                  ) ??
                  const TextStyle();
          final highlightStyle = TextStyle(
            backgroundColor: cs.primaryContainer.withAlpha(180),
            color: cs.onPrimaryContainer,
          );
          final currentMatchStyle = TextStyle(
            backgroundColor: Colors.amber.shade400.withAlpha(220),
            color: Colors.black,
            fontWeight: FontWeight.bold,
          );

          return ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(
                horizontal: 16.0, vertical: 8.0),
            itemCount: verses.length,
            itemBuilder: (context, index) {
              final verse = verses[index];
              final isSelected =
                  _selectedVerseNumbers.contains(verse.verse);
              final key = index < _verseKeys.length
                  ? _verseKeys[index]
                  : GlobalKey();

              int? currentOccurrence;
              if (_matchVerseIndices.isNotEmpty &&
                  _matchVerseIndices[_currentMatchIndex] == index) {
                currentOccurrence = _currentMatchIndex -
                    _matchVerseIndices
                        .sublist(0, _currentMatchIndex)
                        .where((vi) => vi == index)
                        .length;
              }

              return GestureDetector(
                key: key,
                onTap: () => _toggleVerseSelection(verse.verse),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? cs.primaryContainer.withAlpha(120)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 4),
                  margin: const EdgeInsets.only(bottom: 4),
                  child: RichText(
                    text: TextSpan(
                      style: baseStyle,
                      children: [
                        TextSpan(
                          text: '${verse.verse} ',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: typography.fontSize * 0.8,
                            color: isSelected
                                ? cs.primary
                                : cs.onSurfaceVariant,
                          ),
                        ),
                        ..._buildHighlightedSpans(
                          verse.text,
                          baseStyle,
                          highlightStyle,
                          currentMatchStyle,
                          currentOccurrenceIndex: currentOccurrence,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
      );
    }

    // Sermon tab (index 0)
    if (tab.type == ReaderContentType.sermon && tab.sermonId != null) {
      final asyncParagraphs =
          ref.watch(sermonParagraphsProvider(tab.sermonId!));
      return asyncParagraphs.when(
        data: (paragraphs) {
          if (paragraphs.isEmpty) {
            return const Center(
                child: Text('No paragraphs found for this sermon.'));
          }

          // Cache paragraphs and rebuild keys / match indices when content changes.
          if (_currentParagraphs != paragraphs) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() {
                _currentParagraphs = paragraphs;
                _verseKeys =
                    List.generate(paragraphs.length, (_) => GlobalKey());
                _selectedParagraphIndices.clear();
                if (_isSearching &&
                    !_searchAllSermons &&
                    _searchController.text.isNotEmpty) {
                  _computeMatches(_searchController.text);
                } else {
                  _clearMatches();
                }
              });
            });
          }

          final cs = Theme.of(context).colorScheme;
          final baseStyle =
              Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontSize: typography.fontSize,
                    height: typography.lineHeight,
                    fontFamily: typography.fontFamily,
                  ) ??
                  const TextStyle();
          final highlightStyle = TextStyle(
            backgroundColor: cs.primaryContainer.withAlpha(180),
            color: cs.onPrimaryContainer,
          );
          final currentMatchStyle = TextStyle(
            backgroundColor: Colors.amber.shade400.withAlpha(220),
            color: Colors.black,
            fontWeight: FontWeight.bold,
          );

          return Column(
            children: [
              _buildSermonNavRow(),
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 8.0),
                  itemCount: paragraphs.length,
                  itemBuilder: (context, index) {
                    final paragraph = paragraphs[index];
                    final key = index < _verseKeys.length
                        ? _verseKeys[index]
                        : GlobalKey();

                    // Compute which occurrence in this paragraph is the current match.
                    int? currentOccurrence;
                    if (_matchVerseIndices.isNotEmpty &&
                        _matchVerseIndices[_currentMatchIndex] == index) {
                      currentOccurrence = _currentMatchIndex -
                          _matchVerseIndices
                              .sublist(0, _currentMatchIndex)
                              .where((pi) => pi == index)
                              .length;
                    }

                    final isParagraphSelected =
                        _selectedParagraphIndices.contains(index);
                    return GestureDetector(
                      key: key,
                      onTap: () => _toggleParagraphSelection(index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        decoration: BoxDecoration(
                          color: isParagraphSelected
                              ? cs.primaryContainer.withAlpha(120)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 4),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: RichText(
                          text: TextSpan(
                            style: baseStyle,
                            children: [
                              if (paragraph.paragraphNumber != null)
                                TextSpan(
                                  text: '${paragraph.paragraphNumber}\u00B6 ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: typography.fontSize * 0.8,
                                    color: isParagraphSelected
                                        ? cs.primary
                                        : Colors.grey,
                                  ),
                                ),
                              ..._buildHighlightedSpans(
                                paragraph.text,
                                baseStyle,
                                highlightStyle,
                                currentMatchStyle,
                                currentOccurrenceIndex: currentOccurrence,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
      );
    }

    return Center(
        child: Text('Unsupported content type for ${tab.title}...'));
  }

  // ── All-sermons FTS results list ──────────────────────────────────────────

  Widget _buildAllSermonResults() {
    final theme = Theme.of(context);

    if (_allSermonSearchLoading && _allSermonResults.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_allSermonResults.isEmpty) {
      return Center(
        child: Text(
          _searchController.text.length < 2
              ? 'Type at least 2 characters to search all sermons.'
              : 'No results found.',
          textAlign: TextAlign.center,
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }

    return ListView.builder(
      itemCount: _allSermonResults.length,
      padding: const EdgeInsets.only(bottom: 16),
      itemBuilder: (context, i) {
        final r = _allSermonResults[i];
        final metaParts = <String>[
          if (r.paragraphLabel != null && r.paragraphLabel!.isNotEmpty)
            '¶${r.paragraphLabel}',
          if (r.paragraphNumber != null) '${r.paragraphNumber}¶',
          if (r.date != null && r.date!.isNotEmpty) r.date!,
          if (r.location != null && r.location!.isNotEmpty) r.location!,
        ];
        final meta = metaParts.join(' • ');

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _openSermonFromResult(r),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          r.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.home_outlined,
                            size: 20,
                            color: theme.colorScheme.primary),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        onPressed: () => _openSermonFromResult(r),
                      ),
                    ],
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                  const SizedBox(height: 6),
                  FtsHighlightText(rawSnippet: r.snippet),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── In-content navigation row (Previous | B | M | Next) ──────────────────

  Widget _buildSermonNavRow() {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(100),
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton.icon(
            icon: const Icon(Icons.chevron_left, size: 18),
            label: const Text('Previous'),
            style: TextButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => _openAdjacentSermon(-1),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _NavIconButton(
                label: 'B',
                icon: Icons.menu_book_outlined,
                onPressed: _openQuickNav,
              ),
              const SizedBox(width: 8),
              _NavIconButton(
                label: 'M',
                icon: Icons.import_contacts,
                onPressed: _openSermonQuickNav,
              ),
            ],
          ),
          TextButton.icon(
            icon: const Icon(Icons.chevron_right, size: 18),
            label: const Text('Next'),
            iconAlignment: IconAlignment.end,
            style: TextButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => _openAdjacentSermon(1),
          ),
        ],
      ),
    );
  }

  // ── Bottom tab bar ────────────────────────────────────────────────────────

  Widget _buildBottomTabBar(
      BuildContext context, SermonFlowState state) {
    final theme = Theme.of(context);
    return BottomAppBar(
      elevation: 8,
      child: SizedBox(
        height: 50,
        child: Row(
          children: [
            // Scrollable tabs
            Expanded(
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: state.tabs.length,
                itemBuilder: (context, index) {
                  final tab = state.tabs[index];
                  final isActive = index == state.activeTabIndex;
                  final isSermonTab = index == 0;

                  return GestureDetector(
                    onTap: () {
                      ref
                          .read(sermonFlowProvider.notifier)
                          .switchTab(index);
                      if (_scrollController.hasClients) {
                        _scrollController.jumpTo(0);
                      }
                      setState(() {
                        _selectedVerseNumbers.clear();
                        _selectedParagraphIndices.clear();
                        _isSearching = false;
                        _searchController.clear();
                        _clearMatches();
                        _currentVerses = [];
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 4),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: isActive
                            ? theme.colorScheme.primaryContainer
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isActive
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outline.withAlpha(128),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isSermonTab
                                ? Icons.headphones
                                : Icons.menu_book_outlined,
                            size: 14,
                            color: isActive
                                ? theme.colorScheme.onPrimaryContainer
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _shortenTitle(tab.title),
                            style: TextStyle(
                              fontWeight: isActive
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isActive
                                  ? theme.colorScheme.onPrimaryContainer
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                          if (state.tabs.length > 1) ...[
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: () => ref
                                  .read(sermonFlowProvider.notifier)
                                  .closeTab(index),
                              child: Icon(
                                Icons.close,
                                size: 14,
                                color: isActive
                                    ? theme.colorScheme.onPrimaryContainer
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // "+" opens sermon quick nav
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _openSermonQuickNav,
              visualDensity: VisualDensity.compact,
            ),

            // "⋮" three-dots popup
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'close_others',
                  child: Text('Close Other Tabs'),
                ),
                PopupMenuItem(
                  value: 'hide_tabs',
                  child: Text('Hide Bottom Tabs'),
                ),
              ],
              onSelected: (val) {
                if (val == 'close_others') _closeOtherTabs();
                if (val == 'hide_tabs') {
                  setState(() => _hideBottomTabs = true);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  String _shortenTitle(String title) {
    if (title.length > 15) return '${title.substring(0, 12)}...';
    return title;
  }
}

// ── Private helper widgets ────────────────────────────────────────────────────

/// A labeled row: [Text label]  [FloatingActionButton.small]
class _FabOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _FabOption({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          elevation: 2,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(label,
                style: Theme.of(context).textTheme.labelMedium),
          ),
        ),
        const SizedBox(width: 8),
        FloatingActionButton.small(
          heroTag: label,
          onPressed: onTap,
          child: Icon(icon, size: 20),
        ),
      ],
    );
  }
}

/// Compact icon+label button used in the in-content nav row (B / M).
class _NavIconButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const _NavIconButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OutlinedButton.icon(
      icon: Icon(icon, size: 16),
      label: Text(label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: BorderSide(color: theme.colorScheme.outline.withAlpha(160)),
      ),
      onPressed: onPressed,
    );
  }
}
