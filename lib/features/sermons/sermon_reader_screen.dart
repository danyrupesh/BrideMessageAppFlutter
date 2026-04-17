import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart' show SharePlus, ShareParams;
import 'package:printing/printing.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/pdf_export_service.dart';
import '../../core/utils/desktop_file_saver.dart';
import '../../core/utils/tamil_normalizer.dart';
import '../../core/widgets/responsive_bottom_sheet.dart';
import '../../core/widgets/selection_action_bar.dart';
import 'providers/sermon_flow_provider.dart';
import 'providers/sermon_provider.dart';
import 'widgets/sermon_quick_nav_sheet.dart';
import '../reader/models/reader_tab.dart';
import '../reader/providers/reader_provider.dart';
import '../reader/providers/typography_provider.dart';
import '../reader/widgets/quick_navigation_sheet.dart';
import '../reader/widgets/reader_settings_sheet.dart';
import '../reader/widgets/pane_header.dart';
import '../reader/widgets/reading_pane.dart';
import '../onboarding/onboarding_screen.dart';
import '../../core/database/models/bible_search_result.dart';
import '../../core/database/models/sermon_models.dart';
import '../../core/database/models/sermon_search_result.dart';
import '../search/providers/search_provider.dart' show SearchType;
import '../common/widgets/fts_highlight_text.dart';
import '../help/widgets/help_button.dart';

class _NextMatchIntent extends Intent {
  const _NextMatchIntent();
}

class _PrevMatchIntent extends Intent {
  const _PrevMatchIntent();
}

class _AppBarChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool isWide;

  const _AppBarChip({
    required this.label,
    required this.onTap,
    this.icon,
    this.isWide = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final fontSize = isWide ? 15.0 : 13.0;
    final horizontalPadding = isWide ? 14.0 : 10.0;
    final verticalPadding = isWide ? 8.0 : 6.0;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: verticalPadding,
        ),
        decoration: BoxDecoration(
          color: cs.primaryContainer.withAlpha(160),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: isWide ? 20 : 16, color: cs.primary),
              SizedBox(width: isWide ? 6 : 4),
            ],
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: fontSize,
                color: cs.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SermonReaderScreen extends ConsumerStatefulWidget {
  const SermonReaderScreen({super.key});

  @override
  ConsumerState<SermonReaderScreen> createState() => _SermonReaderScreenState();
}

class SermonSelectionWidget extends StatefulWidget {
  final TextSpan combinedSpan;
  final ScrollController scrollController;

  const SermonSelectionWidget({
    super.key,
    required this.combinedSpan,
    required this.scrollController,
  });

  @override
  State<SermonSelectionWidget> createState() => _SermonSelectionWidgetState();
}

class _SermonSelectionWidgetState extends State<SermonSelectionWidget> {
  String? selectedText;
  Offset? selectionPosition;

  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  void _showPopover() {
    _removePopover();

    if (selectedText == null || selectionPosition == null) return;

    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          left: selectionPosition!.dx - 80,
          top: selectionPosition!.dy - 60,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: const Offset(0, -50),
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: selectedText!));
                        _removePopover();
                      },
                      child: const Text(
                        "Copy",
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () {
                        // TODO: integrate share
                        _removePopover();
                      },
                      child: const Text(
                        "Share",
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removePopover() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  void dispose() {
    _removePopover();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        selectedText = null;
        _removePopover();
      },
      child: CompositedTransformTarget(
        link: _layerLink,
        child: SelectionArea(
          contextMenuBuilder: (context, state) => const SizedBox.shrink(),
          onSelectionChanged: (selection) {
            final text = selection?.plainText ?? '';

            if (text.trim().isEmpty) {
              selectedText = null;
              _removePopover();
              return;
            }

            selectedText = text.trim();

            final renderBox = context.findRenderObject() as RenderBox;
            final position = renderBox.localToGlobal(Offset.zero);

            selectionPosition = position;

            Future.delayed(const Duration(milliseconds: 100), () {
              if (mounted) _showPopover();
            });
          },
          child: SingleChildScrollView(
            controller: widget.scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: RichText(text: widget.combinedSpan),
          ),
        ),
      ),
    );
  }
}

class _SermonReaderScreenState extends ConsumerState<SermonReaderScreen> {
  static final PdfExportService _pdfExportService = PdfExportService();
  static const int _allSermonsPageSize = 30;

  // ── Scroll controller (preserves position across fullscreen toggle) ────────
  final ScrollController _scrollController = ScrollController();
  final ScrollController _splitPrimaryScrollController = ScrollController();
  final ScrollController _splitSecondaryScrollController = ScrollController();

  // ── In-page search ────────────────────────────────────────────────────────
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String?
  _lastSearchActivatedTabId; // Track which tab had search auto-activated
  List<GlobalKey> _verseKeys = [];
  List<int> _matchVerseIndices = [];
  int _currentMatchIndex = 0;
  int _totalMatches = 0;

  // ── Verse selection (Bible ref tabs) ─────────────────────────────────────
  final Set<int> _selectedVerseNumbers = {};
  List<BibleSearchResult> _currentVerses = [];

  // ── OS text selection (sermons & Bible) ───────────────────────────────────
  String? _activeSelectionText;
  Timer? _sermonSelectionDebounce;

  // ── Search scope / All-sermons FTS ────────────────────────────────────────
  bool _searchAllSermons = false;
  SearchType _sermonSearchType = SearchType.all;
  List<SermonSearchResult> _allSermonResults = [];
  bool _allSermonSearchLoading = false;
  bool _allSermonSearchLoadingMore = false;
  bool _allSermonHasMore = false;
  Timer? _allSermonSearchDebounce;
  int _allSermonSearchRequestId = 0;
  String? _lastActiveTabId;
  String? _lastTypographyLang;
  String? _initialSearchScrollTabId;

  // ── Paragraph cache (for "This Sermon" in-page search) ───────────────────
  List<SermonParagraphEntity> _currentParagraphs = [];
  int? _selectionFirstParagraph;
  int? _selectionLastParagraph;

  // ── UI state ──────────────────────────────────────────────────────────────
  bool _fabExpanded = false;
  bool _hideBottomTabs = false;
  static const double _bmWideBreakpoint = 900.0;
  static const double _bmSplitDefault = 0.6;
  static const double _bmSplitMin = 0.35;
  static const double _bmSplitMax = 0.75;
  static const double _bmSplitterWidth = 8.0;
  static const String _bmSplitRatioKey = 'sermon_bm_split_ratio';
  static const String _splitPrimaryFontOffsetKey =
      'sermon_split_primary_font_offset';
  static const String _splitSecondaryFontOffsetKey =
      'sermon_split_secondary_font_offset';
  double _bmSplitRatio = _bmSplitDefault;
  double _splitPrimaryFontOffset = 0.0;
  double _splitSecondaryFontOffset = 0.0;
  final Map<String, Future<List<SermonParagraphEntity>>>
      _bmSecondarySermonFutureCache = {};
  final TextEditingController _primaryMiniSearchController =
      TextEditingController();
  final TextEditingController _secondaryMiniSearchController =
      TextEditingController();
  final FocusNode _primaryMiniSearchFocusNode = FocusNode();
  final FocusNode _secondaryMiniSearchFocusNode = FocusNode();
  bool _primaryMiniSearchActive = false;
  bool _secondaryMiniSearchActive = false;
  List<int> _primaryMatchIndices = [];
  int _primaryCurrentMatchIndex = 0;
  int _primaryTotalMatches = 0;
  List<int> _secondaryMatchIndices = [];
  int _secondaryCurrentMatchIndex = 0;
  int _secondaryTotalMatches = 0;
  List<BibleSearchResult> _bmCurrentVerses = [];
  List<SermonParagraphEntity> _bmSecondaryParagraphs = [];
  List<GlobalKey> _bmVerseKeys = [];
  String? _bmVerseSignature;
  bool _bmDefaultBiblePending = false;
  final FocusNode _searchFieldFocusNode = FocusNode();
  late final bool Function(KeyEvent) _searchKeyHandler;

  @override
  void initState() {
    super.initState();
    _searchKeyHandler = (event) {
      if (!_isSearching) return false;
      if (event is! KeyDownEvent) return false;
      final isEnter =
          event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter;
      if (!isEnter) return false;
      if (_searchAllSermons || _totalMatches == 0) return true;
      if (HardwareKeyboard.instance.isShiftPressed) {
        _navigateToMatch(-1);
      } else {
        _navigateToMatch(1);
      }
      return true;
    };
    HardwareKeyboard.instance.addHandler(_searchKeyHandler);
    unawaited(_loadBmSplitPreferences());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _splitPrimaryScrollController.dispose();
    _splitSecondaryScrollController.dispose();
    _searchController.dispose();
    _primaryMiniSearchController.dispose();
    _secondaryMiniSearchController.dispose();
    _searchFieldFocusNode.dispose();
    _primaryMiniSearchFocusNode.dispose();
    _secondaryMiniSearchFocusNode.dispose();
    _bmSecondarySermonFutureCache.clear();
    _allSermonSearchDebounce?.cancel();
    HardwareKeyboard.instance.removeHandler(_searchKeyHandler);
    super.dispose();
  }

  Future<List<SermonParagraphEntity>> _getBmSecondarySermonFuture({
    required String sermonLang,
    required String sermonId,
  }) {
    final cacheKey = '$sermonLang::$sermonId';
    return _bmSecondarySermonFutureCache.putIfAbsent(cacheKey, () async {
      final repo = await ref.read(sermonRepositoryByLangProvider(sermonLang).future);
      return repo.getParagraphsForSermon(sermonId);
    });
  }

  Future<void> _loadBmSplitPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final storedRatio = prefs.getDouble(_bmSplitRatioKey);
    final storedPrimaryOffset = prefs.getDouble(_splitPrimaryFontOffsetKey);
    final storedSecondaryOffset = prefs.getDouble(_splitSecondaryFontOffsetKey);
    setState(() {
      if (storedRatio != null) {
        _bmSplitRatio = storedRatio.clamp(_bmSplitMin, _bmSplitMax);
      }
      if (storedPrimaryOffset != null) {
        _splitPrimaryFontOffset = storedPrimaryOffset;
      }
      if (storedSecondaryOffset != null) {
        _splitSecondaryFontOffset = storedSecondaryOffset;
      }
    });
  }

  Future<void> _persistBmSplitRatio() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_bmSplitRatioKey, _bmSplitRatio);
  }

  Future<void> _persistSplitFontOffsets() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_splitPrimaryFontOffsetKey, _splitPrimaryFontOffset);
    await prefs.setDouble(
      _splitSecondaryFontOffsetKey,
      _splitSecondaryFontOffset,
    );
  }

  Future<void> _ensureBmDefaultBibleTab() async {
    final flow = ref.read(sermonFlowProvider);
    if (!flow.bmMode || flow.bmBibleGroup.tabs.isNotEmpty) return;
    if (_bmDefaultBiblePending) return;
    _bmDefaultBiblePending = true;

    final sermonLang = ref.read(selectedSermonLangProvider);
    final fallbackLang = ref.read(selectedBibleLangProvider);
    final langCandidate = fallbackLang.trim().isEmpty
        ? sermonLang
        : fallbackLang;
    final lang = langCandidate == 'ta' ? 'ta' : 'en';

    try {
      final books = await ref
          .read(bibleBookListByLangProvider(lang).future)
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;

      String defaultBook = lang == 'ta' ? 'ஆதியாகமம்' : 'Genesis';
      if (books.isNotEmpty) {
        final sortedBooks = [...books]
          ..sort((firstBook, secondBook) {
            final firstIndex = firstBook['book_index'] as int? ?? 1;
            final secondIndex = secondBook['book_index'] as int? ?? 1;
            return firstIndex.compareTo(secondIndex);
          });
        final firstBookName = sortedBooks.first['book'] as String?;
        if (firstBookName != null && firstBookName.trim().isNotEmpty) {
          defaultBook = firstBookName.trim();
        }
      }

      final defaultTab = ReaderTab(
        type: ReaderContentType.bible,
        title: '$defaultBook 1',
        book: defaultBook,
        chapter: 1,
        bibleLang: lang,
      );
      ref
          .read(sermonFlowProvider.notifier)
          .upsertBmBibleTab(bibleTab: defaultTab, openInNewTab: false);
    } catch (_) {
      if (!mounted) return;
      final fallbackBook = lang == 'ta' ? 'ஆதியாகமம்' : 'Genesis';
      final defaultTab = ReaderTab(
        type: ReaderContentType.bible,
        title: '$fallbackBook 1',
        book: fallbackBook,
        chapter: 1,
        bibleLang: lang,
      );
      ref
          .read(sermonFlowProvider.notifier)
          .upsertBmBibleTab(bibleTab: defaultTab, openInNewTab: false);
    } finally {
      _bmDefaultBiblePending = false;
    }
  }

  double _primaryPaneFontSize(TypographySettings typography) {
    return (typography.fontSize + _splitPrimaryFontOffset).clamp(12.0, 56.0);
  }

  double _secondaryPaneFontSize(TypographySettings typography) {
    return (typography.fontSize + _splitSecondaryFontOffset).clamp(12.0, 56.0);
  }

  void _adjustPrimarySplitFont(double delta) {
    final activeTab = ref.read(sermonFlowProvider).activeTab;
    final lang = activeTab?.bibleLang ?? ref.read(selectedSermonLangProvider) ?? 'en';
    setState(() {
      final current = _primaryPaneFontSize(ref.read(typographyProvider(lang)));
      final next = (current + delta).clamp(12.0, 56.0);
      _splitPrimaryFontOffset = next - ref.read(typographyProvider(lang)).fontSize;
    });
    unawaited(_persistSplitFontOffsets());
  }

  void _adjustSecondarySplitFont(double delta) {
    final flow = ref.read(sermonFlowProvider);
    final group = flow.bmBibleGroup;
    final activeSec = group.tabs.isNotEmpty ? group.tabs[group.activeIndex.clamp(0, group.tabs.length - 1)] : null;
    final lang = activeSec?.bibleLang ?? activeSec?.sermonLang ?? 'en';
    
    setState(() {
      final current = _secondaryPaneFontSize(ref.read(typographyProvider(lang)));
      final next = (current + delta).clamp(12.0, 56.0);
      _splitSecondaryFontOffset = next - ref.read(typographyProvider(lang)).fontSize;
    });
    unawaited(_persistSplitFontOffsets());
  }

  List<int> _computeMatchIndices(List<String> texts, String query) {
    if (query.trim().isEmpty || texts.isEmpty) return [];
    final pattern = RegExp(query, caseSensitive: false);
    final indices = <int>[];
    for (var i = 0; i < texts.length; i++) {
      final count = pattern.allMatches(texts[i]).length;
      for (var j = 0; j < count; j++) {
        indices.add(i);
      }
    }
    return indices;
  }

  int? _currentOccurrenceForItemWithState({
    required List<int> matchIndices,
    required int currentMatchIndex,
    required int itemIndex,
  }) {
    if (matchIndices.isEmpty) return null;
    if (currentMatchIndex < 0 || currentMatchIndex >= matchIndices.length) {
      return null;
    }
    if (matchIndices[currentMatchIndex] != itemIndex) return null;

    var count = 0;
    for (var i = 0; i < currentMatchIndex; i++) {
      if (matchIndices[i] == itemIndex) count++;
    }
    return count;
  }

  Future<void> _openAdjacentBmBiblePassage(int direction) async {
    final flow = ref.read(sermonFlowProvider);
    final group = flow.bmBibleGroup;
    if (group.tabs.isEmpty) return;

    final activeIndex = group.activeIndex.clamp(0, group.tabs.length - 1);
    final activeTab = group.tabs[activeIndex];
    final currentBook = activeTab.book;
    final currentChapter = activeTab.chapter;
    final lang =
        (activeTab.bibleLang ?? ref.read(selectedBibleLangProvider)) ?? 'en';
    if (currentBook == null || currentChapter == null) return;

    final books = await ref.read(bibleBookListByLangProvider(lang).future);
    if (books.isEmpty) return;

    final sortedBooks = [...books]
      ..sort((a, b) {
        final first = a['book_index'] as int? ?? 1;
        final second = b['book_index'] as int? ?? 1;
        return first.compareTo(second);
      });

    final bookIndex = sortedBooks.indexWhere((b) => b['book'] == currentBook);
    if (bookIndex == -1) return;

    var nextBookIndex = bookIndex;
    var nextChapter = currentChapter;

    if (direction > 0) {
      final currentBookChapters =
          sortedBooks[bookIndex]['chapters'] as int? ?? 1;
      if (currentChapter < currentBookChapters) {
        nextChapter = currentChapter + 1;
      } else if (bookIndex < sortedBooks.length - 1) {
        nextBookIndex = bookIndex + 1;
        nextChapter = 1;
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No next Bible passage.')),
          );
        }
        return;
      }
    } else {
      if (currentChapter > 1) {
        nextChapter = currentChapter - 1;
      } else if (bookIndex > 0) {
        nextBookIndex = bookIndex - 1;
        final prevBookChapters =
            sortedBooks[nextBookIndex]['chapters'] as int? ?? 1;
        nextChapter = prevBookChapters;
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No previous Bible passage.')),
          );
        }
        return;
      }
    }

    final nextBook = sortedBooks[nextBookIndex]['book'] as String;
    final nextTab = ReaderTab(
      type: ReaderContentType.bible,
      title: '$nextBook $nextChapter',
      book: nextBook,
      chapter: nextChapter,
      bibleLang: lang,
    );
    final added = ref
        .read(sermonFlowProvider.notifier)
        .upsertBmBibleTab(bibleTab: nextTab, openInNewTab: false);
    if (!added && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Split view tab limit reached (20).')),
      );
    }
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
              direction > 0 ? 'No next sermon.' : 'No previous sermon.',
            ),
            duration: const Duration(seconds: 1),
          ),
        );
      }
      return;
    }
    final currentTabs = ref.read(sermonFlowProvider).tabs;
    final replaceIndex = currentTabs.indexWhere((t) {
      if (t.type != ReaderContentType.sermon) return false;
      if (sermonTab?.sermonId != null) {
        return t.sermonId == sermonTab!.sermonId;
      }
      return t.id == sermonTab?.id;
    });

    final nextTab = ReaderTab(
      type: ReaderContentType.sermon,
      title: adjacent.title,
      sermonId: adjacent.id,
    );

    if (replaceIndex >= 0) {
      ref
          .read(sermonFlowProvider.notifier)
          .replaceSermonTab(replaceIndex, nextTab);
    } else {
      ref.read(sermonFlowProvider.notifier).openSermon(nextTab);
    }
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
    });
  }

  // ── Quick-nav — Bible ──────────────────────────────────────────────────────

  Future<void> _openQuickNav({String? forcedInitialLang}) async {
    final flowState = ref.read(sermonFlowProvider);
    final isBmMode = flowState.bmMode;
    final sermonLang = ref.read(selectedSermonLangProvider);
    final activeBibleLang = flowState.activeTab?.type == ReaderContentType.bible
        ? flowState.activeTab?.bibleLang
        : null;
    final initialLang = (forcedInitialLang == 'ta' || forcedInitialLang == 'en')
        ? forcedInitialLang!
        : (activeBibleLang == 'ta' || activeBibleLang == 'en')
        ? activeBibleLang!
        : (sermonLang == 'ta' ? 'ta' : 'en');
    setState(() => _fabExpanded = false);
    final result = await showResponsiveBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      maxWidth: 980,
      builder: (_) => QuickNavigationSheet(initialLang: initialLang),
    );
    if (result == null) return;
    final verse = result['verse'] as int?;
    final newTab = ReaderTab(
      type: ReaderContentType.bible,
      // App bar title should always show only book name + chapter number,
      // even when a specific verse is selected.
      title: "${result['book']} ${result['chapter']}",
      book: result['book'] as String,
      chapter: result['chapter'] as int,
      verse: verse,
      bibleLang: result['lang'] as String?,
    );
    if (!isBmMode) {
      ref.read(sermonFlowProvider.notifier).setBmMode(true);
    }
    final added = ref
        .read(sermonFlowProvider.notifier)
        .upsertBmBibleTab(
          bibleTab: newTab,
          openInNewTab: result['newTab'] == true,
        );
    if (!added && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Split view tab limit reached (20).')),
      );
    }
    setState(() {
      _selectedVerseNumbers.clear();
      _isSearching = false;
      _searchController.clear();
      _clearMatches();
    });
  }

  Future<void> _openQuickNavForBibleTab({
    int? tabIndex,
    int? bmIndex,
    required bool isBm,
  }) async {
    final flowState = ref.read(sermonFlowProvider);
    final sermonLang = ref.read(selectedSermonLangProvider);
    String? preferredLang;
    if (isBm && bmIndex != null) {
      final bmTabs = flowState.bmBibleGroup.tabs;
      if (bmIndex >= 0 && bmIndex < bmTabs.length) {
        preferredLang = bmTabs[bmIndex].bibleLang;
      }
    } else if (!isBm && tabIndex != null) {
      final tabs = flowState.tabs;
      if (tabIndex >= 0 && tabIndex < tabs.length) {
        preferredLang = tabs[tabIndex].bibleLang;
      }
    }
    final initialLang = (preferredLang == 'ta' || preferredLang == 'en')
        ? preferredLang!
        : (sermonLang == 'ta' ? 'ta' : 'en');

    setState(() => _fabExpanded = false);
    if (isBm && bmIndex != null) {
      ref.read(sermonFlowProvider.notifier).setBmBibleActive(bmIndex);
    } else if (!isBm && tabIndex != null) {
      ref.read(sermonFlowProvider.notifier).switchTab(tabIndex);
    }
    final result = await showResponsiveBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      maxWidth: 980,
      builder: (_) => QuickNavigationSheet(initialLang: initialLang),
    );
    if (result == null) return;

    final verse = result['verse'] as int?;
    final newTab = ReaderTab(
      type: ReaderContentType.bible,
      title: "${result['book']} ${result['chapter']}",
      book: result['book'] as String,
      chapter: result['chapter'] as int,
      verse: verse,
      bibleLang: result['lang'] as String?,
    );

    if (isBm) {
      final added = ref
          .read(sermonFlowProvider.notifier)
          .upsertBmBibleTab(bibleTab: newTab, openInNewTab: false);
      if (!added && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Split view tab limit reached (20).')),
        );
      }
    } else if (tabIndex != null) {
      ref.read(sermonFlowProvider.notifier).replaceBibleTab(tabIndex, newTab);
    }

    setState(() {
      _selectedVerseNumbers.clear();
      _isSearching = false;
      _searchController.clear();
      _clearMatches();
    });
  }

  // ── Quick-nav — Sermon ─────────────────────────────────────────────────────

  Future<void> _openSermonQuickNav() async {
    setState(() => _fabExpanded = false);
    await showResponsiveBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      maxWidth: 720,
      builder: (ctx) => SermonQuickNavSheet(
        onSelected: (sermon) {
          final added = ref
              .read(sermonFlowProvider.notifier)
              .addSermonTab(
                ReaderTab(
                  type: ReaderContentType.sermon,
                  title: sermon.title,
                  sermonId: sermon.id,
                ),
              );
          if (!added && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Split view tab limit reached (20).'),
              ),
            );
            return;
          }
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(0);
          }
          setState(() {
            _isSearching = false;
            _searchController.clear();
            _clearMatches();
            _currentVerses = [];
          });
        },
      ),
    );
  }

  Future<void> _openSermonQuickNavForTab(int tabIndex) async {
    setState(() => _fabExpanded = false);
    await showResponsiveBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      maxWidth: 720,
      builder: (ctx) => SermonQuickNavSheet(
        onSelected: (sermon) {
          ref
              .read(sermonFlowProvider.notifier)
              .replaceSermonTab(
                tabIndex,
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
            _selectedVerseNumbers.clear();
            _isSearching = false;
            _searchController.clear();
            _clearMatches();
            _currentVerses = [];
          });
        },
      ),
    );
  }


  // ── All-Sermons FTS search ────────────────────────────────────────────────

  Future<void> _triggerAllSermonSearch({bool append = false}) async {
    final requestId = ++_allSermonSearchRequestId;
    final q = _searchController.text.trim();
    if (q.length < 2) {
      setState(() {
        _allSermonResults = [];
        _allSermonSearchLoading = false;
        _allSermonSearchLoadingMore = false;
        _allSermonHasMore = false;
      });
      return;
    }

    if (append && !_allSermonHasMore) return;

    setState(() {
      if (append) {
        _allSermonSearchLoadingMore = true;
      } else {
        _allSermonSearchLoading = true;
      }
    });
    try {
      final repo = await ref.read(sermonRepositoryProvider.future);
      final results = await repo
          .searchSermons(
            query: q,
            limit: _allSermonsPageSize,
            offset: append ? _allSermonResults.length : 0,
            exactMatch: _sermonSearchType == SearchType.exact,
            anyWord: _sermonSearchType == SearchType.any,
          )
          .timeout(const Duration(seconds: 12));
      if (requestId != _allSermonSearchRequestId) return;
      if (mounted) {
        setState(() {
          _allSermonResults = append
              ? <SermonSearchResult>[..._allSermonResults, ...results]
              : results;
          _allSermonHasMore = results.length == _allSermonsPageSize;
          _allSermonSearchLoading = false;
          _allSermonSearchLoadingMore = false;
        });
      }
    } catch (_) {
      if (requestId != _allSermonSearchRequestId) return;
      if (mounted) {
        setState(() {
          _allSermonSearchLoading = false;
          _allSermonSearchLoadingMore = false;
        });
      }
    }
  }

  void _scheduleAllSermonSearch({bool immediate = false}) {
    _allSermonSearchDebounce?.cancel();
    if (immediate) {
      _triggerAllSermonSearch();
      return;
    }
    _allSermonSearchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _triggerAllSermonSearch();
    });
  }

  void _loadMoreAllSermons() {
    _allSermonSearchDebounce?.cancel();
    _triggerAllSermonSearch(append: true);
  }

  void _openSermonFromResult(SermonSearchResult result) {
    final added = ref
        .read(sermonFlowProvider.notifier)
        .addSermonTab(
          ReaderTab(
            type: ReaderContentType.sermon,
            title: result.title,
            sermonId: result.sermonId,
          ),
        );
    if (!added) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Split view tab limit reached (20).')),
      );
      return;
    }
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    setState(() {
      _isSearching = false;
      _searchAllSermons = false;
      _searchController.clear();
      _clearMatches();
      _allSermonResults = [];
      _allSermonHasMore = false;
      _allSermonSearchLoadingMore = false;
      _currentParagraphs = [];
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

  void _computeMatches(String query, {bool scrollToMatch = true}) {
    // Unified match computation for both Bible verses and sermon paragraphs.
    final isSermonTab =
        ref.read(sermonFlowProvider).activeTab?.type ==
        ReaderContentType.sermon;
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
    final indices = _computeMatchIndices(texts, query);
    setState(() {
      _matchVerseIndices = indices;
      _totalMatches = indices.length;
      _currentMatchIndex = 0;
    });
    if (indices.isNotEmpty && scrollToMatch) _scrollToCurrentMatch();
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

  void _adjustReaderFontSize(double delta) {
    final activeTab = ref.read(sermonFlowProvider).activeTab;
    final lang = activeTab?.type == ReaderContentType.bible
        ? (activeTab?.bibleLang ?? ref.read(selectedBibleLangProvider))
        : ref.read(selectedSermonLangProvider);
    final stableLang = lang ?? 'en';
    final typography = ref.read(typographyProvider(stableLang));
    final next = (typography.fontSize + delta).clamp(12.0, 56.0).toDouble();
    if (stableLang == 'ta') {
      ref.read(taTypographyProvider.notifier).updateFontSize(next);
    } else {
      ref.read(enTypographyProvider.notifier).updateFontSize(next);
    }
  }

  int? _currentOccurrenceForItem(int itemIndex) {
    return _currentOccurrenceForItemWithState(
      matchIndices: _matchVerseIndices,
      currentMatchIndex: _currentMatchIndex,
      itemIndex: itemIndex,
    );
  }

  Future<void> _openAdjacentSecondarySermon({
    required ReaderTab currentTab,
    required int direction,
  }) async {
    final sermonId = currentTab.sermonId;
    if (sermonId == null || sermonId.isEmpty) return;
    final String lang =
        (currentTab.sermonLang ?? ref.read(selectedSermonLangProvider)) == 'ta'
        ? 'ta'
        : 'en';
    final repo = await ref.read(sermonRepositoryByLangProvider(lang).future);
    final adjacent = await repo.getAdjacentSermon(sermonId, direction);
    if (!mounted) return;
    if (adjacent == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            direction > 0 ? 'No next sermon.' : 'No previous sermon.',
          ),
        ),
      );
      return;
    }
    ref
        .read(sermonFlowProvider.notifier)
        .upsertBmBibleTab(
          bibleTab: currentTab.copyWith(
            title: adjacent.title,
            sermonId: adjacent.id,
            sermonLang: lang,
          ),
          openInNewTab: false,
        );
  }

  /// Height of [_buildSermonNavRow] (padding + compact buttons); keep in sync with UI.
  static const double _kSermonNavRowHeight = 44;

  double _estimatedOffsetForIndex(int index) {
    if (!_scrollController.hasClients || _verseKeys.isEmpty) return 0;
    final max = _scrollController.position.maxScrollExtent;
    final frac = _verseKeys.length <= 1 ? 0.0 : index / (_verseKeys.length - 1);
    final offset = max * frac;
    return offset.clamp(0.0, max).toDouble();
  }

  /// Places the paragraph [index] just below the app bar + in-reader nav row,
  /// using global coordinates (independent of font size / line height).
  void _jumpAlignParagraphUnderBars(int index) {
    if (!_scrollController.hasClients ||
        index < 0 ||
        index >= _verseKeys.length) {
      return;
    }
    if (!mounted) return;
    final ctx = _verseKeys[index].currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;

    final media = MediaQuery.of(context);
    final targetScreenY =
        media.padding.top + kToolbarHeight + _kSermonNavRowHeight;
    final topOffset = box.localToGlobal(Offset.zero).dy;
    final delta = topOffset - targetScreenY;
    if (delta.abs() < 2) return;

    final nextOffset = (_scrollController.offset + delta).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.jumpTo(nextOffset.toDouble());
  }

  void _scrollToSermonOccurrenceInParagraph(
    int paragraphIndex,
    int occurrenceIndex,
  ) {
    if (!_scrollController.hasClients ||
        paragraphIndex < 0 ||
        paragraphIndex >= _verseKeys.length ||
        paragraphIndex >= _currentParagraphs.length ||
        !mounted) {
      return;
    }

    final query = _searchController.text;
    if (query.isEmpty) {
      _jumpAlignParagraphUnderBars(paragraphIndex);
      return;
    }

    final paragraphText = _currentParagraphs[paragraphIndex].text;
    if (paragraphText.isEmpty) {
      _jumpAlignParagraphUnderBars(paragraphIndex);
      return;
    }

    final ctx = _verseKeys[paragraphIndex].currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;

    final pattern = RegExp(query, caseSensitive: false);
    final matches = pattern.allMatches(paragraphText).toList();
    if (matches.isEmpty) {
      _jumpAlignParagraphUnderBars(paragraphIndex);
      return;
    }

    final safeOccurrence = occurrenceIndex.clamp(0, matches.length - 1);
    final charIndex = matches[safeOccurrence].start;
    final ratio = paragraphText.isEmpty
        ? 0.0
        : (charIndex / paragraphText.length).clamp(0.0, 1.0);

    final media = MediaQuery.of(context);
    final targetScreenY =
        media.padding.top + kToolbarHeight + _kSermonNavRowHeight + 6;
    final paragraphTop = box.localToGlobal(Offset.zero).dy;
    final estimatedOccurrenceY = paragraphTop + (box.size.height * ratio);
    final delta = estimatedOccurrenceY - targetScreenY;
    final nextOffset = (_scrollController.offset + delta).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.jumpTo(nextOffset.toDouble());
  }

  bool _scrollToCurrentSermonOccurrenceGlobal({bool instantScroll = false}) {
    if (!_scrollController.hasClients ||
        _matchVerseIndices.isEmpty ||
        _currentParagraphs.isEmpty ||
        _currentMatchIndex < 0 ||
        _currentMatchIndex >= _matchVerseIndices.length) {
      return false;
    }

    final paragraphIndex = _matchVerseIndices[_currentMatchIndex];
    if (paragraphIndex < 0 || paragraphIndex >= _currentParagraphs.length) {
      return false;
    }

    final query = _searchController.text;
    if (query.isEmpty) return false;

    final occurrenceIndex = _currentOccurrenceForItem(paragraphIndex) ?? 0;
    final pattern = RegExp(query, caseSensitive: false);

    var totalChars = 0;
    var charsBeforeTargetParagraph = 0;
    for (var i = 0; i < _currentParagraphs.length; i++) {
      final textLength = _currentParagraphs[i].text.length;
      if (i < paragraphIndex) {
        charsBeforeTargetParagraph += textLength;
        if (i < _currentParagraphs.length - 1) {
          charsBeforeTargetParagraph += 1;
        }
      }
      totalChars += textLength;
      if (i < _currentParagraphs.length - 1) {
        totalChars += 1;
      }
    }

    if (totalChars <= 0) return false;

    final matches = pattern
        .allMatches(_currentParagraphs[paragraphIndex].text)
        .toList();
    if (matches.isEmpty) return false;

    final safeOccurrence = occurrenceIndex.clamp(0, matches.length - 1);
    final localStart = matches[safeOccurrence].start;
    final globalCharOffset = charsBeforeTargetParagraph + localStart;
    final ratio = (globalCharOffset / totalChars).clamp(0.0, 1.0);
    final target = ratio * _scrollController.position.maxScrollExtent;

    if (instantScroll) {
      _scrollController.jumpTo(target);
    } else {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
    return true;
  }

  void _scrollToCurrentMatch({int retryCount = 0, bool instantScroll = false}) {
    if (_matchVerseIndices.isEmpty) return;
    final vi = _matchVerseIndices[_currentMatchIndex];
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final active = ref.read(sermonFlowProvider).activeTab;
      final inSermonSearch =
          active?.type == ReaderContentType.sermon && !_searchAllSermons;

      if (inSermonSearch &&
          _scrollToCurrentSermonOccurrenceGlobal(
            instantScroll: instantScroll,
          )) {
        return;
      }

      final ensureDuration = instantScroll
          ? Duration.zero
          : const Duration(milliseconds: 300);
      if (vi < _verseKeys.length) {
        final ctx = _verseKeys[vi].currentContext;
        if (ctx != null) {
          await Scrollable.ensureVisible(
            ctx,
            duration: ensureDuration,
            curve: Curves.easeInOut,
            alignment: 0.12,
            alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          );
          if (!mounted) return;
          if (inSermonSearch) {
            final occurrence = _currentOccurrenceForItem(vi) ?? 0;
            _scrollToSermonOccurrenceInParagraph(vi, occurrence);
          } else {
            _jumpAlignParagraphUnderBars(vi);
          }
          return;
        }
      }
      if (_scrollController.hasClients) {
        final estimated = _estimatedOffsetForIndex(vi);
        final current = _scrollController.offset;
        // Nudge toward target so item can build, then resolve via ensureVisible.
        if ((estimated - current).abs() > 8) {
          if (instantScroll) {
            _scrollController.jumpTo(estimated);
          } else {
            await _scrollController.animateTo(
              estimated,
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
            );
          }
        }
      }
      if (retryCount >= 8) return;
      Future<void>.delayed(const Duration(milliseconds: 16), () {
        if (!mounted) return;
        _scrollToCurrentMatch(
          retryCount: retryCount + 1,
          instantScroll: instantScroll,
        );
      });
    });
  }

  Future<SermonEntity?> _pickSermonForSecondaryPane(String lang) async {
    SermonEntity? picked;
    await showResponsiveBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      maxWidth: 720,
      builder: (ctx) => SermonQuickNavSheet(
        lang: lang,
        onSelected: (sermon) {
          picked = sermon;
        },
      ),
    );
    return picked;
  }

  Future<void> _openSecondaryBiblePicker({
    required String lang,
    required bool openInNewTab,
  }) async {
    final result = await showResponsiveBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      maxWidth: 980,
      builder: (_) => QuickNavigationSheet(initialLang: lang),
    );
    if (result == null) return;
    final verse = result['verse'] as int?;
    final rightTab = ReaderTab(
      type: ReaderContentType.bible,
      title: "${result['book']} ${result['chapter']}",
      book: result['book'] as String,
      chapter: result['chapter'] as int,
      verse: verse,
      bibleLang: result['lang'] as String? ?? lang,
    );
    final added = ref
        .read(sermonFlowProvider.notifier)
        .upsertBmBibleTab(bibleTab: rightTab, openInNewTab: openInNewTab);
    if (!added && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Split view tab limit reached (20).')),
      );
    }
  }

  Future<void> _openSecondarySermonPicker({
    required String lang,
    required bool openInNewTab,
  }) async {
    final sermon = await _pickSermonForSecondaryPane(lang);
    if (sermon == null) return;
    final rightTab = ReaderTab(
      type: ReaderContentType.sermon,
      title: sermon.title,
      sermonId: sermon.id,
      sermonLang: lang,
    );
    final added = ref
        .read(sermonFlowProvider.notifier)
        .upsertBmBibleTab(bibleTab: rightTab, openInNewTab: openInNewTab);
    if (!added && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Split view tab limit reached (20).')),
      );
    }
  }

  Future<void> _onSecondaryPaneSourceSelected(
    String value, {
    required bool openInNewTab,
  }) async {
    switch (value) {
      case 'bible_en':
        await _openSecondaryBiblePicker(lang: 'en', openInNewTab: openInNewTab);
        break;
      case 'bible_ta':
        await _openSecondaryBiblePicker(lang: 'ta', openInNewTab: openInNewTab);
        break;
      case 'sermon_en':
        await _openSecondarySermonPicker(
          lang: 'en',
          openInNewTab: openInNewTab,
        );
        break;
      case 'sermon_ta':
        await _openSecondarySermonPicker(
          lang: 'ta',
          openInNewTab: openInNewTab,
        );
        break;
    }
    if (!mounted) return;
    setState(() {
      _secondaryMiniSearchController.clear();
      _secondaryMatchIndices = [];
      _secondaryTotalMatches = 0;
      _secondaryCurrentMatchIndex = 0;
    });
  }

  void _computePrimaryPaneMatches(String query, {bool scrollToMatch = true}) {
    final indices = _computeMatchIndices(
      _currentParagraphs.map((paragraph) => paragraph.text).toList(),
      query,
    );
    setState(() {
      _primaryMatchIndices = indices;
      _primaryTotalMatches = indices.length;
      _primaryCurrentMatchIndex = 0;
    });
    if (indices.isNotEmpty && scrollToMatch) {
      _scrollPrimaryPaneToCurrentMatch();
    }
  }

  void _navigatePrimaryPaneMatch(int direction) {
    if (_primaryMatchIndices.isEmpty) return;
    setState(() {
      _primaryCurrentMatchIndex =
          (_primaryCurrentMatchIndex + direction) % _primaryMatchIndices.length;
      if (_primaryCurrentMatchIndex < 0) {
        _primaryCurrentMatchIndex = _primaryMatchIndices.length - 1;
      }
    });
    _scrollPrimaryPaneToCurrentMatch();
  }

  void _scrollPrimaryPaneToCurrentMatch({bool instantScroll = false}) {
    if (_primaryMatchIndices.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToSermonOccurrenceByState(
        controller: _splitPrimaryScrollController,
        paragraphs: _currentParagraphs,
        query: _primaryMiniSearchController.text,
        matchIndices: _primaryMatchIndices,
        currentMatchIndex: _primaryCurrentMatchIndex,
        instantScroll: instantScroll,
      );
    });
  }

  bool _scrollToSermonOccurrenceByState({
    required ScrollController controller,
    required List<SermonParagraphEntity> paragraphs,
    required String query,
    required List<int> matchIndices,
    required int currentMatchIndex,
    bool instantScroll = false,
  }) {
    if (!controller.hasClients ||
        matchIndices.isEmpty ||
        paragraphs.isEmpty ||
        currentMatchIndex < 0 ||
        currentMatchIndex >= matchIndices.length ||
        query.trim().isEmpty) {
      return false;
    }

    final paragraphIndex = matchIndices[currentMatchIndex];
    if (paragraphIndex < 0 || paragraphIndex >= paragraphs.length) {
      return false;
    }

    final occurrenceIndex = _currentOccurrenceForItemWithState(
      matchIndices: matchIndices,
      currentMatchIndex: currentMatchIndex,
      itemIndex: paragraphIndex,
    );
    if (occurrenceIndex == null) return false;

    final pattern = RegExp(query, caseSensitive: false);
    var totalChars = 0;
    var charsBeforeTargetParagraph = 0;
    for (var i = 0; i < paragraphs.length; i++) {
      final textLength = paragraphs[i].text.length;
      if (i < paragraphIndex) {
        charsBeforeTargetParagraph += textLength;
        if (i < paragraphs.length - 1) {
          charsBeforeTargetParagraph += 1;
        }
      }
      totalChars += textLength;
      if (i < paragraphs.length - 1) {
        totalChars += 1;
      }
    }
    if (totalChars <= 0) return false;

    final matches = pattern.allMatches(paragraphs[paragraphIndex].text).toList();
    if (matches.isEmpty) return false;
    final safeOccurrence = occurrenceIndex.clamp(0, matches.length - 1);
    final globalCharOffset =
        charsBeforeTargetParagraph + matches[safeOccurrence].start;
    final ratio = (globalCharOffset / totalChars).clamp(0.0, 1.0);
    final target = ratio * controller.position.maxScrollExtent;

    if (instantScroll) {
      controller.jumpTo(target);
    } else {
      controller.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
    return true;
  }

  void _computeSecondaryPaneMatches(String query, {bool scrollToMatch = true}) {
    final flowState = ref.read(sermonFlowProvider);
    final group = flowState.bmBibleGroup;
    final activeSecondary = group.tabs.isEmpty
        ? null
        : group.tabs[group.activeIndex.clamp(0, group.tabs.length - 1)];
    final texts = activeSecondary?.type == ReaderContentType.sermon
        ? _bmSecondaryParagraphs.map((paragraph) => paragraph.text).toList()
        : _bmCurrentVerses.map((verse) => verse.text).toList();
    final indices = _computeMatchIndices(
      texts,
      query,
    );
    setState(() {
      _secondaryMatchIndices = indices;
      _secondaryTotalMatches = indices.length;
      _secondaryCurrentMatchIndex = 0;
    });
    if (indices.isNotEmpty && scrollToMatch) {
      _scrollSecondaryPaneToCurrentMatch();
    }
  }

  void _navigateSecondaryPaneMatch(int direction) {
    if (_secondaryMatchIndices.isEmpty) return;
    setState(() {
      _secondaryCurrentMatchIndex =
          (_secondaryCurrentMatchIndex + direction) %
          _secondaryMatchIndices.length;
      if (_secondaryCurrentMatchIndex < 0) {
        _secondaryCurrentMatchIndex = _secondaryMatchIndices.length - 1;
      }
    });
    _scrollSecondaryPaneToCurrentMatch();
  }

  void _scrollSecondaryPaneToCurrentMatch() {
    if (_secondaryMatchIndices.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final flowState = ref.read(sermonFlowProvider);
      if (flowState.bmBibleGroup.tabs.isEmpty) return;
      final activeSecondary = flowState.bmBibleGroup.tabs[
        flowState.bmBibleGroup.activeIndex.clamp(
          0,
          flowState.bmBibleGroup.tabs.length - 1,
        )
      ];
      if (activeSecondary.type == ReaderContentType.sermon) {
        _scrollToSermonOccurrenceByState(
          controller: _splitSecondaryScrollController,
          paragraphs: _bmSecondaryParagraphs,
          query: _secondaryMiniSearchController.text,
          matchIndices: _secondaryMatchIndices,
          currentMatchIndex: _secondaryCurrentMatchIndex,
        );
        return;
      }
      final verseIndex = _secondaryMatchIndices[_secondaryCurrentMatchIndex];
      if (verseIndex < 0 || verseIndex >= _bmVerseKeys.length) return;
      final targetContext = _bmVerseKeys[verseIndex].currentContext;
      if (targetContext != null) {
        await Scrollable.ensureVisible(
          targetContext,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          alignment: 0.12,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        );
        return;
      }
      if (!_splitSecondaryScrollController.hasClients) return;
      final max = _splitSecondaryScrollController.position.maxScrollExtent;
      if (max <= 0 || _bmCurrentVerses.isEmpty) return;
      final fraction = (verseIndex / _bmCurrentVerses.length).clamp(0.0, 1.0);
      final target = fraction * max;
      _splitSecondaryScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
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

  void _scrollToParagraphIndex(
    int index, {
    int retryCount = 0,
    bool instantScroll = false,
  }) {
    if (index < 0 || _verseKeys.isEmpty || index >= _verseKeys.length) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final ensureDuration = instantScroll
          ? Duration.zero
          : const Duration(milliseconds: 300);
      final ctx = _verseKeys[index].currentContext;
      if (ctx != null) {
        await Scrollable.ensureVisible(
          ctx,
          duration: ensureDuration,
          curve: Curves.easeInOut,
          alignment: 0.12,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        );
        if (!mounted) return;
        _jumpAlignParagraphUnderBars(index);
        return;
      }
      if (_scrollController.hasClients) {
        final estimated = _estimatedOffsetForIndex(index);
        final current = _scrollController.offset;
        if ((estimated - current).abs() > 8) {
          if (instantScroll) {
            _scrollController.jumpTo(estimated);
          } else {
            await _scrollController.animateTo(
              estimated,
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
            );
          }
        }
      }
      if (retryCount >= 8) return;
      Future<void>.delayed(const Duration(milliseconds: 16), () {
        if (!mounted) return;
        _scrollToParagraphIndex(
          index,
          retryCount: retryCount + 1,
          instantScroll: instantScroll,
        );
      });
    });
  }

  void _applyInitialSearchFocus(ReaderTab tab) {
    if (_initialSearchScrollTabId == tab.id) return;
    final query = tab.initialSearchQuery;
    if (query == null || query.isEmpty || _currentParagraphs.isEmpty) return;

    _computeMatches(query, scrollToMatch: false);

    int? focusIndex;
    final targetNumber = tab.initialFocusParagraph;
    if (targetNumber != null) {
      focusIndex = _currentParagraphs.indexWhere(
        (p) => p.paragraphNumber == targetNumber,
      );
      if (focusIndex < 0) focusIndex = null;
    }

    if (focusIndex != null) {
      final exactMatchIndex = _matchVerseIndices.indexWhere(
        (idx) => idx == focusIndex,
      );
      if (exactMatchIndex != -1) {
        setState(() => _currentMatchIndex = exactMatchIndex);
        _initialSearchScrollTabId = tab.id;
        _scrollToCurrentMatch(instantScroll: true);
        return;
      }

      if (_matchVerseIndices.isNotEmpty) {
        // Some DB snippets can report a nearby paragraph number; choose the
        // closest actual match so the highlighted result is visible immediately.
        var nearestMatchListIndex = 0;
        var nearestDistance = (_matchVerseIndices.first - focusIndex).abs();
        for (var i = 1; i < _matchVerseIndices.length; i++) {
          final distance = (_matchVerseIndices[i] - focusIndex).abs();
          if (distance < nearestDistance) {
            nearestDistance = distance;
            nearestMatchListIndex = i;
          }
        }
        setState(() => _currentMatchIndex = nearestMatchListIndex);
        _initialSearchScrollTabId = tab.id;
        _scrollToCurrentMatch(instantScroll: true);
        return;
      }

      _initialSearchScrollTabId = tab.id;
      _scrollToParagraphIndex(focusIndex, instantScroll: true);
      return;
    }

    if (_matchVerseIndices.isNotEmpty) {
      _initialSearchScrollTabId = tab.id;
      _scrollToCurrentMatch(instantScroll: true);
    }
  }

  bool _hasParagraphContentChanged(List<SermonParagraphEntity> next) {
    if (_currentParagraphs.length != next.length) return true;
    for (var i = 0; i < next.length; i++) {
      final a = _currentParagraphs[i];
      final b = next[i];
      if (a.id != b.id ||
          a.paragraphNumber != b.paragraphNumber ||
          a.text != b.text) {
        return true;
      }
    }
    return false;
  }

  bool get _hasAnySelection {
    final textSelected = _activeSelectionText?.trim().isNotEmpty ?? false;
    return textSelected || _selectedVerseNumbers.isNotEmpty;
  }

  String _buildSermonSelectionFooter() {
    final flowState = ref.read(sermonFlowProvider);
    final activeTab = flowState.activeTab;
    final title = activeTab?.title ?? 'Sermon';

    // Try to extract a sermon code like 47-0412 from the title.
    final codeMatch = RegExp(r'\\b\\d{2}-\\d{4}\\b').firstMatch(title);
    final code = codeMatch?.group(0) ?? '';

    String footer = title;
    if (code.isNotEmpty && !title.contains(code)) {
      footer = '$title  $code';
    }

    if (_selectionFirstParagraph != null) {
      if (_selectionLastParagraph != null &&
          _selectionLastParagraph != _selectionFirstParagraph) {
        footer =
            '$footer Para-${_selectionFirstParagraph},${_selectionLastParagraph}';
      } else {
        footer = '$footer Para-${_selectionFirstParagraph}';
      }
    }

    return footer;
  }

  Future<void> _copyCurrentSelection() async {
    var payload = _activeSelectionText?.trim() ?? '';
    if (payload.isEmpty) {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      payload = data?.text?.trim() ?? '';
    }
    if (payload.isEmpty) return;

    final footer = _buildSermonSelectionFooter();
    final fullText = '$payload\n$footer';

    Clipboard.setData(ClipboardData(text: fullText));
    setState(() => _activeSelectionText = null);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selection copied'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  void _shareCurrentSelection() {
    final payload = _activeSelectionText?.trim() ?? '';
    if (payload.isEmpty) return;

    final footer = _buildSermonSelectionFooter();
    final fullText = '$payload\n$footer';

    final flowState = ref.read(sermonFlowProvider);
    final sermonTab = flowState.tabs.firstWhere(
      (t) => t.type == ReaderContentType.sermon,
      orElse: () => flowState.tabs.first,
    );
    final lang = ref.read(selectedSermonLangProvider);
    final sermonId = sermonTab.sermonId ?? '';
    final deepLink =
        'https://endtimebride.in/appshare/sermon?id=$sermonId&lang=$lang';

    SharePlus.instance.share(
      ShareParams(
        text: '$fullText\n\n🔗 Open in Bride Message App:\n$deepLink',
      ),
    );
    setState(() => _activeSelectionText = null);
  }

  // ── PDF generation (Sermon) ──────────────────────────────────────────────

  Future<Map<String, dynamic>> _buildSermonPdfPayload() async {
    final flowState = ref.read(sermonFlowProvider);
    final activeTab = flowState.activeTab;
    final lang = ref.read(selectedSermonLangProvider);
    final typography = ref.read(typographyProvider(lang));

    SermonEntity sermon;

    if (activeTab?.sermonId != null) {
      try {
        // Load sermon directly from the repository instead of via FutureProvider
        final repo = await ref.read(sermonRepositoryProvider.future);
        final loaded = await repo.getSermonById(activeTab!.sermonId!);

        sermon =
            loaded ??
            SermonEntity(
              id: activeTab.sermonId!,
              title: activeTab.title,
              language: lang,
            );
      } catch (_) {
        sermon = SermonEntity(
          id: activeTab!.sermonId!,
          title: activeTab.title,
          language: lang,
        );
      }
    } else {
      sermon = SermonEntity(
        id: activeTab?.title ?? 'sermon',
        title: activeTab?.title ?? 'Sermon',
        language: lang,
      );
    }

    final paragraphs = _currentParagraphs
        .asMap()
        .entries
        .map((entry) => <String, dynamic>{
              'paragraphNumber': entry.value.paragraphNumber ?? (entry.key + 1),
              'text': entry.value.text,
            })
        .toList(growable: false);

    return <String, dynamic>{
      'type': 'sermon',
      'lang': lang == 'ta' ? 'ta' : 'en',
      'title': activeTab?.title ?? 'Sermon',
      'meta': <String, dynamic>{
        'sermonId': sermon.id,
        'location': sermon.location,
        'date': sermon.date,
        'duration': sermon.duration,
      },
      'settings': <String, dynamic>{
        'fontSize': typography.fontSize,
        'lineHeight': typography.lineHeight,
        'titleFontSize': typography.titleFontSize,
        'fontFamily': typography.resolvedFontFamily ?? '',
      },
      'content': <String, dynamic>{'paragraphs': paragraphs},
    };
  }

  Future<Uint8List> _fetchSermonPdfBytes() async {
    final payload = await _buildSermonPdfPayload();
    final bytes = await _pdfExportService.export(payload);
    return bytes;
  }

  String _sanitizePdfName(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[<>:"/\\\\|?*]'), '-').trim();
    return cleaned.isEmpty ? 'Document' : cleaned;
  }

  String _resolvePdfTitle({
    required String rawTitle,
    required String langCode,
  }) {
    if (langCode == 'ta') {
      return normalizeTamil(rawTitle.trim());
    }
    return rawTitle.trim();
  }

  Future<void> _withPdfProgress(Future<void> Function() task) async {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );
    try {
      await task();
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  Future<void> _printSermonPdf() async {
    await _withPdfProgress(() async {
      late final Uint8List bytes;
      try {
        bytes = await _fetchSermonPdfBytes();
      } on PdfExportException catch (e) {
        if (!mounted) return;
        final message = e.isNetworkIssue
            ? 'PDF export requires internet connection.'
            : e.message;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
        return;
      }
      final activeTab = ref.read(sermonFlowProvider).activeTab;
      final rawTitle = activeTab?.title ?? 'Sermon';
      final langCode = (activeTab?.sermonLang ??
                  ref.read(selectedSermonLangProvider) ??
                  'en') ==
              'ta'
          ? 'ta'
          : 'en';
      final safeTitle = _sanitizePdfName(
        _resolvePdfTitle(rawTitle: rawTitle, langCode: langCode),
      );
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: safeTitle);
    });
  }

  Future<void> _downloadSermonPdf() async {
    await _withPdfProgress(() async {
      late final Uint8List bytes;
      try {
        bytes = await _fetchSermonPdfBytes();
      } on PdfExportException catch (e) {
        if (!mounted) return;
        final message = e.isNetworkIssue
            ? 'PDF export requires internet connection.'
            : e.message;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
        return;
      }

      final activeTab = ref.read(sermonFlowProvider).activeTab;
      final rawTitle = activeTab?.title ?? 'Sermon';
      final langCode = (activeTab?.sermonLang ??
                  ref.read(selectedSermonLangProvider) ??
                  'en') ==
              'ta'
          ? 'ta'
          : 'en';
      final safeTitle = _sanitizePdfName(
        _resolvePdfTitle(rawTitle: rawTitle, langCode: langCode),
      );
      final filename = '$safeTitle.pdf';

      // Desktop: native Save dialog + Open folder.
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final savedPath = await DesktopFileSaver.savePdf(
          suggestedName: filename,
          bytes: bytes,
        );

        if (!mounted || savedPath == null) return;

        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('PDF saved'),
            content: Text('Saved to:\n$savedPath'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  DesktopFileSaver.revealInExplorer(savedPath);
                },
                child: const Text('Open folder'),
              ),
            ],
          ),
        );
        return;
      }

      // Mobile: save to app documents directory and allow direct open.
      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/$filename';
      final file = File(filePath);
      await file.writeAsBytes(bytes, flush: true);

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('PDF saved'),
          content: Text('Saved inside app documents:\n$filePath'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                try {
                  await OpenFilex.open(filePath);
                } catch (_) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'PDF saved to:\n$filePath\n\nPlease open it from your file manager.',
                      ),
                    ),
                  );
                }
              },
              child: const Text('Open file'),
            ),
          ],
        ),
      );
    });
  }

  String _sanitizeTextName(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[<>:"/\\\\|?*]'), '-').trim();
    return cleaned.isEmpty ? 'Document' : cleaned;
  }

  String _buildSermonText() {
    if (_currentParagraphs.isEmpty) return '';
    return _currentParagraphs
        .map((p) {
          final prefix = (p.paragraphNumber != null)
              ? '${p.paragraphNumber} '
              : '';
          return '$prefix${p.text}';
        })
        .join('\n\n');
  }

  Future<void> _downloadSermonText() async {
    await _withPdfProgress(() async {
      final text = _buildSermonText();
      if (text.isEmpty) return;
      final bytes = utf8.encode(text);

      final rawTitle =
          ref.read(sermonFlowProvider).activeTab?.title ?? 'Sermon';
      final safeTitle = _sanitizeTextName(rawTitle);
      final filename = '$safeTitle.txt';

      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final savedPath = await DesktopFileSaver.saveText(
          suggestedName: filename,
          bytes: bytes,
        );
        if (!mounted || savedPath == null) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Text saved'),
            content: Text('Saved to:\n$savedPath'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  DesktopFileSaver.revealInExplorer(savedPath);
                },
                child: const Text('Open folder'),
              ),
            ],
          ),
        );
        return;
      }

      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/$filename';
      final file = File(filePath);
      await file.writeAsBytes(bytes, flush: true);

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Text saved'),
          content: Text('Saved inside app documents:\n$filePath'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                try {
                  await OpenFilex.open(filePath);
                } catch (_) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Text saved to:\n$filePath\n\nPlease open it from your file manager.',
                      ),
                    ),
                  );
                }
              },
              child: const Text('Open file'),
            ),
          ],
        ),
      );
    });
  }

  void _openCodList(BuildContext context) {
    final lang = ref.read(selectedSermonLangProvider);
    if (lang == 'ta') {
      ref.read(selectedSermonLangProvider.notifier).setLang('ta');
      final uri = Uri(
        path: '/sermons',
        queryParameters: const {
          'title': 'COD - கேள்விகளும் பதில்களும்',
          'mode': 'cod',
          'lang': 'ta',
        },
      );
      context.push(uri.toString());
    } else {
      ref.read(selectedSermonLangProvider.notifier).setLang('en');
      final uri = Uri(
        path: '/sermons',
        queryParameters: const {
          'title': 'COD - Question and Answers',
          'mode': 'cod',
          'lang': 'en',
        },
      );
      context.push(uri.toString());
    }
  }

  void _openSevenSealsList(BuildContext context) {
    final lang = ref.read(selectedSermonLangProvider);
    if (lang == 'ta') {
      ref.read(selectedSermonLangProvider.notifier).setLang('ta');
      final uri = Uri(
        path: '/sermons',
        queryParameters: const {
          'mode': 'sevenSeals',
          'title': '7 முத்திரைகள்',
          'lang': 'ta',
        },
      );
      context.push(uri.toString());
    } else {
      ref.read(selectedSermonLangProvider.notifier).setLang('en');
      final uri = Uri(
        path: '/sermons',
        queryParameters: const {
          'mode': 'sevenSeals',
          'title': '7 Seals',
          'lang': 'en',
        },
      );
      context.push(uri.toString());
    }
  }

  void _enterSearchMode() {
    setState(() {
      _isSearching = true;
      _fabExpanded = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchFieldFocusNode.requestFocus();
      final textLength = _searchController.text.length;
      _searchController.selection = TextSelection.fromPosition(
        TextPosition(offset: textLength),
      );
    });
  }

  // ── Highlighted text spans ────────────────────────────────────────────────

  List<TextSpan> _buildHighlightedSpans(
    String text,
    TextStyle baseStyle,
    TextStyle highlightStyle,
    TextStyle currentMatchStyle, {
    required String query,
    required bool enabled,
    int? currentOccurrenceIndex,
  }) {
    if (!enabled || query.isEmpty) {
      return [TextSpan(text: text, style: baseStyle)];
    }
    final matches = RegExp(
      query,
      caseSensitive: false,
    ).allMatches(text).toList();
    if (matches.isEmpty) return [TextSpan(text: text, style: baseStyle)];

    final spans = <TextSpan>[];
    int start = 0;
    int occurrenceCounter = 0;
    for (final match in matches) {
      if (match.start > start) {
        spans.add(
          TextSpan(text: text.substring(start, match.start), style: baseStyle),
        );
      }
      final isCurrent = occurrenceCounter == currentOccurrenceIndex;
      spans.add(
        TextSpan(
          text: text.substring(match.start, match.end),
          style: isCurrent ? currentMatchStyle : baseStyle,
        ),
      );
      occurrenceCounter++;
      start = match.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: baseStyle));
    }
    return spans;
  }

  Widget _buildMatchMarkers(
    int itemCount,
    List<int> matchIndices,
    int? currentItemIndex, {
    bool enabled = true,
  }) {
    if (!enabled || matchIndices.isEmpty || itemCount <= 1) {
      return const SizedBox.shrink();
    }
    final markers = matchIndices.toSet().toList()..sort();
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight;
          const markerWidth = 4.0;
          const markerHeight = 6.0;
          return Stack(
            children: [
              for (final idx in markers)
                Positioned(
                  right: 0,
                  top: ((idx / (itemCount - 1)) * (height - markerHeight))
                      .clamp(0.0, height - markerHeight),
                  child: Container(
                    width: markerWidth,
                    height: markerHeight,
                    decoration: BoxDecoration(
                      color: idx == currentItemIndex
                          ? Colors.orange.shade700
                          : Colors.yellow.shade600,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    final flowState = ref.watch(sermonFlowProvider);
    final activeTab = flowState.activeTab;
    final sermonLang = ref.watch(selectedSermonLangProvider);
    final bibleLangFallback = ref.watch(selectedBibleLangProvider);
    final readerTypographyLang = activeTab?.type == ReaderContentType.bible
        ? (activeTab?.bibleLang ?? bibleLangFallback)
        : sermonLang;
    final typographyState = ref.watch(typographyProvider(readerTypographyLang));

    final isFullscreen = typographyState.isFullscreen;
    final openedFromSearch = activeTab?.openedFromSearch ?? false;

    // Clear search state if tab changed and doesn't have initialSearchQuery
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final activeId = activeTab?.id;
      final tabChanged = activeId != _lastActiveTabId;
      if (_isSearching && tabChanged && activeTab?.initialSearchQuery == null) {
        setState(() {
          _isSearching = false;
          _searchController.clear();
          _clearMatches();
          _lastSearchActivatedTabId = null;
        });
      }
      _lastActiveTabId = activeId;

      if (flowState.bmMode && flowState.bmBibleGroup.tabs.isEmpty) {
        _ensureBmDefaultBibleTab();
      }
    });

    final baseTheme = Theme.of(context);
    final selectionTheme = baseTheme.textSelectionTheme.copyWith(
      selectionColor: baseTheme.colorScheme.primary.withOpacity(0.35),
      selectionHandleColor: baseTheme.colorScheme.primary,
    );

    // Dismiss FAB when tapping elsewhere.
    return Theme(
      data: baseTheme.copyWith(textSelectionTheme: selectionTheme),
      child: Shortcuts(
        shortcuts: {
          LogicalKeySet(LogicalKeyboardKey.enter): const _NextMatchIntent(),
          LogicalKeySet(LogicalKeyboardKey.shift, LogicalKeyboardKey.enter):
              const _PrevMatchIntent(),
        },
        child: Actions(
          actions: {
            _NextMatchIntent: CallbackAction<_NextMatchIntent>(
              onInvoke: (intent) {
                if (_isSearching && !_searchAllSermons && _totalMatches > 0) {
                  _navigateToMatch(1);
                }
                return null;
              },
            ),
            _PrevMatchIntent: CallbackAction<_PrevMatchIntent>(
              onInvoke: (intent) {
                if (_isSearching && !_searchAllSermons && _totalMatches > 0) {
                  _navigateToMatch(-1);
                }
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: GestureDetector(
              behavior: HitTestBehavior.deferToChild,
              onTap: () {
                if (_fabExpanded) setState(() => _fabExpanded = false);
              },
              child: Scaffold(
                appBar: isFullscreen
                    ? null
                    : (_isSearching
                          ? _buildSearchAppBar(
                              context,
                              openedFromSearch: openedFromSearch,
                            )
                          : _buildDefaultAppBar(
                              context,
                              activeTab,
                              flowState,
                              typographyState,
                              openedFromSearch: openedFromSearch,
                            )),
                body: activeTab == null
                    ? const Center(
                        child: Text('No sermon loaded. Return to sermon list.'),
                      )
                    : _buildBody(
                        activeTab,
                        typographyState,
                        flowState,
                        isFullscreen,
                        openedFromSearch,
                      ),
                floatingActionButton:
                    (activeTab == null ||
                        isFullscreen ||
                        _isSearching ||
                        _hasAnySelection)
                    ? null
                    : _buildSpeedDial(),
                floatingActionButtonLocation:
                    FloatingActionButtonLocation.endFloat,
                bottomNavigationBar:
                    (!isFullscreen &&
                        !_hideBottomTabs &&
                        flowState.tabs.isNotEmpty &&
                        !_isSearching &&
                        !flowState.bmMode)
                    ? _buildBottomTabBar(context, flowState)
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Body wrapper ─────────────────────────────────────────────────────────

  Widget _buildBody(
    ReaderTab activeTab,
    TypographySettings typography,
    SermonFlowState flowState,
    bool isFullscreen,
    bool openedFromSearch,
  ) {
    // When searching, inject the scope chips row (and type chips for All Sermons)
    // above the content/results.
    if (_isSearching && !isFullscreen) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!openedFromSearch) ...[
            _buildSearchChipsRow(),
            if (_searchAllSermons) _buildSearchTypeChipsRow(),
          ],
          Expanded(
            child: _searchAllSermons
                ? _buildAllSermonResults()
                : _buildTabContent(activeTab, typography, flowState),
          ),
        ],
      );
    }

    final content = _buildTabContent(activeTab, typography, flowState);
    Widget contentWithBar = Column(
      children: [
        Expanded(child: content),
        SelectionActionBar(
          isVisible: (_activeSelectionText?.trim().isNotEmpty ?? false),
          selectedText: _activeSelectionText,
          onCopy: _copyCurrentSelection,
          onShare: _shareCurrentSelection,
          onDismiss: () {
            setState(() => _activeSelectionText = null);
          },
        ),
      ],
    );

    if (isFullscreen) {
      return Stack(
        children: [
          contentWithBar,
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
                      ref.read(typographyGlobalProvider.notifier).toggleFullscreen(),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(
                      Icons.fullscreen_exit,
                      color: Colors.white,
                      size: 22,
                    ),
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
          contentWithBar,
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
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.expand_more,
                            color: Colors.white,
                            size: 18,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Show Tabs',
                            style: TextStyle(color: Colors.white, fontSize: 13),
                          ),
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
    return contentWithBar;
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

  AppBar _buildSearchAppBar(
    BuildContext context, {
    required bool openedFromSearch,
  }) {
    return AppBar(
      toolbarHeight: kToolbarHeight,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () {
          if (openedFromSearch) {
            // When this tab was opened from Common Search, the back button
            // should return to the search page instead of just exiting
            // in-page search mode.
            context.pop();
            return;
          }
          setState(() {
            _isSearching = false;
            _searchAllSermons = false;
            _searchController.clear();
            _clearMatches();
            _allSermonResults = [];
            _allSermonHasMore = false;
            _allSermonSearchLoadingMore = false;
            _lastSearchActivatedTabId = null;
          });
        },
      ),
      title: TextField(
        focusNode: _searchFieldFocusNode,
        controller: _searchController,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'Search in content...',
          border: InputBorder.none,
          filled: false,
          fillColor: Colors.transparent,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 8),
        ),
        onSubmitted: (_) {
          if (!_searchAllSermons && _totalMatches > 0) {
            _navigateToMatch(1);
            return;
          }
          if (_searchAllSermons) {
            _scheduleAllSermonSearch(immediate: true);
          }
        },
        onChanged: (val) {
          _computeMatches(val);
          if (_searchAllSermons) _scheduleAllSermonSearch();
        },
      ),
      actions: [
        if (_searchController.text.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              _searchController.clear();
              _computeMatches('');
              if (_searchAllSermons) {
                setState(() {
                  _allSermonResults = [];
                  _allSermonHasMore = false;
                  _allSermonSearchLoading = false;
                  _allSermonSearchLoadingMore = false;
                });
              }
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
            onPressed: _totalMatches == 0 ? null : () => _navigateToMatch(-1),
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: _totalMatches == 0 ? null : () => _navigateToMatch(1),
          ),
        ],
        // "All Sermons" mode: show loading indicator while searching.
        if (_searchAllSermons &&
            (_allSermonSearchLoading || _allSermonSearchLoadingMore))
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
                _allSermonHasMore = false;
                _allSermonSearchLoadingMore = false;
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
              setState(() {
                _searchAllSermons = true;
                _allSermonResults = [];
                _allSermonHasMore = false;
              });
              _scheduleAllSermonSearch(immediate: true);
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
              _scheduleAllSermonSearch(immediate: true);
            },
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('Exact Phrase'),
            selected: _sermonSearchType == SearchType.exact,
            onSelected: (_) {
              setState(() => _sermonSearchType = SearchType.exact);
              _scheduleAllSermonSearch(immediate: true);
            },
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('Any Word'),
            selected: _sermonSearchType == SearchType.any,
            onSelected: (_) {
              setState(() => _sermonSearchType = SearchType.any);
              _scheduleAllSermonSearch(immediate: true);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSplitViewPopupMenu(
    BuildContext context,
    BoxConstraints constraints,
    bool splitEnabled,
    ThemeData theme, {
    String? label,
  }) {
    final icon = Icon(
      Icons.splitscreen,
      size: constraints.maxWidth >= 900 ? 28 : 24,
      color: splitEnabled ? theme.colorScheme.primary : null,
    );

    if (label != null) {
      return PopupMenuButton<String>(
        tooltip: label,
        onSelected: _onSermonSplitViewSourceSelected,
        itemBuilder: (context) => _buildSplitViewItems(constraints),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: constraints.maxWidth >= 900 ? 15 : 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return PopupMenuButton<String>(
      tooltip: 'Split View',
      icon: icon,
      onSelected: _onSermonSplitViewSourceSelected,
      itemBuilder: (context) => _buildSplitViewItems(constraints),
    );
  }

  List<PopupMenuEntry<String>> _buildSplitViewItems(
    BoxConstraints constraints,
  ) {
    final itemStyle = TextStyle(
      fontSize: constraints.maxWidth >= 900 ? 16 : 14,
    );
    return [
      PopupMenuItem<String>(
        value: 'bible_en',
        child: Text('Bible English', style: itemStyle),
      ),
      PopupMenuItem<String>(
        value: 'bible_ta',
        child: Text('Bible Tamil', style: itemStyle),
      ),
      PopupMenuItem<String>(
        value: 'sermon_en',
        child: Text('Sermon English', style: itemStyle),
      ),
      PopupMenuItem<String>(
        value: 'sermon_ta',
        child: Text('Sermon Tamil', style: itemStyle),
      ),
      const PopupMenuDivider(),
      PopupMenuItem<String>(
        value: 'split_off',
        child: Text('Disable Split View', style: itemStyle),
      ),
    ];
  }

  Future<void> _onSermonSplitViewSourceSelected(String value) async {
    if (value == 'split_off') {
      ref.read(sermonFlowProvider.notifier).setBmMode(false);
      return;
    }

    // Toggle BM mode if not enabled.
    if (!ref.read(sermonFlowProvider).bmMode) {
      ref.read(sermonFlowProvider.notifier).setBmMode(true);
    }

    if (value == 'bible_ta' || value == 'bible_en') {
      final lang = value == 'bible_ta' ? 'ta' : 'en';
      await _openQuickNav(forcedInitialLang: lang);
    } else if (value == 'sermon_ta' || value == 'sermon_en') {
      // For now, we open the quick nav for sermons.
      // Language switching in SermonQuickNavSheet follows the global sermon lang.
      await _openSermonQuickNav();
    }
  }

  AppBar _buildDefaultAppBar(
    BuildContext context,
    ReaderTab? activeTab,
    SermonFlowState flowState,
    TypographySettings typography, {
    bool openedFromSearch = false,
  }) {
    final theme = Theme.of(context);
    final hasSelection = _selectedVerseNumbers.isNotEmpty;
    final isOnBibleTab = flowState.activeTab?.type == ReaderContentType.bible;
    final bibleReadLang =
        (activeTab?.bibleLang ?? ref.watch(selectedBibleLangProvider)) ?? 'en';
    final chapterNo = activeTab?.chapter;
    final chapterLabel = chapterNo == null
        ? ''
        : (bibleReadLang == 'ta'
              ? 'அதிகாரம் $chapterNo'
              : 'Chapter $chapterNo');
    final isSermonTab =
        flowState.activeTab?.type == ReaderContentType.sermon &&
        activeTab?.sermonId != null;
    final isWideScreen = MediaQuery.sizeOf(context).width >= 900;

    // Subtitle metadata for the sermon tab.
    Widget titleWidget;
    if (!isOnBibleTab && activeTab?.sermonId != null) {
      final sermonAsync = ref.watch(sermonByIdProvider(activeTab!.sermonId!));
      final SermonEntity? sermon = sermonAsync.maybeWhen(
        data: (v) => v,
        orElse: () => null,
      );
      final subtitle = sermon == null
          ? null
          : [
              sermon.id,
              if (sermon.year != null) sermon.year.toString(),
              if (sermon.duration != null && sermon.duration!.isNotEmpty)
                sermon.duration!,
            ].join(' • ');

      // If the sermon has loaded but the tab title is still "Loading...",
      // quickly update it so the UI and Bottom Tabs reflect the real title.
      if (sermon != null && activeTab.title == 'Loading...') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref
              .read(sermonFlowProvider.notifier)
              .updateActiveTabTitle(sermon.title);
        });
      }

      titleWidget = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            activeTab.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: (isWideScreen ? 24.0 : 18.0) + (typography.titleFontSize - (isWideScreen ? 18.0 : 13.0)).clamp(0, 10),
            ),
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
          mainAxisSize: MainAxisSize.max,
          children: [
            Expanded(
              child: Text(
                activeTab?.title ?? 'Bible Reference',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      );
    } else {
      titleWidget = Text(
        activeTab?.title ?? 'Sermon',
        overflow: TextOverflow.ellipsis,
      );
    }

    return AppBar(
      toolbarHeight: isWideScreen ? 64.0 : (isOnBibleTab ? 72.0 : 92.0),
      titleSpacing: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.pop(),
      ),
      title: LayoutBuilder(
        builder: (context, constraints) {
          final showPcChips = constraints.maxWidth >= 900 && isSermonTab;
          if (!showPcChips) {
            return SizedBox(width: constraints.maxWidth, child: titleWidget);
          }

          final lang = ref.watch(selectedSermonLangProvider);
          final codLabel = lang == 'ta' ? 'COD Tamil' : 'COD English';
          final sealsLabel = lang == 'ta' ? 'ஏழு முத்திரைகள்' : 'Seven Seals';

          return Row(
            mainAxisAlignment: MainAxisAlignment.start,
            mainAxisSize: MainAxisSize.max,
            children: [
              Flexible(child: titleWidget),
              const SizedBox(width: 24),
              // Split View Controls
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8.0,
                  vertical: 2.0,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: theme.colorScheme.surfaceVariant.withAlpha(80),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSplitViewPopupMenu(
                      context,
                      constraints,
                      flowState.bmMode,
                      theme,
                      label: 'Split View',
                    ),
                    if (flowState.bmMode) ...[
                      const SizedBox(width: 8),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                          textStyle:
                              const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onPressed: () {
                          ref
                              .read(sermonFlowProvider.notifier)
                              .setBmMode(false);
                        },
                        child: const Text('Disable Split View'),
                      ),
                    ],
                  ],
                ),
              ),
              const Spacer(),
              const SizedBox(width: 16),
              Wrap(
                spacing: 12,
                children: [
                  _AppBarChip(
                    label: codLabel,
                    icon: Icons.article_outlined,
                    onTap: () => _openCodList(context),
                    isWide: true,
                  ),
                  _AppBarChip(
                    label: sealsLabel,
                    icon: Icons.layers_outlined,
                    onTap: () => _openSevenSealsList(context),
                    isWide: true,
                  ),
                ],
              ),
            ],
          );
        },
      ),
      actions: [
        if (hasSelection && isOnBibleTab) ...[
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _shareSelectedVerses,
          ),
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () => setState(() => _selectedVerseNumbers.clear()),
          ),
        ] else ...[
          if (isOnBibleTab || isSermonTab)
            IconButton(
              tooltip: 'Decrease font size',
              icon: const Text(
                'A-',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              onPressed: () => _adjustReaderFontSize(-1),
            ),
          if (isOnBibleTab || isSermonTab)
            IconButton(
              tooltip: 'Increase font size',
              icon: const Text(
                'A+',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              onPressed: () => _adjustReaderFontSize(1),
            ),
          const HelpButton(topicId: 'reader'),
          if (!openedFromSearch) ...[
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: _enterSearchMode,
            ),
            IconButton(
              icon: const Icon(Icons.home),
              onPressed: () => context.go('/'),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => ReaderSettingsSheet.show(context),
          ),
        ],
      ],
      bottom: isOnBibleTab
          ? PreferredSize(
              preferredSize: Size.fromHeight(
                MediaQuery.sizeOf(context).width >= 900 ? 44 : 40,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isDesktopNav = constraints.maxWidth >= 900;
                  final iconSize = isDesktopNav ? 24.0 : 22.0;
                  final labelSize = isDesktopNav ? 15.0 : 14.0;
                  final buttonHeight = isDesktopNav ? 42.0 : 38.0;
                  final horizontalPadding = isDesktopNav ? 18.0 : 12.0;

                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.symmetric(
                              horizontal: horizontalPadding,
                            ),
                            minimumSize: Size(0, buttonHeight),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () => _openAdjacentBmBiblePassage(-1),
                          icon: Icon(Icons.chevron_left, size: iconSize),
                          label: Text(
                            'Previous',
                            style: TextStyle(
                              fontSize: labelSize,
                              height: 1.1,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              chapterLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: labelSize,
                                height: 1.1,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.symmetric(
                              horizontal: horizontalPadding,
                            ),
                            minimumSize: Size(0, buttonHeight),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () => _openAdjacentBmBiblePassage(1),
                          iconAlignment: IconAlignment.end,
                          icon: Icon(Icons.chevron_right, size: iconSize),
                          label: Text(
                            'Next',
                            style: TextStyle(
                              fontSize: labelSize,
                              height: 1.1,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            )
          : null,
    );
  }

  // ── Tab content ───────────────────────────────────────────────────────────

  Widget _buildLoadError(Object err) {
    final message = err.toString();
    final lower = message.toLowerCase();
    final isFileError = err is FileSystemException;
    final isMissingBible =
        lower.contains('database file not found') &&
        lower.contains('bible_') &&
        lower.contains('.db');
    final isMissingSermon =
        lower.contains('database file not found') &&
        lower.contains('sermons_') &&
        lower.contains('.db');
    final canImport = isFileError && (isMissingBible || isMissingSermon);

    final title = isMissingBible
        ? 'Bible database is not installed'
        : isMissingSermon
        ? 'Sermon database is not installed'
        : 'Failed to load content';
    final details = isMissingBible
        ? 'Import Tamil/English Bible database to continue.'
        : isMissingSermon
        ? 'Import Tamil/English sermons database to continue.'
        : message;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 10),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(details, textAlign: TextAlign.center),
            if (canImport) ...[
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
          ],
        ),
      ),
    );
  }

  Widget _buildMissingDbPrompt({
    required String title,
    required String details,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 10),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(details, textAlign: TextAlign.center),
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

  Widget _buildTabContent(
    ReaderTab tab,
    TypographySettings typography,
    SermonFlowState flowState,
  ) {
    // Bible reference tab
    if (tab.type == ReaderContentType.bible &&
        tab.book != null &&
        tab.chapter != null) {
      final lang =
          (tab.bibleLang ?? ref.watch(selectedBibleLangProvider)) ?? 'en';
      final bibleDbExists = ref.watch(bibleDatabaseExistsByLangProvider(lang));
      if (bibleDbExists.maybeWhen(
        data: (exists) => !exists,
        orElse: () => false,
      )) {
        return _buildMissingDbPrompt(
          title: 'Bible database is not installed',
          details: 'Import Tamil/English Bible database to continue.',
        );
      }

      final asyncVerses = ref.watch(chapterVersesProvider(tab));
      return asyncVerses.when(
        data: (verses) {
          if (_currentVerses != verses) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() {
                _currentVerses = verses;
                _verseKeys = List.generate(verses.length, (_) => GlobalKey());
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
                    Scrollable.ensureVisible(
                      ctx,
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeInOut,
                      alignment: 0.2,
                    );
                  }
                });
              }
            });
          }

          if (verses.isEmpty) {
            return const Center(
              child: Text('No verses found in this chapter.'),
            );
          }

          final cs = Theme.of(context).colorScheme;
          final baseStyle =
              Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontSize: typography.fontSize,
                height: typography.lineHeight,
                fontFamily: typography.resolvedFontFamily,
              ) ??
              const TextStyle();
          final highlightStyle = baseStyle;
          final currentMatchStyle = TextStyle(
            backgroundColor: Colors.yellow.shade300,
            color: Colors.black,
            fontWeight: FontWeight.bold,
          );

          final currentItemIndex = _matchVerseIndices.isNotEmpty
              ? _matchVerseIndices[_currentMatchIndex]
              : null;

          return Stack(
            children: [
              ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                itemCount: verses.length,
                itemBuilder: (context, index) {
                  final verse = verses[index];
                  final isSelected = _selectedVerseNumbers.contains(
                    verse.verse,
                  );
                  final key = index < _verseKeys.length
                      ? _verseKeys[index]
                      : GlobalKey();

                  final currentOccurrence = _currentOccurrenceForItem(index);

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
                        horizontal: 6,
                        vertical: 4,
                      ),
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
                              query: _searchController.text,
                              enabled: _isSearching && !_searchAllSermons,
                              currentOccurrenceIndex: currentOccurrence,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: 6,
                    child: _buildMatchMarkers(
                      verses.length,
                      _matchVerseIndices,
                      currentItemIndex,
                      enabled: _isSearching,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => _buildLoadError(err),
      );
    }

    // Sermon tab (index 0)
    if (tab.type == ReaderContentType.sermon && tab.sermonId != null) {
      final sermonLang = ref.watch(selectedSermonLangProvider);
      final sermonDbExists = ref.watch(
        sermonDatabaseExistsProvider(sermonLang),
      );
      if (sermonDbExists.maybeWhen(
        data: (exists) => !exists,
        orElse: () => false,
      )) {
        return _buildMissingDbPrompt(
          title: 'Sermon database is not installed',
          details: 'Import Tamil/English sermons database to continue.',
        );
      }

      final asyncParagraphs = ref.watch(
        sermonParagraphsProvider(tab.sermonId!),
      );
      return asyncParagraphs.when(
        data: (paragraphs) {
          if (paragraphs.isEmpty) {
            return const Center(
              child: Text('No paragraphs found for this sermon.'),
            );
          }

          // Cache paragraphs and rebuild keys / match indices when content changes.
          if (_hasParagraphContentChanged(paragraphs)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() {
                _currentParagraphs = paragraphs;
                _verseKeys = List.generate(
                  paragraphs.length,
                  (_) => GlobalKey(),
                );
                if (_isSearching &&
                    !_searchAllSermons &&
                    _searchController.text.isNotEmpty) {
                  _computeMatches(_searchController.text);
                } else {
                  _clearMatches();
                }
                if (_primaryMiniSearchActive &&
                    _primaryMiniSearchController.text.trim().isNotEmpty) {
                  _computePrimaryPaneMatches(
                    _primaryMiniSearchController.text,
                    scrollToMatch: false,
                  );
                } else {
                  _primaryMatchIndices = [];
                  _primaryTotalMatches = 0;
                  _primaryCurrentMatchIndex = 0;
                }
              });
            });
          }

          // Auto-activate search if initial query was provided
          if (tab.initialSearchQuery != null &&
              !_isSearching &&
              _lastSearchActivatedTabId != tab.id) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() {
                _isSearching = true;
                _searchAllSermons = false;
                _searchController.text = tab.initialSearchQuery!;
                _lastSearchActivatedTabId = tab.id;
              });
              _applyInitialSearchFocus(tab);
            });
          }

          final cs = Theme.of(context).colorScheme;
          return Column(
            children: [
              _buildSermonNavRow(flowState),
              Expanded(
                child: flowState.bmMode
                    ? _buildBmSplitContent(
                        flowState: flowState,
                        typography: typography,
                        sermonParagraphs: paragraphs,
                        colorScheme: cs,
                      )
                    : _buildSermonParagraphList(paragraphs, typography, cs),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => _buildLoadError(err),
      );
    }

    return Center(child: Text('Unsupported content type for ${tab.title}...'));
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

    final showFooter = _allSermonHasMore || _allSermonSearchLoadingMore;

    return ListView.builder(
      itemCount: _allSermonResults.length + (showFooter ? 1 : 0),
      padding: const EdgeInsets.only(bottom: 16),
      itemBuilder: (context, i) {
        if (i >= _allSermonResults.length) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Center(
              child: _allSermonSearchLoadingMore
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : FilledButton.tonal(
                      onPressed: _loadMoreAllSermons,
                      child: const Text('Load more'),
                    ),
            ),
          );
        }
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
            borderRadius: BorderRadius.circular(12),
          ),
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
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.home_outlined,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
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
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
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

  Widget _buildSermonNavRow(SermonFlowState flowState) {
    if (flowState.bmMode) return const SizedBox.shrink();
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
        mainAxisAlignment: flowState.bmMode
            ? MainAxisAlignment.center
            : MainAxisAlignment.spaceBetween,
        children: [
          if (!flowState.bmMode)
            TextButton.icon(
              icon: const Icon(Icons.chevron_left, size: 18),
              label: const Text('Previous'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => _openAdjacentSermon(-1),
            ),
          if (!_isSearching && !flowState.bmMode)
            const SizedBox.shrink(), // Placeholder since we removed Split View from here
          if (!flowState.bmMode)
            TextButton.icon(
              icon: const Icon(Icons.chevron_right, size: 18),
              label: const Text('Next'),
              iconAlignment: IconAlignment.end,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => _openAdjacentSermon(1),
            ),
        ],
      ),
    );
  }

  // ── Bottom tab bar ────────────────────────────────────────────────────────

  Widget _buildBottomTabBar(BuildContext context, SermonFlowState state) {
    final theme = Theme.of(context);
    final lang = ref.watch(selectedSermonLangProvider);
    final typography = ref.watch(typographyProvider(lang));
    final activeTab = state.activeTab;
    final isOnBibleTab = activeTab?.type == ReaderContentType.bible;
    final visibleIndices = <int>[];
    for (var i = 0; i < state.tabs.length; i++) {
      final tab = state.tabs[i];
      if (tab.type == ReaderContentType.sermon) {
        visibleIndices.add(i);
      }
    }
    return Material(
      elevation: 8,
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: theme.colorScheme.outlineVariant.withAlpha(80),
              ),
            ),
          ),
          child: SizedBox(
            height: 50,
            child: Row(
              children: [
                // Scrollable tabs
                Expanded(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: visibleIndices.length,
                    itemBuilder: (context, index) {
                      final actualIndex = visibleIndices[index];
                      final tab = state.tabs[actualIndex];
                      final isActive = actualIndex == state.activeTabIndex;
                      final isSermonTab = tab.type == ReaderContentType.sermon;

                      return GestureDetector(
                        onTap: () {
                          ref
                              .read(sermonFlowProvider.notifier)
                              .switchTab(actualIndex);
                        },
                        onDoubleTap: () {
                          if (tab.type == ReaderContentType.sermon) {
                            _openSermonQuickNavForTab(actualIndex);
                          } else {
                            _openQuickNavForBibleTab(
                              tabIndex: actualIndex,
                              isBm: false,
                            );
                          }
                        },
                        onLongPress: _isDesktopPlatform
                            ? null
                            : () {
                                if (tab.type == ReaderContentType.sermon) {
                                  _openSermonQuickNavForTab(actualIndex);
                                } else {
                                  _openQuickNavForBibleTab(
                                    tabIndex: actualIndex,
                                    isBm: false,
                                  );
                                }
                              },
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
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
                              _buildSermonTitleTooltip(
                                tab,
                                Text(
                                  _shortenTitle(tab.title),
                                  style: TextStyle(
                                    fontSize: typography.titleFontSize,
                                    fontWeight: isActive
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isActive
                                        ? theme.colorScheme.onPrimaryContainer
                                        : theme.colorScheme.onSurface,
                                  ),
                                ),
                              ),
                              if (visibleIndices.length > 1) ...[
                                const SizedBox(width: 4),
                                InkWell(
                                  onTap: () => ref
                                      .read(sermonFlowProvider.notifier)
                                      .closeTab(actualIndex),
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
                  itemBuilder: (_) {
                    final items = <PopupMenuEntry<String>>[
                      const PopupMenuItem(
                        value: 'share_link',
                        child: ListTile(
                          leading: Icon(Icons.share_outlined),
                          title: Text('Share Link'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'copy_link',
                        child: ListTile(
                          leading: Icon(Icons.copy_outlined),
                          title: Text('Copy Link'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                    ];
                    if (!isOnBibleTab) {
                      items.add(
                        const PopupMenuItem(
                          value: 'download_txt',
                          child: ListTile(
                            leading: Icon(Icons.description_outlined),
                            title: Text('Download Txt'),
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                          ),
                        ),
                      );
                      items.addAll([
                        const PopupMenuItem(
                          value: 'download_pdf',
                          child: ListTile(
                            leading: Icon(Icons.download_outlined),
                            title: Text('Download PDF'),
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'print_pdf',
                          child: ListTile(
                            leading: Icon(Icons.print_outlined),
                            title: Text('Print PDF'),
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                          ),
                        ),
                      ]);
                    }
                    items.addAll(const [
                      PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'close_others',
                        child: Text('Close Other Tabs'),
                      ),
                      PopupMenuItem(
                        value: 'hide_tabs',
                        child: Text('Hide Bottom Tabs'),
                      ),
                    ]);
                    return items;
                  },
                  onSelected: (val) {
                    if (val == 'share_link' || val == 'copy_link') {
                      final lang = isOnBibleTab
                          ? ref.read(selectedBibleLangProvider)
                          : ref.read(selectedSermonLangProvider);
                      final linkItem = isOnBibleTab
                          ? 'bible?book=${Uri.encodeComponent(activeTab?.book ?? '')}&chapter=${activeTab?.chapter ?? 1}&lang=$lang'
                          : 'sermon?id=${activeTab?.sermonId ?? ''}&lang=$lang';
                      final deepLink =
                          'https://endtimebride.in/appshare/$linkItem';

                      if (val == 'share_link') {
                        SharePlus.instance.share(
                          ShareParams(
                            text:
                                '${activeTab?.title ?? ''}\n\n🔗 Read in Bride Message App:\n$deepLink',
                          ),
                        );
                      } else {
                        Clipboard.setData(ClipboardData(text: deepLink));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Link copied to clipboard'),
                          ),
                        );
                      }
                    }
                    if (val == 'download_pdf') _downloadSermonPdf();
                    if (val == 'print_pdf') _printSermonPdf();
                    if (val == 'download_txt') _downloadSermonText();
                    if (val == 'close_others') _closeOtherTabs();
                    if (val == 'hide_tabs') {
                      setState(() => _hideBottomTabs = true);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSermonParagraphList(
    List<SermonParagraphEntity> paragraphs,
    TypographySettings typography,
    ColorScheme cs,
  ) {
    // Delegate to the unified sermon body builder.
    return _buildSermonBody(
      paragraphs,
      typography,
      cs,
      scrollController: _scrollController,
      searchQuery: _searchController.text,
      searchEnabled: _isSearching && !_searchAllSermons,
      matchIndices: _matchVerseIndices,
      currentMatchIndex: _currentMatchIndex,
    );
  }

  String _shortenTitle(String title) {
    if (title.length > 15) return '${title.substring(0, 12)}...';
    return title;
  }

  Widget _buildSermonBody(
    List<SermonParagraphEntity> paragraphs,
    TypographySettings typography,
    ColorScheme cs,
    {
    required ScrollController scrollController,
    required String searchQuery,
    required bool searchEnabled,
    required List<int> matchIndices,
    required int currentMatchIndex,
    double? fontSizeOverride,
  }) {
    final sermonFontSize = (fontSizeOverride ?? typography.fontSize)
        .clamp(12.0, 56.0)
        .toDouble();
    final baseStyle =
        Theme.of(context).textTheme.bodyLarge?.copyWith(
          fontSize: sermonFontSize,
          height: typography.lineHeight,
          fontFamily: typography.resolvedFontFamily,
        ) ??
        const TextStyle();

    final highlightStyle = baseStyle;

    final currentMatchStyle = TextStyle(
      backgroundColor: Colors.yellow.shade300,
      color: Colors.black,
      fontWeight: FontWeight.bold,
    );

    final children = <InlineSpan>[];
    final paragraphRanges = <Map<String, int?>>[];
    var offset = 0;

    for (var i = 0; i < paragraphs.length; i++) {
      final paragraph = paragraphs[i];
      final currentOccurrence = _currentOccurrenceForItemWithState(
        matchIndices: matchIndices,
        currentMatchIndex: currentMatchIndex,
        itemIndex: i,
      );
      final displayParagraphNumber = paragraph.paragraphNumber ?? (i + 1);
      final paragraphPrefix = '$displayParagraphNumber ';

      // Paragraph number
      children.add(
        TextSpan(
          text: paragraphPrefix,
          style: baseStyle.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: sermonFontSize * 0.82,
            color: cs.onSurfaceVariant,
          ),
        ),
      );

      // Paragraph text
      children.addAll(
        _buildHighlightedSpans(
          paragraph.text,
          baseStyle,
          highlightStyle,
          currentMatchStyle,
          query: searchQuery,
          enabled: searchEnabled,
          currentOccurrenceIndex: currentOccurrence,
        ),
      );

      if (i < paragraphs.length - 1) {
        // Use a single line break between paragraphs to avoid large gaps.
        children.add(TextSpan(text: '\n', style: baseStyle));
        offset += 1;
      }

      final prefixLength = paragraphPrefix.length;
      final paraLength = paragraph.text.length;
      paragraphRanges.add({
        'start': offset - prefixLength - paraLength,
        'end': offset,
        'number': displayParagraphNumber,
      });
    }

    final combinedSpan = TextSpan(children: children, style: baseStyle);
    final combinedPlainText = combinedSpan.toPlainText();

    return Stack(
      children: [
        SelectionArea(
          // Hide the platform menu; we show our own overlay automatically.
          contextMenuBuilder: (context, state) => const SizedBox.shrink(),
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Builder(
              builder: (innerContext) {
                return SelectableText.rich(
                  combinedSpan,
                  onSelectionChanged: (selection, cause) {
                    final text = selection.textInside(combinedPlainText);

                    _sermonSelectionDebounce?.cancel();

                    if (text.trim().isEmpty) {
                      if (_activeSelectionText != null) {
                        _sermonSelectionDebounce = Timer(
                          const Duration(milliseconds: 200),
                          () {
                            if (!mounted) return;
                            setState(() => _activeSelectionText = null);
                          },
                        );
                      }
                      return;
                    }

                    _sermonSelectionDebounce = Timer(
                      const Duration(milliseconds: 200),
                      () {
                        if (!mounted) return;
                        setState(() {
                          _activeSelectionText = text.trim();
                          final start = selection.start;
                          final end = selection.end;
                          int? first;
                          int? last;
                          for (final range in paragraphRanges) {
                            final rStart = range['start'] as int;
                            final rEnd = range['end'] as int;
                            final number = range['number'];
                            if (number == null) continue;
                            final intersects = start < rEnd && end > rStart;
                            if (!intersects) continue;
                            first = (first == null || number < first)
                                ? number
                                : first;
                            last = (last == null || number > last)
                                ? number
                                : last;
                          }
                          _selectionFirstParagraph = first;
                          _selectionLastParagraph = last;
                        });
                      },
                    );
                  },
                );
              },
            ),
          ),
        ),

        // Search markers (keep your existing logic)
        Positioned.fill(
          child: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 6,
              child: _buildMatchMarkers(
                paragraphs.length,
                matchIndices,
                matchIndices.isNotEmpty
                    ? matchIndices[currentMatchIndex]
                    : null,
                enabled: searchEnabled,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBmSplitContent({
    required SermonFlowState flowState,
    required TypographySettings typography,
    required List<SermonParagraphEntity> sermonParagraphs,
    required ColorScheme colorScheme,
  }) {
    final theme = Theme.of(context);
    final activeSermonTab = flowState.activeTab;
    if (activeSermonTab == null) {
      return const Center(child: Text('No sermon loaded.'));
    }
    final bmGroup = flowState.bmBibleGroup;
    final activeSecondaryTab = bmGroup.tabs.isEmpty
        ? null
        : bmGroup.tabs[bmGroup.activeIndex.clamp(0, bmGroup.tabs.length - 1)];
    final hasSecondaryTabs = bmGroup.tabs.isNotEmpty;

    final primaryPane = Column(
      children: [
        PaneHeader(
          tab: activeSermonTab,
          isPrimary: true,
          displayFontSize: _primaryPaneFontSize(typography),
          isSearchActive: _primaryMiniSearchActive,
          onOpenPicker: _openSermonQuickNav,
          onPrev: () => _openAdjacentSermon(-1),
          onNext: () => _openAdjacentSermon(1),
          onDecreaseFont: () => _adjustPrimarySplitFont(-1),
          onIncreaseFont: () => _adjustPrimarySplitFont(1),
          onToggleSearch: () {
            setState(() {
              _primaryMiniSearchActive = !_primaryMiniSearchActive;
              if (!_primaryMiniSearchActive) {
                _primaryMiniSearchController.clear();
                _primaryMatchIndices = [];
                _primaryTotalMatches = 0;
                _primaryCurrentMatchIndex = 0;
              }
            });
            if (_primaryMiniSearchActive &&
                _primaryMiniSearchController.text.trim().isNotEmpty) {
              _computePrimaryPaneMatches(_primaryMiniSearchController.text);
            }
          },
          onSourceSelected: (value) => _onSermonSplitViewSourceSelected(value),
        ),
        Expanded(
          child: ReadingPane(
            child: _buildSermonBody(
              sermonParagraphs,
              typography,
              colorScheme,
              scrollController: _splitPrimaryScrollController,
              searchQuery: _primaryMiniSearchController.text,
              searchEnabled: _primaryMiniSearchActive,
              matchIndices: _primaryMatchIndices,
              currentMatchIndex: _primaryCurrentMatchIndex,
              fontSizeOverride: _primaryPaneFontSize(typography),
            ),
            isSearchActive: _primaryMiniSearchActive,
            searchController: _primaryMiniSearchController,
            searchFocusNode: _primaryMiniSearchFocusNode,
            matchCounterText: _primaryTotalMatches > 0
                ? '${_primaryCurrentMatchIndex + 1}/$_primaryTotalMatches'
                : '0/0',
            onSearchChanged: (value) => _computePrimaryPaneMatches(value),
            onPrevMatch: _primaryTotalMatches > 0
                ? () => _navigatePrimaryPaneMatch(-1)
                : null,
            onNextMatch: _primaryTotalMatches > 0
                ? () => _navigatePrimaryPaneMatch(1)
                : null,
            onCloseSearch: () {
              setState(() {
                _primaryMiniSearchActive = false;
                _primaryMiniSearchController.clear();
                _primaryMatchIndices = [];
                _primaryTotalMatches = 0;
                _primaryCurrentMatchIndex = 0;
              });
            },
          ),
        ),
      ],
    );

    final rightTabsRow = SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemCount: bmGroup.tabs.length,
              itemBuilder: (context, index) {
                final tab = bmGroup.tabs[index];
                final isActive = index == bmGroup.activeIndex;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  child: GestureDetector(
                    onDoubleTap: () async {
                      if (tab.type == ReaderContentType.bible) {
                        await _openQuickNavForBibleTab(
                          bmIndex: index,
                          isBm: true,
                        );
                        return;
                      }
                      await _onSecondaryPaneSourceSelected(
                        (tab.sermonLang ?? 'en') == 'ta'
                            ? 'sermon_ta'
                            : 'sermon_en',
                        openInNewTab: false,
                      );
                    },
                    onLongPress: _isDesktopPlatform
                        ? null
                        : () async {
                              if (tab.type == ReaderContentType.bible) {
                                await _openQuickNavForBibleTab(
                                  bmIndex: index,
                                  isBm: true,
                                );
                                return;
                              }
                              await _onSecondaryPaneSourceSelected(
                                (tab.sermonLang ?? 'en') == 'ta'
                                    ? 'sermon_ta'
                                    : 'sermon_en',
                                openInNewTab: false,
                              );
                            },
                    child: FilterChip(
                      selected: isActive,
                      showCheckmark: isActive,
                      label: Text(tab.title),
                      onSelected: (_) => ref
                          .read(sermonFlowProvider.notifier)
                          .setBmBibleActive(index),
                      onDeleted: bmGroup.tabs.length <= 1
                          ? null
                          : () => ref
                                .read(sermonFlowProvider.notifier)
                                .closeBmBibleTab(index),
                      deleteIcon: const Icon(Icons.close, size: 16),
                    ),
                  ),
                );
              },
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Add module',
            icon: const Icon(Icons.add),
            onSelected: (value) async {
              await _onSecondaryPaneSourceSelected(value, openInNewTab: true);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'bible_en',
                child: Text('English Bible (KJV)'),
              ),
              PopupMenuItem(
                value: 'bible_ta',
                child: Text('Tamil Bible (BSI)'),
              ),
              PopupMenuItem(
                value: 'sermon_en',
                child: Text('English Sermons'),
              ),
              PopupMenuItem(
                value: 'sermon_ta',
                child: Text('Tamil Sermons'),
              ),
            ],
          ),
        ],
      ),
    );

    final fallbackSecondaryTab = ReaderTab(
      type: ReaderContentType.bible,
      title: 'Genesis 1',
      book: 'Genesis',
      chapter: 1,
      bibleLang: ref.read(selectedBibleLangProvider),
    );
    final resolvedSecondaryTab = activeSecondaryTab ?? fallbackSecondaryTab;

    final secondaryLang = resolvedSecondaryTab.bibleLang ?? resolvedSecondaryTab.sermonLang ?? 'en';
    final secondaryTypography = ref.watch(typographyProvider(secondaryLang));

    final secondaryPane = Column(
      children: [
        PaneHeader(
          tab: resolvedSecondaryTab,
          isPrimary: false,
          showSourcePicker: true,
          displayFontSize: _secondaryPaneFontSize(secondaryTypography),
          isSearchActive: _secondaryMiniSearchActive,
          onOpenPicker: () async {
            if (resolvedSecondaryTab.type == ReaderContentType.bible) {
              final lang = (resolvedSecondaryTab.bibleLang ?? 'en') == 'ta'
                  ? 'ta'
                  : 'en';
              await _openSecondaryBiblePicker(lang: lang, openInNewTab: false);
              return;
            }
            final lang = (resolvedSecondaryTab.sermonLang ?? 'en') == 'ta'
                ? 'ta'
                : 'en';
            await _openSecondarySermonPicker(lang: lang, openInNewTab: false);
          },
          onPrev: hasSecondaryTabs
              ? () async {
                    if (resolvedSecondaryTab.type == ReaderContentType.bible) {
                      await _openAdjacentBmBiblePassage(-1);
                      return;
                    }
                    await _openAdjacentSecondarySermon(
                      currentTab: resolvedSecondaryTab,
                      direction: -1,
                    );
                  }
              : null,
          onNext: hasSecondaryTabs
              ? () async {
                    if (resolvedSecondaryTab.type == ReaderContentType.bible) {
                      await _openAdjacentBmBiblePassage(1);
                      return;
                    }
                    await _openAdjacentSecondarySermon(
                      currentTab: resolvedSecondaryTab,
                      direction: 1,
                    );
                  }
              : null,
          onDecreaseFont: () => _adjustSecondarySplitFont(-1),
          onIncreaseFont: () => _adjustSecondarySplitFont(1),
          onSourceSelected: (value) async {
            await _onSecondaryPaneSourceSelected(value, openInNewTab: false);
          },
          onToggleSearch: () {
            setState(() {
              _secondaryMiniSearchActive = !_secondaryMiniSearchActive;
              if (!_secondaryMiniSearchActive) {
                _secondaryMiniSearchController.clear();
                _secondaryMatchIndices = [];
                _secondaryTotalMatches = 0;
                _secondaryCurrentMatchIndex = 0;
              }
            });
            if (_secondaryMiniSearchActive &&
                _secondaryMiniSearchController.text.trim().isNotEmpty) {
              _computeSecondaryPaneMatches(_secondaryMiniSearchController.text);
            }
          },
        ),
        rightTabsRow,
        Expanded(
          child: ReadingPane(
            child: resolvedSecondaryTab.type == ReaderContentType.bible
                ? _buildBmBibleContent(
                    resolvedSecondaryTab,
                    secondaryTypography,
                    controller: _splitSecondaryScrollController,
                    searchQuery: _secondaryMiniSearchController.text,
                    searchEnabled: _secondaryMiniSearchActive,
                    matchIndices: _secondaryMatchIndices,
                    currentMatchIndex: _secondaryCurrentMatchIndex,
                    fontSizeOverride: _secondaryPaneFontSize(secondaryTypography),
                  )
                : _buildBmSecondarySermonContent(
                    resolvedSecondaryTab,
                    secondaryTypography,
                    searchQuery: _secondaryMiniSearchController.text,
                    searchEnabled: _secondaryMiniSearchActive,
                    matchIndices: _secondaryMatchIndices,
                    currentMatchIndex: _secondaryCurrentMatchIndex,
                    fontSizeOverride: _secondaryPaneFontSize(secondaryTypography),
                  ),
            isSearchActive: _secondaryMiniSearchActive,
            searchController: _secondaryMiniSearchController,
            searchFocusNode: _secondaryMiniSearchFocusNode,
            matchCounterText: _secondaryTotalMatches > 0
                ? '${_secondaryCurrentMatchIndex + 1}/$_secondaryTotalMatches'
                : '0/0',
            onSearchChanged: (value) => _computeSecondaryPaneMatches(value),
            onPrevMatch: _secondaryTotalMatches > 0
                ? () => _navigateSecondaryPaneMatch(-1)
                : null,
            onNextMatch: _secondaryTotalMatches > 0
                ? () => _navigateSecondaryPaneMatch(1)
                : null,
            onCloseSearch: () {
              setState(() {
                _secondaryMiniSearchActive = false;
                _secondaryMiniSearchController.clear();
                _secondaryMatchIndices = [];
                _secondaryTotalMatches = 0;
                _secondaryCurrentMatchIndex = 0;
              });
            },
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= _bmWideBreakpoint;
        if (isWide) {
          final availableWidth = constraints.maxWidth;
          final usable = (availableWidth - _bmSplitterWidth).clamp(
            0.0,
            availableWidth,
          );
          final leftWidth = (usable * _bmSplitRatio).clamp(
            usable * _bmSplitMin,
            usable * _bmSplitMax,
          );
          final rightWidth = (usable - leftWidth).clamp(
            usable * (1 - _bmSplitMax),
            usable * (1 - _bmSplitMin),
          );
          return Row(
            children: [
              SizedBox(width: leftWidth, child: primaryPane),
              MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragUpdate: (details) {
                    final delta = details.delta.dx / (usable == 0 ? 1 : usable);
                    setState(() {
                      _bmSplitRatio = (_bmSplitRatio + delta).clamp(
                        _bmSplitMin,
                        _bmSplitMax,
                      );
                    });
                  },
                  onHorizontalDragEnd: (_) => _persistBmSplitRatio(),
                  onDoubleTap: () {
                    setState(() {
                      _bmSplitRatio = _bmSplitDefault;
                    });
                    _persistBmSplitRatio();
                  },
                  child: SizedBox(
                    width: _bmSplitterWidth,
                    child: Center(
                      child: Container(
                        width: 2,
                        height: double.infinity,
                        color: theme.colorScheme.outlineVariant.withAlpha(140),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: rightWidth, child: secondaryPane),
            ],
          );
        }
        final availableHeight = constraints.maxHeight;
        const mobileSplitterTouchHeight = 28.0;
        final usableHeight = (availableHeight - mobileSplitterTouchHeight)
            .clamp(0.0, availableHeight);
        final topHeight = (usableHeight * _bmSplitRatio).clamp(
          usableHeight * _bmSplitMin,
          usableHeight * _bmSplitMax,
        );
        final bottomHeight = (usableHeight - topHeight).clamp(
          usableHeight * (1 - _bmSplitMax),
          usableHeight * (1 - _bmSplitMin),
        );

        return Column(
          children: [
            SizedBox(height: topHeight, child: primaryPane),
            MouseRegion(
              cursor: SystemMouseCursors.resizeRow,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragUpdate: (details) {
                  final delta =
                      details.delta.dy / (usableHeight == 0 ? 1 : usableHeight);
                  setState(() {
                    _bmSplitRatio = (_bmSplitRatio + delta).clamp(
                      _bmSplitMin,
                      _bmSplitMax,
                    );
                  });
                },
                onVerticalDragEnd: (_) => _persistBmSplitRatio(),
                onDoubleTap: () {
                  setState(() {
                    _bmSplitRatio = _bmSplitDefault;
                  });
                  _persistBmSplitRatio();
                },
                child: SizedBox(
                  height: mobileSplitterTouchHeight,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: double.infinity,
                        height: 1,
                        color: theme.colorScheme.outlineVariant.withAlpha(130),
                      ),
                      Container(
                        width: 52,
                        height: 20,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant.withAlpha(
                              170,
                            ),
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 20,
                              height: 2,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.onSurfaceVariant,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Container(
                              width: 20,
                              height: 2,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.onSurfaceVariant,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(height: bottomHeight, child: secondaryPane),
          ],
        );
      },
    );
  }

  Widget _buildBmPanel({
    required Widget header,
    Widget? topToolbar,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withAlpha(90),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant.withAlpha(90),
                ),
              ),
            ),
            child: header,
          ),
          if (topToolbar != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.outlineVariant.withAlpha(80),
                  ),
                ),
              ),
              child: topToolbar,
            ),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _buildBmBibleHeader({required BmBibleGroup? group}) {
    final theme = Theme.of(context);
    final lang = ref.watch(selectedSermonLangProvider);
    final typography = ref.watch(typographyProvider(lang));
    final tabs = group?.tabs ?? const <ReaderTab>[];
    final activeIndex = group?.activeIndex ?? 0;
    return Row(
      children: [
        Icon(
          Icons.menu_book_outlined,
          size: 16,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 6),
        Text(
          'B',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                if (tabs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      'Select chapter',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontSize: typography.titleFontSize,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                for (var i = 0; i < tabs.length; i++)
                  _buildBmBibleTabChip(
                    label: tabs[i].title,
                    isActive: i == activeIndex,
                    onTap: () => ref
                        .read(sermonFlowProvider.notifier)
                        .setBmBibleActive(i),
                    onDoubleTap: () =>
                        _openQuickNavForBibleTab(bmIndex: i, isBm: true),
                    onLongPress: _isDesktopPlatform
                        ? null
                        : () =>
                              _openQuickNavForBibleTab(bmIndex: i, isBm: true),
                    onClose: () => ref
                        .read(sermonFlowProvider.notifier)
                        .closeBmBibleTab(i),
                  ),
              ],
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.remove),
          tooltip: 'Decrease Bible text size',
          visualDensity: VisualDensity.compact,
          onPressed: () => _adjustSecondarySplitFont(-1),
        ),
        Text(
          _secondaryPaneFontSize(typography).toStringAsFixed(0),
          style: theme.textTheme.labelSmall,
        ),
        IconButton(
          icon: const Icon(Icons.add),
          tooltip: 'Increase Bible text size',
          visualDensity: VisualDensity.compact,
          onPressed: () => _adjustSecondarySplitFont(1),
        ),
        IconButton(
          icon: const Icon(Icons.add),
          tooltip: 'Add Bible tab',
          visualDensity: VisualDensity.compact,
          onPressed: _openQuickNav,
        ),
      ],
    );
  }

  Widget _buildBmSermonHeader({required SermonFlowState flowState}) {
    final theme = Theme.of(context);
    final lang = ref.watch(selectedSermonLangProvider);
    final typography = ref.watch(typographyProvider(lang));
    final sermonIndices = <int>[];
    for (var i = 0; i < flowState.tabs.length; i++) {
      if (flowState.tabs[i].type == ReaderContentType.sermon) {
        sermonIndices.add(i);
      }
    }
    return Row(
      children: [
        Icon(Icons.import_contacts, size: 16, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Text(
          'M',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final index in sermonIndices)
                  _buildBmSermonTabChip(
                    label: flowState.tabs[index].title,
                    isActive: index == flowState.activeTabIndex,
                    tooltip: _sermonTooltipText(flowState.tabs[index]),
                    fontSize: typography.titleFontSize,
                    onTap: () =>
                        ref.read(sermonFlowProvider.notifier).switchTab(index),
                    onDoubleTap: () => _openSermonQuickNavForTab(index),
                    onLongPress: _isDesktopPlatform
                        ? null
                        : () => _openSermonQuickNavForTab(index),
                    onClose: sermonIndices.length <= 1
                        ? null
                        : () => ref
                              .read(sermonFlowProvider.notifier)
                              .closeTab(index),
                  ),
              ],
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.remove),
          tooltip: 'Decrease sermon text size',
          visualDensity: VisualDensity.compact,
          onPressed: () => _adjustPrimarySplitFont(-1),
        ),
        Text(
          _primaryPaneFontSize(typography).toStringAsFixed(0),
          style: theme.textTheme.labelSmall,
        ),
        IconButton(
          icon: const Icon(Icons.add),
          tooltip: 'Increase sermon text size',
          visualDensity: VisualDensity.compact,
          onPressed: () => _adjustPrimarySplitFont(1),
        ),
        IconButton(
          icon: const Icon(Icons.info_outline),
          tooltip: 'Sermon tab help',
          visualDensity: VisualDensity.compact,
          onPressed: _showSermonTabHelp,
        ),
        IconButton(
          icon: const Icon(Icons.add),
          tooltip: 'Add sermon tab',
          visualDensity: VisualDensity.compact,
          onPressed: _openSermonQuickNav,
        ),
      ],
    );
  }

  Widget _buildHeaderPickerTag({
    required String label,
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
    required bool enabled,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: tooltip,
        child: OutlinedButton.icon(
          onPressed: enabled ? onPressed : null,
          icon: Icon(icon, size: 14),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            minimumSize: const Size(0, 28),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            textStyle: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBmPaneNavToolbar({
    required String previousTooltip,
    required String allLabel,
    required String allTooltip,
    required IconData allIcon,
    required VoidCallback? onPrevious,
    required VoidCallback onAll,
    required VoidCallback? onNext,
  }) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: previousTooltip,
          visualDensity: VisualDensity.compact,
          onPressed: onPrevious,
        ),
        Expanded(
          child: Center(
            child: _buildHeaderPickerTag(
              label: allLabel,
              tooltip: allTooltip,
              icon: allIcon,
              enabled: true,
              onPressed: onAll,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Next',
          visualDensity: VisualDensity.compact,
          onPressed: onNext,
        ),
      ],
    );
  }

  Widget _buildBmSermonTabChip({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    required String? tooltip,
    required double fontSize,
    VoidCallback? onClose,
    VoidCallback? onDoubleTap,
    VoidCallback? onLongPress,
  }) {
    final theme = Theme.of(context);
    final bg = isActive
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surface;
    final fg = isActive
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;
    final borderColor = isActive
        ? theme.colorScheme.primary
        : theme.colorScheme.outline;
    final chip = Container(
      margin: const EdgeInsets.only(right: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor.withAlpha(160)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _shortenTitle(label),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: fg,
                  fontSize: fontSize,
                ),
              ),
              if (onClose != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(Icons.close, size: 14, color: fg),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  onPressed: onClose,
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (tooltip == null || tooltip.isEmpty) return chip;
    return Tooltip(message: tooltip, child: chip);
  }

  void _showSermonTabHelp() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sermon & Bible Tabs'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Single click / tap: open this tab content'),
            SizedBox(height: 6),
            Text('Double-click (desktop): open Quick Navigation for this tab'),
            SizedBox(height: 6),
            Text('Double-tap (mobile): open Quick Navigation for this tab'),
            SizedBox(height: 6),
            Text('Long-press (mobile): open Quick Navigation for this tab'),
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

  Widget _buildBmBibleTabChip({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    VoidCallback? onDoubleTap,
    VoidCallback? onLongPress,
    required VoidCallback onClose,
  }) {
    final theme = Theme.of(context);
    final lang = ref.watch(selectedSermonLangProvider);
    final typography = ref.watch(typographyProvider(lang));
    final bg = isActive
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surface;
    final fg = isActive
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;
    final borderColor = isActive
        ? theme.colorScheme.primary
        : theme.colorScheme.outline;
    return Container(
      margin: const EdgeInsets.only(right: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor.withAlpha(160)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _shortenTitle(label),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: fg,
                  fontSize: typography.titleFontSize,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(Icons.close, size: 14, color: fg),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                onPressed: onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBmBibleContent(
    ReaderTab? bibleTab,
    TypographySettings typography,
    {
    required ScrollController controller,
    required String searchQuery,
    required bool searchEnabled,
    required List<int> matchIndices,
    required int currentMatchIndex,
    double? fontSizeOverride,
  }
  ) {
    if (bibleTab == null || bibleTab.book == null || bibleTab.chapter == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('No Bible passage selected.'),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _openQuickNav,
                icon: const Icon(Icons.menu_book_outlined),
                label: const Text('Choose Passage'),
              ),
            ],
          ),
        ),
      );
    }

    final asyncVerses = ref.watch(chapterVersesProvider(bibleTab));
    return asyncVerses.when(
      data: (verses) {
        if (verses.isEmpty) {
          return const Center(child: Text('No verses found in this chapter.'));
        }

        final signature =
            '${bibleTab.id}:${bibleTab.book}:${bibleTab.chapter}:${bibleTab.bibleLang ?? 'en'}:${verses.length}';
        if (_bmVerseSignature != signature) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _bmVerseSignature = signature;
              _bmCurrentVerses = verses;
              _bmVerseKeys = List.generate(verses.length, (_) => GlobalKey());
              _bmSecondaryParagraphs = [];
            });
            if (_secondaryMiniSearchActive &&
                _secondaryMiniSearchController.text.trim().isNotEmpty) {
              _computeSecondaryPaneMatches(
                _secondaryMiniSearchController.text,
                scrollToMatch: false,
              );
            }
          });
        }

        final cs = Theme.of(context).colorScheme;
        final bibleFontSize = (fontSizeOverride ?? typography.fontSize).clamp(
          12.0,
          56.0,
        );
        final baseStyle =
            Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontSize: bibleFontSize,
              height: typography.lineHeight,
              fontFamily: typography.resolvedFontFamily,
            ) ??
            const TextStyle();

        return SelectionArea(
          child: ListView.builder(
            controller: controller,
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            itemCount: verses.length,
            itemBuilder: (context, index) {
              final verse = verses[index];
              final key = index < _bmVerseKeys.length
                  ? _bmVerseKeys[index]
                  : GlobalKey();
              final isSelected = _selectedVerseNumbers.contains(verse.verse);
              final currentOccurrence = _currentOccurrenceForItemWithState(
                matchIndices: matchIndices,
                currentMatchIndex: currentMatchIndex,
                itemIndex: index,
              );
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
                    horizontal: 6,
                    vertical: 4,
                  ),
                  margin: const EdgeInsets.only(bottom: 4),
                  child: RichText(
                    text: TextSpan(
                      style: baseStyle,
                      children: [
                        TextSpan(
                          text: '${verse.verse} ',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: bibleFontSize * 0.8,
                            color: isSelected
                                ? cs.primary
                                : cs.onSurfaceVariant,
                          ),
                        ),
                        ..._buildHighlightedSpans(
                          verse.text,
                          baseStyle,
                          baseStyle,
                          TextStyle(
                            backgroundColor: Colors.yellow.shade300,
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                          query: searchQuery,
                          enabled: searchEnabled,
                          currentOccurrenceIndex: currentOccurrence,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => _buildLoadError(err),
    );
  }

  Widget _buildBmSecondarySermonContent(
    ReaderTab sermonTab,
    TypographySettings typography, {
    required String searchQuery,
    required bool searchEnabled,
    required List<int> matchIndices,
    required int currentMatchIndex,
    double? fontSizeOverride,
  }) {
    final sermonId = sermonTab.sermonId;
    if (sermonId == null || sermonId.isEmpty) {
      return const Center(child: Text('No sermon selected.'));
    }
    final String lang =
        (sermonTab.sermonLang ?? ref.watch(selectedSermonLangProvider)) == 'ta'
        ? 'ta'
        : 'en';
    final paragraphsFuture = _getBmSecondarySermonFuture(
      sermonLang: lang,
      sermonId: sermonId,
    );
    return FutureBuilder<List<SermonParagraphEntity>>(
      future: paragraphsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                snapshot.error.toString(),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final paragraphs = snapshot.data ?? const <SermonParagraphEntity>[];
        if (paragraphs.isEmpty) {
          return const Center(child: Text('No paragraphs found for sermon.'));
        }
        final signature = '${sermonId}_${lang}_${paragraphs.length}';
        if (_bmVerseSignature != signature) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _bmVerseSignature = signature;
              _bmSecondaryParagraphs = paragraphs;
              _bmCurrentVerses = [];
              _bmVerseKeys = [];
            });
            if (_secondaryMiniSearchActive &&
                _secondaryMiniSearchController.text.trim().isNotEmpty) {
              _computeSecondaryPaneMatches(
                _secondaryMiniSearchController.text,
                scrollToMatch: false,
              );
            }
          });
        }
        return _buildSermonBody(
          paragraphs,
          typography,
          Theme.of(context).colorScheme,
          scrollController: _splitSecondaryScrollController,
          searchQuery: searchQuery,
          searchEnabled: searchEnabled,
          matchIndices: matchIndices,
          currentMatchIndex: currentMatchIndex,
          fontSizeOverride: fontSizeOverride,
        );
      },
    );
  }

  String? _sermonTooltipText(ReaderTab tab) {
    if (tab.sermonId == null) return null;
    final sermonAsync = ref.watch(sermonByIdProvider(tab.sermonId!));
    return sermonAsync.maybeWhen(
      data: (sermon) {
        if (sermon == null) return tab.title;
        final metaParts = <String>[
          if (sermon.id.isNotEmpty) sermon.id,
          if (sermon.year != null) sermon.year.toString(),
          if (sermon.duration != null && sermon.duration!.isNotEmpty)
            sermon.duration!,
          if (sermon.location != null && sermon.location!.isNotEmpty)
            sermon.location!,
        ];
        final meta = metaParts.join(' • ');
        if (meta.isEmpty) return sermon.title;
        return '${sermon.title}\n$meta';
      },
      orElse: () => tab.title,
    );
  }

  Widget _buildSermonTitleTooltip(ReaderTab tab, Widget child) {
    if (tab.type != ReaderContentType.sermon) return child;
    final tooltip = _sermonTooltipText(tab);
    if (tooltip == null || tooltip.isEmpty) return child;
    return Tooltip(message: tooltip, child: child);
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(label, style: Theme.of(context).textTheme.labelMedium),
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
  final bool isActive;

  const _NavIconButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeBg = theme.colorScheme.primaryContainer;
    final activeFg = theme.colorScheme.onPrimaryContainer;
    return OutlinedButton.icon(
      icon: Icon(icon, size: 16, color: isActive ? activeFg : null),
      label: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 13,
          color: isActive ? activeFg : null,
        ),
      ),
      style: OutlinedButton.styleFrom(
        backgroundColor: isActive ? activeBg : null,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: BorderSide(
          color: isActive
              ? theme.colorScheme.primary
              : theme.colorScheme.outline.withAlpha(160),
        ),
      ),
      onPressed: onPressed,
    );
  }
}
