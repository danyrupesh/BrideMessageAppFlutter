import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart' show SharePlus, ShareParams;
import 'package:printing/printing.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/pdf_export_service.dart';
import '../../core/utils/desktop_file_saver.dart';
import '../../core/widgets/responsive_bottom_sheet.dart';
import '../../core/widgets/selection_action_bar.dart';
import 'providers/reader_provider.dart';
import 'providers/typography_provider.dart';
import 'models/reader_tab.dart';
import 'widgets/reader_settings_sheet.dart';
import 'widgets/quick_navigation_sheet.dart';
import 'widgets/pane_header.dart';
import '../help/widgets/help_button.dart';
import 'widgets/reading_pane.dart';
import 'widgets/bottom_tab_rail.dart';
import 'widgets/parallel_source_sheet.dart';
import '../../core/database/models/bible_search_result.dart';
import '../../core/database/models/sermon_models.dart';
import '../../core/database/sermon_repository.dart';
import '../common/widgets/fts_highlight_text.dart';
import '../common/widgets/section_menu_button.dart';
import '../onboarding/onboarding_screen.dart';
import '../sermons/providers/sermon_provider.dart';

enum BibleSearchScope { chapter, book, all }

enum BibleSearchMode { smart, exactPhrase, anyWord, accurate }

class _NextMatchIntent extends Intent {
  const _NextMatchIntent();
}

class _PrevMatchIntent extends Intent {
  const _PrevMatchIntent();
}

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key});

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  static final PdfExportService _pdfExportService = PdfExportService();
  static const int _globalBiblePageSize = 50;
  static const String _searchModePrefKey = 'reader_search_mode';
  static const String _parallelSplitRatioPrefKey = 'reader_en_ta_split_ratio';
  static const double _parallelWideBreakpoint = 900.0;
  static const double _parallelSplitDefault = 0.5;
  static const double _parallelSplitMin = 0.3;
  static const double _parallelSplitMax = 0.7;
  static const double _parallelSplitterWidth = 8.0;
  static const double _bmSplitDefault = 0.6;
  static const double _bmSplitMin = 0.35;
  static const double _bmSplitMax = 0.75;
  static const double _bmSplitterWidth = 8.0;

  // ── Scroll controller (preserves position across fullscreen toggle) ────────
  final ScrollController _scrollController = ScrollController();
  final ScrollController _parallelPrimaryScrollController = ScrollController();
  final ScrollController _parallelSecondaryScrollController =
      ScrollController();
  final ScrollController _bmTabsScrollController = ScrollController();
  final ScrollController _splitTabsScrollController = ScrollController();
  /// Separate from [_scrollController] so book/all-scope search doesn't detach
  /// the Bible verse list from its scroll controller.
  final ScrollController _scopeSearchScrollController = ScrollController();
  final Map<String, Future<List<SermonParagraphEntity>>>
  _splitSermonParagraphsFutureCache = {};
  final FocusNode _searchFieldFocusNode = FocusNode();
  final TextEditingController _primaryMiniSearchController =
      TextEditingController();
  final TextEditingController _secondaryMiniSearchController =
      TextEditingController();
  final FocusNode _primaryMiniSearchFocusNode = FocusNode();
  final FocusNode _secondaryMiniSearchFocusNode = FocusNode();
  final TextEditingController _gotoVerseController = TextEditingController();
  final FocusNode _gotoVerseFocusNode = FocusNode();
  late final bool Function(KeyEvent) _searchKeyHandler;

  String? _parallelSourceTabId;
  ReaderTab? _parallelEnglishTab;
  double _parallelSplitRatio = _parallelSplitDefault;
  bool _primaryMiniSearchActive = false;
  bool _secondaryMiniSearchActive = false;
  List<BibleSearchResult> _secondaryVerses = [];
  String? _lastSecondaryChapterSignature;
  List<int> _secondaryMatchVerseIndices = [];
  int _secondaryCurrentMatchIndex = 0;
  int _secondaryTotalMatches = 0;

  // ── In-page search ────────────────────────────────────────────────────────
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  BibleSearchScope _searchScope = BibleSearchScope.chapter;
  BibleSearchMode _searchMode = BibleSearchMode.smart;
  bool _showSearchOptions = true;
  int? _bookRangeStartIndex;
  int? _bookRangeEndIndex;
  int? _chapterRangeStart;
  int? _chapterRangeEnd;
  List<BibleSearchResult> _globalBibleResults = [];
  bool _globalSearchLoading = false;
  bool _globalSearchLoadingMore = false;
  int _globalSearchTotalCount = 0;
  Timer? _globalSearchDebounce;
  int _globalSearchRequestId = 0;
  String?
  _lastSearchActivatedTabId; // Track which tab had search auto-activated
  String? _lastActiveTabId;
  String? _lastTypographyLang;

  /// Flat list of verse indices (one entry per individual match occurrence).
  List<int> _matchVerseIndices = [];
  int _currentMatchIndex = 0;
  int _totalMatches = 0;

  // ── Verse selection ───────────────────────────────────────────────────────
  final Set<int> _selectedVerseNumbers = {};
  String? _activeSelectionText;
  int? _lastVerseTapped;

  // ── Current verses cache (needed for search + share) ─────────────────────
  List<BibleSearchResult> _currentVerses = [];
  String? _lastChapterSignature;
  /// Keys for scroll-to-verse (fractional scroll breaks with variable verse heights).
  final Map<String, GlobalKey> _bibleVerseAnchorKeys = {};
  final Map<String, String> _lastParallelBiblePaneSig = {};
  String? _pendingSearchRecalcSignature;
  String? _pendingVerseJumpSignature;
  String? _initialSearchScrollTabId;
  final Map<String, GlobalKey> _bmTabChipKeys = {};
  final Map<String, GlobalKey> _splitTabChipKeys = {};
  String? _lastBmAutoScrollTabId;
  String? _lastSplitAutoScrollTabId;

  // ─────────────────────────────────────────────────────────────────────────

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
      if (_totalMatches == 0) return true;
      if (HardwareKeyboard.instance.isShiftPressed) {
        _navigateToMatch(-1);
      } else {
        _navigateToMatch(1);
      }
      return true;
    };
    HardwareKeyboard.instance.addHandler(_searchKeyHandler);
    unawaited(_loadSearchPreferences());
    unawaited(_loadParallelSplitRatio());
  }

  Future<void> _onMainTabTap(int index, List<ReaderTab> tabs) async {
    final activeIndex = ref.read(readerProvider).activeTabIndex;
    final tab = tabs[index];
    final isActive = index == activeIndex;
    if (isActive) {
      if (tab.type == ReaderContentType.bible) {
        // Always reload the correct language when Bible tab is tapped, even if already active
        final lang =
            tab.bibleLang ?? ref.read(selectedBibleLangProvider) ?? 'en';
        ref.read(selectedBibleLangProvider.notifier).setLang(lang);
        ref
            .read(readerProvider.notifier)
            .replaceCurrentTab(tab.copyWith(bibleLang: lang));
        _openQuickNav(initialLang: lang, initialOpenInNewTab: false);
        return;
      }
      final sermonLang =
          tab.sermonLang ?? ref.read(selectedSermonLangProvider) ?? 'en';
      final picked = await _pickSermonForBm(sermonLang);
      if (!mounted || picked == null) return;
      ref.read(selectedSermonLangProvider.notifier).setLang(sermonLang);
      ref
          .read(readerProvider.notifier)
          .replaceCurrentTab(
            ReaderTab(
              type: ReaderContentType.sermon,
              title: picked.title,
              sermonId: picked.id,
              sermonLang: sermonLang,
            ),
          );
      return;
    }
    ref.read(readerProvider.notifier).switchTab(index);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _parallelPrimaryScrollController.dispose();
    _parallelSecondaryScrollController.dispose();
    _bmTabsScrollController.dispose();
    _splitTabsScrollController.dispose();
    _searchController.dispose();
    _primaryMiniSearchController.dispose();
    _secondaryMiniSearchController.dispose();
    _searchFieldFocusNode.dispose();
    _primaryMiniSearchFocusNode.dispose();
    _secondaryMiniSearchFocusNode.dispose();
    _gotoVerseController.dispose();
    _gotoVerseFocusNode.dispose();
    _scopeSearchScrollController.dispose();
    _splitSermonParagraphsFutureCache.clear();
    _globalSearchDebounce?.cancel();
    HardwareKeyboard.instance.removeHandler(_searchKeyHandler);
    super.dispose();
  }

  Future<List<SermonParagraphEntity>> _getSplitSermonParagraphsFuture({
    required String sermonLang,
    required String sermonId,
  }) {
    final cacheKey = '$sermonLang::$sermonId';
    return _splitSermonParagraphsFutureCache.putIfAbsent(cacheKey, () async {
      final repo = await ref.read(
        sermonRepositoryByLangProvider(sermonLang).future,
      );
      return repo.getParagraphsForSermon(sermonId);
    });
  }

  void _syncBmTabAutoScroll({
    required List<ReaderBmMessageTab> tabs,
    required int activeIndex,
  }) {
    if (tabs.length <= 1) {
      _lastBmAutoScrollTabId = null;
      return;
    }

    final safeIndex = activeIndex.clamp(0, tabs.length - 1);
    final activeTabId = tabs[safeIndex].id;
    if (_lastBmAutoScrollTabId == activeTabId) return;
    _lastBmAutoScrollTabId = activeTabId;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final targetContext = _bmTabChipKeys[activeTabId]?.currentContext;
      if (targetContext != null) {
        Scrollable.ensureVisible(
          targetContext,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: 0.5,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        );
        return;
      }

      if (!_bmTabsScrollController.hasClients) return;
      final estimatedOffset = (safeIndex * 150.0).clamp(
        0.0,
        _bmTabsScrollController.position.maxScrollExtent,
      );
      _bmTabsScrollController.animateTo(
        estimatedOffset,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  // ── Navigation handler (shared by AppBar title + FAB) ─────────────────────

  Future<void> _openQuickNav({
    String? initialLang,
    bool? initialOpenInNewTab,
  }) async {
    final result = await showResponsiveBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      maxWidth: 980,
      builder: (_) => QuickNavigationSheet(
        initialLang: initialLang,
        initialOpenInNewTab: initialOpenInNewTab,
      ),
    );
    _handleNavResult(result);
  }

  Future<void> _openQuickNavForTestament(int testamentIndex) async {
    // testamentIndex: 0 = Old, 1 = New
    final lang = ref.read(selectedBibleLangProvider);
    final result = await showResponsiveBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      maxWidth: 980,
      builder: (_) => QuickNavigationSheet(
        initialLang: lang,
        initialTestamentIndex: testamentIndex,
      ),
    );
    _handleNavResult(result);
  }

  Future<String> _mapBookNameForLanguage({
    required String sourceBook,
    required String sourceLang,
    required String targetLang,
  }) async {
    if (sourceLang == targetLang) return sourceBook;

    try {
      final sourceBooks = await ref
          .read(bibleBookListByLangProvider(sourceLang).future)
          .timeout(const Duration(seconds: 8));
      final targetBooks = await ref
          .read(bibleBookListByLangProvider(targetLang).future)
          .timeout(const Duration(seconds: 8));

      if (sourceBooks.isEmpty || targetBooks.isEmpty) {
        return sourceBook;
      }

      final normalizedSource = sourceBook.trim().toLowerCase();
      final sourceMatch = sourceBooks.where((book) {
        final name = (book['book'] as String? ?? '').trim().toLowerCase();
        return name == normalizedSource;
      }).toList();

      if (sourceMatch.isEmpty) return sourceBook;

      final sourceIndex = sourceMatch.first['book_index'] as int?;
      if (sourceIndex == null) return sourceBook;

      final targetMatch = targetBooks.where((book) {
        return (book['book_index'] as int?) == sourceIndex;
      }).toList();

      if (targetMatch.isEmpty) return sourceBook;

      final mapped = targetMatch.first['book'] as String?;
      return (mapped == null || mapped.trim().isEmpty)
          ? sourceBook
          : mapped.trim();
    } catch (_) {
      return sourceBook;
    }
  }

  Future<void> _openEnglishParallel(
    ReaderTab? activeTab, {
    String? sourceLangOverride,
  }) async {
    await _openParallelForTargetLang(
      activeTab,
      targetLang: 'en',
      sourceLangOverride: sourceLangOverride,
    );
  }

  Future<void> _openParallelForTargetLang(
    ReaderTab? activeTab, {
    required String targetLang,
    String? sourceLangOverride,
  }) async {
    if (activeTab == null ||
        activeTab.type != ReaderContentType.bible ||
        activeTab.book == null ||
        activeTab.chapter == null) {
      return;
    }

    final sourceLang =
        sourceLangOverride ??
        (activeTab.bibleLang ?? ref.read(selectedBibleLangProvider)) ??
        'en';
    final mappedBook = await _mapBookNameForLanguage(
      sourceBook: activeTab.book!,
      sourceLang: sourceLang,
      targetLang: targetLang,
    );

    final secondaryTab = ReaderTab(
      type: ReaderContentType.bible,
      title: '$mappedBook ${activeTab.chapter}',
      book: mappedBook,
      chapter: activeTab.chapter,
      verse: activeTab.verse,
      bibleLang: targetLang,
    );

    final rightTab = ReaderTab(
      type: ReaderContentType.bible,
      title: '$mappedBook ${activeTab.chapter}',
      book: mappedBook,
      chapter: activeTab.chapter,
      verse: activeTab.verse,
      bibleLang: targetLang,
    );
    ref
        .read(readerProvider.notifier)
        .upsertSplitRightTab(tab: rightTab, openInNewTab: true);

    _resetGlobalSearchState(clearQuery: false);
    if (!mounted) return;
    setState(() {
      _parallelSourceTabId = activeTab.id;
      _parallelEnglishTab = secondaryTab;
    });
  }

  String _languageLabel(String lang) {
    if (lang == 'ta') return 'Tamil';
    if (lang == 'en') return 'English';
    return lang.toUpperCase();
  }

  Future<void> _enableBmModeForLanguage(
    ReaderTab? activeTab, {
    required String sermonLang,
  }) async {
    if (activeTab == null ||
        activeTab.type != ReaderContentType.bible ||
        activeTab.book == null ||
        activeTab.chapter == null) {
      return;
    }

    final hasSermonDb = await ref.read(
      sermonDatabaseExistsProvider(sermonLang).future,
    );

    if (!hasSermonDb) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const OnboardingScreen(showImportDirectly: true),
        ),
      );
      return;
    }

    final picked = await _pickSermonForBm(sermonLang);
    if (!mounted || picked == null) return;

    ref.read(selectedSermonLangProvider.notifier).setLang(sermonLang);

    if (_isParallelActiveFor(activeTab)) {
      _clearParallelMode();
    }

    final added = ref
        .read(readerProvider.notifier)
        .upsertSplitRightTab(
          tab: ReaderTab(
            type: ReaderContentType.sermon,
            title: picked.title,
            sermonId: picked.id,
            sermonLang: sermonLang,
          ),
          openInNewTab: true,
        );
    if (!added && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Split view tab limit reached (20).')),
      );
    }
  }

  Future<void> _onSplitViewSourceSelected(
    ReaderTab? activeTab,
    String value,
  ) async {
    final activeLang =
        (activeTab?.bibleLang ?? ref.read(selectedBibleLangProvider)) ?? 'en';
    switch (value) {
      case 'bible_en':
        await _openParallelForTargetLang(
          activeTab,
          targetLang: 'en',
          sourceLangOverride: activeLang,
        );
        break;
      case 'bible_ta':
        await _openParallelForTargetLang(
          activeTab,
          targetLang: 'ta',
          sourceLangOverride: activeLang,
        );
        break;
      case 'sermon_en':
        await _enableBmModeForLanguage(activeTab, sermonLang: 'en');
        break;
      case 'sermon_ta':
        await _enableBmModeForLanguage(activeTab, sermonLang: 'ta');
        break;
      case 'split_off':
        _clearParallelMode();
        ref.read(readerProvider.notifier).closeSecondaryPane();
        break;
    }
  }

  Future<void> _switchToEnglishBible(
    ReaderTab? activeTab, {
    String? sourceLangOverride,
  }) async {
    if (activeTab == null ||
        activeTab.type != ReaderContentType.bible ||
        activeTab.book == null ||
        activeTab.chapter == null) {
      return;
    }

    final sourceLang =
        sourceLangOverride ??
        (activeTab.bibleLang ?? ref.read(selectedBibleLangProvider)) ??
        'en';
    final mappedBook = await _mapBookNameForLanguage(
      sourceBook: activeTab.book!,
      sourceLang: sourceLang,
      targetLang: 'en',
    );

    final englishTab = activeTab.copyWith(
      title: '$mappedBook ${activeTab.chapter}',
      book: mappedBook,
      chapter: activeTab.chapter,
      verse: activeTab.verse,
      bibleLang: 'en',
      initialSearchQuery: null,
      openedFromSearch: false,
    );

    _clearParallelMode();
    ref.read(readerProvider.notifier).replaceCurrentTab(englishTab);
  }

  Future<void> _switchToTamilBible(ReaderTab? activeTab) async {
    if (activeTab == null ||
        activeTab.type != ReaderContentType.bible ||
        activeTab.book == null ||
        activeTab.chapter == null) {
      return;
    }

    final sourceLang = activeTab.bibleLang ?? 'en';
    final mappedBook = await _mapBookNameForLanguage(
      sourceBook: activeTab.book!,
      sourceLang: sourceLang,
      targetLang: 'ta',
    );

    final tamilTab = activeTab.copyWith(
      title: '$mappedBook ${activeTab.chapter}',
      book: mappedBook,
      chapter: activeTab.chapter,
      verse: activeTab.verse,
      bibleLang: 'ta',
      initialSearchQuery: null,
      openedFromSearch: false,
    );

    _clearParallelMode();
    ref.read(readerProvider.notifier).replaceCurrentTab(tamilTab);
  }

  Future<void> _loadParallelSplitRatio() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getDouble(_parallelSplitRatioPrefKey);
    if (value == null || !mounted) return;
    setState(() {
      _parallelSplitRatio = value.clamp(_parallelSplitMin, _parallelSplitMax);
    });
  }

  Future<void> _persistParallelSplitRatio() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_parallelSplitRatioPrefKey, _parallelSplitRatio);
  }

  void _clearParallelMode() {
    if (_parallelSourceTabId == null && _parallelEnglishTab == null) return;
    if (!mounted) return;
    setState(() {
      _parallelSourceTabId = null;
      _parallelEnglishTab = null;
    });
  }

  bool _isParallelActiveFor(ReaderTab? activeTab) {
    if (activeTab == null) return false;
    if (_parallelSourceTabId == null || _parallelEnglishTab == null) {
      return false;
    }
    if (_parallelSourceTabId != activeTab.id) return false;
    if (activeTab.type != ReaderContentType.bible) return false;
    if (activeTab.book == null || activeTab.chapter == null) return false;
    return true;
  }

  double _parallelPaneFontSize(TypographySettings typography, bool isPrimary) {
    final readerState = ref.read(readerProvider);
    final offset = isPrimary
        ? readerState.primaryFontOffset
        : readerState.secondaryFontOffset;
    return (typography.fontSize + offset).clamp(12.0, 56.0);
  }

  void _adjustParallelPaneFontSize({
    required bool isPrimary,
    required double delta,
  }) {
    if (isPrimary) {
      ref.read(readerProvider.notifier).adjustPrimaryFontOffset(delta);
    } else {
      ref.read(readerProvider.notifier).adjustSecondaryFontOffset(delta);
    }
  }

  Future<void> _onPaneSourceSelected({
    required bool isPrimary,
    required ReaderTab? activeTab,
    String? selectedSource,
    bool forceNewTab = false,
  }) async {
    final picked = selectedSource ?? (await ParallelSourceSheet.show(context));
    if (!mounted || picked == null) return;
    if (isPrimary) {
      await _onSplitViewSourceSelected(activeTab, picked);
      return;
    }

    final notifier = ref.read(readerProvider.notifier);
    final current = _activeSplitRightTab(ref.read(readerProvider));
    final sourceTab = activeTab;
    if (sourceTab == null) return;

    if (picked == 'bible_en' || picked == 'bible_ta') {
      if (sourceTab.type != ReaderContentType.bible ||
          sourceTab.book == null ||
          sourceTab.chapter == null) {
        return;
      }
      final targetLang = picked == 'bible_ta' ? 'ta' : 'en';
      final sourceLang =
          (sourceTab.bibleLang ?? ref.read(selectedBibleLangProvider)) ?? 'en';
      final mappedBook = await _mapBookNameForLanguage(
        sourceBook: sourceTab.book!,
        sourceLang: sourceLang,
        targetLang: targetLang,
      );
      notifier.openSecondaryTab(
        ReaderTab(
          type: ReaderContentType.bible,
          title: '$mappedBook ${sourceTab.chapter}',
          book: mappedBook,
          chapter: sourceTab.chapter,
          verse: sourceTab.verse,
          bibleLang: targetLang,
        ),
        openInNewTab: forceNewTab,
      );
      return;
    }

    final sermonLang = picked == 'sermon_ta' ? 'ta' : 'en';
    final pickedSermon = await _pickSermonForBm(sermonLang);
    if (!mounted || pickedSermon == null) return;
    notifier.openSecondaryTab(
      ReaderTab(
        type: ReaderContentType.sermon,
        title: pickedSermon.title,
        sermonId: pickedSermon.id,
        sermonLang: sermonLang,
      ),
      openInNewTab: forceNewTab || current != null,
    );
  }

  void _adjustReaderFontSize(double delta) {
    final activeTab = ref.read(readerProvider).activeTab;
    final lang =
        activeTab?.bibleLang ?? ref.read(selectedBibleLangProvider) ?? 'en';
    final typography = ref.read(typographyProvider(lang));
    final next = (typography.fontSize + delta).clamp(12.0, 56.0).toDouble();
    if (lang == 'ta') {
      ref.read(taTypographyProvider.notifier).updateFontSize(next);
    } else {
      ref.read(enTypographyProvider.notifier).updateFontSize(next);
    }
  }

  Future<SermonEntity?> _pickSermonForBm(String lang) async {
    final repo = await ref.read(sermonRepositoryByLangProvider(lang).future);
    final sermons = await repo.getSermonsPage(limit: 200, offset: 0);
    if (!mounted || sermons.isEmpty) return null;

    var query = '';
    Future<List<SermonEntity>>? searchFuture;
    return showModalBottomSheet<SermonEntity>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final q = query.trim();
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.75,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search message...',
                        ),
                        onChanged: (value) {
                          setSheetState(() {
                            query = value;
                            final normalized = value.trim();
                            searchFuture = normalized.isEmpty
                                ? null
                                : _searchAllSermonsForPicker(
                                    repo: repo,
                                    lang: lang,
                                    query: normalized,
                                  );
                          });
                        },
                      ),
                    ),
                    Expanded(
                      child: q.isEmpty
                          ? ListView.separated(
                              itemCount: sermons.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final sermon = sermons[index];
                                return ListTile(
                                  title: Text(
                                    sermon.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    [
                                      sermon.id,
                                      if (sermon.year != null)
                                        sermon.year.toString(),
                                    ].join(' • '),
                                  ),
                                  onTap: () => Navigator.of(ctx).pop(sermon),
                                );
                              },
                            )
                          : FutureBuilder<List<SermonEntity>>(
                              future: searchFuture,
                              builder: (context, snapshot) {
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }

                                final results =
                                    snapshot.data ?? const <SermonEntity>[];
                                if (results.isEmpty) {
                                  return const Center(
                                    child: Text('No sermons found.'),
                                  );
                                }

                                return ListView.separated(
                                  itemCount: results.length,
                                  separatorBuilder: (_, __) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final sermon = results[index];
                                    return ListTile(
                                      title: Text(
                                        sermon.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text(
                                        [
                                          sermon.id,
                                          if (sermon.year != null)
                                            sermon.year.toString(),
                                        ].join(' • '),
                                      ),
                                      onTap: () =>
                                          Navigator.of(ctx).pop(sermon),
                                    );
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _pruneVerseAnchorsForTab(String tabId) {
    _bibleVerseAnchorKeys.removeWhere((k, _) => k.startsWith('$tabId|'));
  }

  GlobalKey _ensureBibleVerseKey(ReaderTab tab, int verseNo) {
    final k = '${tab.id}|$verseNo';
    return _bibleVerseAnchorKeys.putIfAbsent(k, GlobalKey.new);
  }

  Future<void> _jumpToBibleVerse(
    int verseNum,
    ReaderTab tab,
    ScrollController controller,
  ) async {
    final activeTab = ref.read(readerProvider).activeTab;
    var verses = (activeTab != null && tab.id == activeTab.id)
        ? _currentVerses
        : _secondaryVerses;

    if (verses.isEmpty || verses.indexWhere((v) => v.verse == verseNum) < 0) {
      try {
        verses = await ref.read(chapterVersesProvider(tab).future);
      } catch (_) {
        verses = const <BibleSearchResult>[];
      }
    }

    if (!mounted) return;
    if (verses.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Chapter is still loading. Try again in a moment.'),
        ),
      );
      return;
    }

    if (verses.indexWhere((v) => v.verse == verseNum) < 0) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('Verse $verseNum is not in this chapter.'),
        ),
      );
      return;
    }

    _ensureBibleVerseKey(tab, verseNum);

    final idx = verses.indexWhere((v) => v.verse == verseNum);
    final lastIdx = verses.length - 1;
    double alignmentFraction() {
      if (verses.length <= 1 || lastIdx <= 0) return 0.0;
      return (idx.clamp(0, lastIdx) / lastIdx).clamp(0.0, 1.0);
    }

    void scheduleScroll({int attempt = 0}) {
      if (!mounted || attempt > 48) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!controller.hasClients) {
          scheduleScroll(attempt: attempt + 1);
          return;
        }
        final maxExtent = controller.position.maxScrollExtent;
        if (maxExtent <= 0) {
          scheduleScroll(attempt: attempt + 1);
          return;
        }

        final target = alignmentFraction() * maxExtent;
        controller
            .animateTo(
              target.clamp(0.0, maxExtent),
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeOutCubic,
            )
            .then((_) {
              if (!mounted) return;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                final ctx = _bibleVerseAnchorKeys['${tab.id}|$verseNum']
                    ?.currentContext;
                if (ctx != null) {
                  Scrollable.ensureVisible(
                    ctx,
                    alignment: 0.1,
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                  );
                }
              });
            });
      });
    }

    scheduleScroll();
  }

  void _submitGotoVerseField(ReaderTab? activeTab) {
    final parsed = int.tryParse(_gotoVerseController.text.trim());
    if (parsed != null && parsed > 0 && activeTab != null) {
      _jumpToPara(parsed, activeTab, _scrollController);
    }
    _gotoVerseFocusNode.unfocus();
  }

  void _jumpToPara(int num, ReaderTab tab, ScrollController controller) {
    if (tab.type == ReaderContentType.bible) {
      unawaited(_jumpToBibleVerse(num, tab, controller));
      return;
    }

    if (!controller.hasClients) return;

    // For Sermons, we need to fetch paragraphs if not already in memory.
    final sermonId = tab.sermonId;
    if (sermonId == null) return;

    ref.read(sermonParagraphsProvider(sermonId).future).then((paragraphs) {
      if (!mounted || !controller.hasClients) return;
      final index = paragraphs.indexWhere((p) => p.paragraphNumber == num);
      if (index >= 0) {
        final frac = (index / paragraphs.length).clamp(0.0, 1.0);
        final target = frac * controller.position.maxScrollExtent;
        controller.animateTo(
          target,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _handleMenuAction(String action, ReaderTab tab) {
    switch (action) {
      case 'copy':
        _copyCurrentReference(tab);
        break;
      case 'share':
        _shareCurrentReference(tab);
        break;
      case 'pdf':
        _generatePdfForTab(tab);
        break;
    }
  }

  void _copyCurrentReference(ReaderTab tab) {
    final refStr = tab.type == ReaderContentType.bible
        ? '${tab.book} ${tab.chapter}'
        : tab.title;
    Clipboard.setData(ClipboardData(text: refStr));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied: $refStr')),
    );
  }

  void _shareCurrentReference(ReaderTab tab) {
    final refStr = tab.type == ReaderContentType.bible
        ? '${tab.book} ${tab.chapter}'
        : tab.title;
    // Assuming Share is available in the environment
    debugPrint('Sharing reference: $refStr');
  }

  void _generatePdfForTab(ReaderTab tab) {
    // PDF generation logic...
    debugPrint('Generating PDF for ${tab.title}');
  }

  Future<List<SermonEntity>> _searchAllSermonsForPicker({
    required SermonRepository repo,
    required String lang,
    required String query,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const <SermonEntity>[];

    final fts = await repo.searchSermons(
      query: trimmed,
      limit: 300,
      offset: 0,
      anyWord: true,
      sortOrder: 'relevance',
    );

    if (fts.isNotEmpty) {
      final byId = <String, SermonEntity>{};
      for (final row in fts) {
        if (byId.containsKey(row.sermonId)) continue;
        byId[row.sermonId] = SermonEntity(
          id: row.sermonId,
          title: row.title,
          language: lang,
          date: row.date,
          year: row.year,
          location: row.location,
        );
      }
      return byId.values.toList();
    }

    return repo.getSermonsPage(
      limit: 500,
      offset: 0,
      searchQuery: trimmed,
      sortBy: 'name_asc',
    );
  }

  Future<void> _enableBmMode(ReaderTab? activeTab) async {
    if (activeTab == null ||
        activeTab.type != ReaderContentType.bible ||
        activeTab.book == null ||
        activeTab.chapter == null) {
      return;
    }

    final bibleLang =
        (activeTab.bibleLang ?? ref.read(selectedBibleLangProvider)) ?? 'en';
    final hasSermonDb = await ref.read(
      sermonDatabaseExistsProvider(bibleLang).future,
    );

    if (!hasSermonDb) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const OnboardingScreen(showImportDirectly: true),
        ),
      );
      return;
    }

    final picked = await _pickSermonForBm(bibleLang);
    if (!mounted || picked == null) return;

    ref.read(selectedSermonLangProvider.notifier).setLang(bibleLang);

    if (_isParallelActiveFor(activeTab)) {
      _clearParallelMode();
    }

    final bmMode = ref.read(readerProvider).bmMode;
    final added = ref
        .read(readerProvider.notifier)
        .upsertBmMessageTab(
          id: picked.id,
          title: picked.title,
          openInNewTab: bmMode,
        );
    if (!added && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Split view tab limit reached (20).')),
      );
    }
  }

  Future<void> _changeBmMessage(ReaderTab? activeTab) async {
    if (activeTab == null) return;
    final bibleLang =
        (activeTab.bibleLang ?? ref.read(selectedBibleLangProvider)) ?? 'en';
    final picked = await _pickSermonForBm(bibleLang);
    if (!mounted || picked == null) return;
    ref.read(selectedSermonLangProvider.notifier).setLang(bibleLang);
    final added = ref
        .read(readerProvider.notifier)
        .upsertBmMessageTab(
          id: picked.id,
          title: picked.title,
          openInNewTab: false,
        );
    final splitAdded = ref
        .read(readerProvider.notifier)
        .upsertSplitRightTab(
          tab: ReaderTab(
            type: ReaderContentType.sermon,
            title: picked.title,
            sermonId: picked.id,
            sermonLang: bibleLang,
          ),
          openInNewTab: false,
        );
    if (!added && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Split view tab limit reached (20).')),
      );
    }
    if (!splitAdded && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Split view tab limit reached (20).')),
      );
    }
  }

  Widget _buildBmMessagePane({
    required ReaderTab activeBibleTab,
    required TypographySettings typography,
  }) {
    final readerState = ref.watch(readerProvider);
    final messageTabs = readerState.bmMessageTabs;
    final activeIndex = readerState.bmMessageActiveIndex;
    final isCompact = MediaQuery.sizeOf(context).width < 640;
    final bibleLang =
        (activeBibleTab.bibleLang ?? ref.watch(selectedBibleLangProvider)) ??
        'en';
    final sermonDbExists = ref.watch(sermonDatabaseExistsProvider(bibleLang));

    if (sermonDbExists.maybeWhen(
      data: (exists) => !exists,
      orElse: () => false,
    )) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40),
              const SizedBox(height: 10),
              Text(
                'Sermon database is not installed',
                style: Theme.of(context).textTheme.titleMedium,
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

    final activeMessageTab = messageTabs.isEmpty
        ? null
        : messageTabs[activeIndex.clamp(0, messageTabs.length - 1)];

    if (messageTabs.length <= 1) {
      _bmTabChipKeys..removeWhere((key, value) => true);
      _lastBmAutoScrollTabId = null;
    } else {
      final liveIds = messageTabs.map((t) => t.id).toSet();
      _bmTabChipKeys.removeWhere((key, value) => !liveIds.contains(key));
      _syncBmTabAutoScroll(tabs: messageTabs, activeIndex: activeIndex);
    }

    if (activeMessageTab == null) {
      return Center(
        child: FilledButton.icon(
          onPressed: () => _changeBmMessage(activeBibleTab),
          icon: const Icon(Icons.library_books_outlined),
          label: const Text('Select Message'),
        ),
      );
    }

    final paragraphsAsync = ref.watch(
      sermonParagraphsProvider(activeMessageTab.id),
    );
    final sermonTitle = activeMessageTab.title;

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 8 : 10,
            vertical: isCompact ? 4 : 6,
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  sermonTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.symmetric(
                    horizontal: isCompact ? 8 : 12,
                    vertical: 6,
                  ),
                ),
                onPressed: () => _changeBmMessage(activeBibleTab),
                child: Text(isCompact ? 'Pick' : 'Change'),
              ),
              IconButton(
                tooltip: 'Open message in new tab',
                visualDensity: VisualDensity.compact,
                onPressed: () async {
                  final bibleLang =
                      (activeBibleTab.bibleLang ??
                          ref.read(selectedBibleLangProvider)) ??
                      'en';
                  final picked = await _pickSermonForBm(bibleLang);
                  if (!mounted || picked == null) return;
                  ref
                      .read(selectedSermonLangProvider.notifier)
                      .setLang(bibleLang);
                  final added = ref
                      .read(readerProvider.notifier)
                      .upsertBmMessageTab(
                        id: picked.id,
                        title: picked.title,
                        openInNewTab: true,
                      );
                  final splitAdded = ref
                      .read(readerProvider.notifier)
                      .upsertSplitRightTab(
                        tab: ReaderTab(
                          type: ReaderContentType.sermon,
                          title: picked.title,
                          sermonId: picked.id,
                          sermonLang: bibleLang,
                        ),
                        openInNewTab: true,
                      );
                  if (!added && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Split view tab limit reached (20).'),
                      ),
                    );
                  }
                  if (!splitAdded && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Split view tab limit reached (20).'),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
        if (messageTabs.length > 1)
          SizedBox(
            height: isCompact ? 36 : 40,
            child: ListView.builder(
              controller: _bmTabsScrollController,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              scrollDirection: Axis.horizontal,
              itemCount: messageTabs.length,
              itemBuilder: (context, index) {
                final tab = messageTabs[index];
                final isActive = index == activeIndex;
                final chipKey = _bmTabChipKeys.putIfAbsent(
                  tab.id,
                  () => GlobalKey(),
                );
                return Container(
                  key: chipKey,
                  margin: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  padding: EdgeInsets.symmetric(horizontal: isCompact ? 8 : 10),
                  decoration: BoxDecoration(
                    color: isActive
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: () => ref
                            .read(readerProvider.notifier)
                            .setActiveBmMessageTab(index),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: isCompact ? 5 : 6,
                          ),
                          child: Tooltip(
                            message: tab.title,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: isCompact ? 130 : 220,
                              ),
                              child: Text(
                                tab.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () => ref
                            .read(readerProvider.notifier)
                            .closeBmMessageTab(index),
                        child: Icon(Icons.close, size: isCompact ? 15 : 16),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        Expanded(
          child: paragraphsAsync.when(
            data: (paragraphs) {
              if (paragraphs.isEmpty) {
                return const Center(
                  child: Text('No message paragraphs found.'),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                itemCount: paragraphs.length,
                itemBuilder: (context, index) {
                  final p = paragraphs[index];
                  final body = p.text.trim();
                  if (body.isEmpty) return const SizedBox.shrink();
                  final label = p.paragraphNumber != null
                      ? '${p.paragraphNumber} '
                      : '';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SelectableText.rich(
                      TextSpan(
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontSize: typography.fontSize,
                          height: typography.lineHeight,
                          fontFamily: typography.resolvedFontFamily,
                        ),
                        children: [
                          if (label.isNotEmpty)
                            TextSpan(
                              text: label,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          TextSpan(text: body),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('$err', textAlign: TextAlign.center),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBmSplitContent({
    required ReaderTab bibleTab,
    required TypographySettings typography,
  }) {
    final bmRatio = ref.watch(readerProvider.select((s) => s.bmSplitRatio));
    final biblePane = _buildTabContent(bibleTab, typography);
    final messagePane = _buildBmMessagePane(
      activeBibleTab: bibleTab,
      typography: typography,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= _parallelWideBreakpoint;
        final ratio = bmRatio.clamp(_bmSplitMin, _bmSplitMax);

        if (isWide) {
          const dividerHeaderInset = 56.0;
          final leftWidth = constraints.maxWidth * ratio;
          final rightWidth =
              constraints.maxWidth - leftWidth - _bmSplitterWidth;
          return Row(
            children: [
              SizedBox(width: leftWidth, child: biblePane),
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (details) {
                  if (constraints.maxWidth <= 0) return;
                  final currentRatio = ref.read(readerProvider).bmSplitRatio;
                  final next =
                      (currentRatio + details.delta.dx / constraints.maxWidth)
                          .clamp(_bmSplitMin, _bmSplitMax)
                          .toDouble();
                  ref
                      .read(readerProvider.notifier)
                      .setBmSplitRatio(next, persist: false);
                },
                onHorizontalDragEnd: (_) {
                  unawaited(ref.read(readerProvider.notifier).persistBmState());
                },
                onDoubleTap: () {
                  ref
                      .read(readerProvider.notifier)
                      .setBmSplitRatio(_bmSplitDefault);
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: Center(
                    child: Container(
                      width: 28,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                          width: 1.2,
                        ),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.drag_handle, size: 16),
                            SizedBox(height: 2),
                            Icon(Icons.drag_handle, size: 16),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: rightWidth, child: messagePane),
            ],
          );
        }

        final topFlex = (ratio * 100).round().clamp(35, 75);
        final bottomFlex = 100 - topFlex;
        return Column(
          children: [
            Expanded(flex: topFlex, child: biblePane),
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onVerticalDragUpdate: (details) {
                final height = constraints.maxHeight;
                if (height <= 0) return;
                final currentRatio = ratio / 100.0;
                final next = ((currentRatio + details.delta.dy / height).clamp(
                  _bmSplitMin,
                  _bmSplitMax,
                )).toDouble();
                ref
                    .read(readerProvider.notifier)
                    .setBmSplitRatio(next, persist: false);
              },
              onVerticalDragEnd: (_) {
                unawaited(ref.read(readerProvider.notifier).persistBmState());
              },
              onDoubleTap: () {
                ref
                    .read(readerProvider.notifier)
                    .setBmSplitRatio(_bmSplitDefault);
              },
              child: Center(
                child: Container(
                  width: 48,
                  height: _bmSplitterWidth * 2.5,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline,
                      width: 1.2,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.drag_handle, size: 18),
                      SizedBox(height: 2),
                      Icon(Icons.drag_handle, size: 18),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(flex: bottomFlex, child: messagePane),
          ],
        );
      },
    );
  }

  Future<void> _openAdjacentParallelBiblePassage(int direction) async {
    final activeTab = ref.read(readerProvider).activeTab;
    final englishTab = _parallelEnglishTab;
    if (activeTab == null) return;
    if (activeTab.type != ReaderContentType.bible ||
        activeTab.book == null ||
        activeTab.chapter == null) {
      return;
    }

    final sourceLang =
        (activeTab.bibleLang ?? ref.read(selectedBibleLangProvider)) ?? 'en';
    final books = await ref.read(
      bibleBookListByLangProvider(sourceLang).future,
    );
    if (books.isEmpty) return;

    final sortedBooks = [...books]
      ..sort((a, b) {
        final first = a['book_index'] as int? ?? 1;
        final second = b['book_index'] as int? ?? 1;
        return first.compareTo(second);
      });

    final currentBook = activeTab.book!;
    final currentChapter = activeTab.chapter!;
    var currentBookIndex = sortedBooks.indexWhere((book) {
      return (book['book'] as String?) == currentBook;
    });
    if (currentBookIndex < 0) {
      final normalizedCurrent = currentBook.trim().toLowerCase();
      currentBookIndex = sortedBooks.indexWhere((book) {
        final name = (book['book'] as String? ?? '').trim().toLowerCase();
        return name == normalizedCurrent;
      });
    }
    if (currentBookIndex < 0) return;

    var nextBookIndex = currentBookIndex;
    var nextChapter = currentChapter;

    if (direction > 0) {
      final currentBookChapters =
          sortedBooks[currentBookIndex]['chapters'] as int? ?? 1;
      if (currentChapter < currentBookChapters) {
        nextChapter = currentChapter + 1;
      } else if (currentBookIndex < sortedBooks.length - 1) {
        nextBookIndex = currentBookIndex + 1;
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
      } else if (currentBookIndex > 0) {
        nextBookIndex = currentBookIndex - 1;
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

    final nextSourceBook = sortedBooks[nextBookIndex]['book'] as String;
    final nextSourceTab = activeTab.copyWith(
      title: '$nextSourceBook $nextChapter',
      book: nextSourceBook,
      chapter: nextChapter,
      verse: null,
      initialSearchQuery: null,
      openedFromSearch: false,
    );

    ref.read(readerProvider.notifier).replaceCurrentTab(nextSourceTab);
    if (!mounted) return;
    if (englishTab != null) {
      final mappedEnglishBook = await _mapBookNameForLanguage(
        sourceBook: nextSourceBook,
        sourceLang: sourceLang,
        targetLang: 'en',
      );

      final nextEnglishTab = englishTab.copyWith(
        title: '$mappedEnglishBook $nextChapter',
        book: mappedEnglishBook,
        chapter: nextChapter,
        verse: null,
        bibleLang: 'en',
        initialSearchQuery: null,
        openedFromSearch: false,
      );
      if (!mounted) return;
      setState(() {
        _parallelEnglishTab = nextEnglishTab;
      });
      return;
    }

    setState(() {
      _selectedVerseNumbers.clear();
      _activeSelectionText = null;
      _lastVerseTapped = null;
    });
  }

  Future<void> _openParallelQuickNav({required bool forPrimaryPane}) async {
    final activeTab = ref.read(readerProvider).activeTab;
    final englishTab = _parallelEnglishTab;
    if (activeTab == null || englishTab == null) return;
    if (activeTab.type != ReaderContentType.bible ||
        activeTab.book == null ||
        activeTab.chapter == null) {
      return;
    }

    final sourceLang =
        (activeTab.bibleLang ?? ref.read(selectedBibleLangProvider)) ?? 'en';
    final pickerLang = forPrimaryPane ? sourceLang : 'en';
    final result = await showResponsiveBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      maxWidth: 980,
      builder: (_) => QuickNavigationSheet(initialLang: pickerLang),
    );
    if (result == null) return;

    final selectedBook = result['book'] as String?;
    final selectedChapter = result['chapter'] as int?;
    final selectedVerse = result['verse'] as int?;
    if (selectedBook == null || selectedChapter == null) return;

    late final ReaderTab nextSourceTab;
    late final ReaderTab nextEnglishTab;

    if (forPrimaryPane) {
      final mappedEnglishBook = await _mapBookNameForLanguage(
        sourceBook: selectedBook,
        sourceLang: sourceLang,
        targetLang: 'en',
      );

      nextSourceTab = activeTab.copyWith(
        title: '$selectedBook $selectedChapter',
        book: selectedBook,
        chapter: selectedChapter,
        verse: selectedVerse,
        initialSearchQuery: null,
        openedFromSearch: false,
      );

      nextEnglishTab = englishTab.copyWith(
        title: '$mappedEnglishBook $selectedChapter',
        book: mappedEnglishBook,
        chapter: selectedChapter,
        verse: selectedVerse,
        bibleLang: 'en',
        initialSearchQuery: null,
        openedFromSearch: false,
      );
    } else {
      final mappedSourceBook = await _mapBookNameForLanguage(
        sourceBook: selectedBook,
        sourceLang: 'en',
        targetLang: sourceLang,
      );

      nextEnglishTab = englishTab.copyWith(
        title: '$selectedBook $selectedChapter',
        book: selectedBook,
        chapter: selectedChapter,
        verse: selectedVerse,
        bibleLang: 'en',
        initialSearchQuery: null,
        openedFromSearch: false,
      );

      nextSourceTab = activeTab.copyWith(
        title: '$mappedSourceBook $selectedChapter',
        book: mappedSourceBook,
        chapter: selectedChapter,
        verse: selectedVerse,
        initialSearchQuery: null,
        openedFromSearch: false,
      );
    }

    ref.read(readerProvider.notifier).replaceCurrentTab(nextSourceTab);
    if (!mounted) return;
    setState(() {
      _parallelEnglishTab = nextEnglishTab;
      _selectedVerseNumbers.clear();
      _activeSelectionText = null;
      _lastVerseTapped = null;
    });
  }

  String _splitTabIdentity(ReaderTab tab) {
    if (tab.type == ReaderContentType.sermon) {
      return 'sermon:${tab.sermonId}:${tab.sermonLang ?? 'en'}';
    }
    return 'bible:${tab.book}:${tab.chapter}:${tab.bibleLang ?? 'en'}';
  }

  ReaderTab? _activeSplitRightTab(ReaderState state) {
    if (state.splitRightTabs.isEmpty) return null;
    final safeIndex = state.splitRightActiveIndex.clamp(
      0,
      state.splitRightTabs.length - 1,
    );
    return state.splitRightTabs[safeIndex];
  }

  void _syncSplitTabAutoScroll({
    required List<ReaderTab> tabs,
    required int activeIndex,
  }) {
    if (tabs.length <= 1) {
      _lastSplitAutoScrollTabId = null;
      return;
    }

    final safeIndex = activeIndex.clamp(0, tabs.length - 1);
    final activeIdentity = _splitTabIdentity(tabs[safeIndex]);
    if (_lastSplitAutoScrollTabId == activeIdentity) return;
    _lastSplitAutoScrollTabId = activeIdentity;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final targetContext = _splitTabChipKeys[activeIdentity]?.currentContext;
      if (targetContext != null) {
        Scrollable.ensureVisible(
          targetContext,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: 0.5,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        );
        return;
      }

      if (!_splitTabsScrollController.hasClients) return;
      final estimatedOffset = (safeIndex * 160.0).clamp(
        0.0,
        _splitTabsScrollController.position.maxScrollExtent,
      );
      _splitTabsScrollController.animateTo(
        estimatedOffset,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _openAdjacentSplitRightBiblePassage({
    required ReaderTab sourceLeftTab,
    required ReaderTab rightBibleTab,
    required int direction,
  }) async {
    if (rightBibleTab.book == null || rightBibleTab.chapter == null) return;
    final lang = (rightBibleTab.bibleLang ?? sourceLeftTab.bibleLang) ?? 'en';
    final books = await ref.read(bibleBookListByLangProvider(lang).future);
    if (books.isEmpty) return;

    final sortedBooks = [...books]
      ..sort((a, b) {
        final first = a['book_index'] as int? ?? 1;
        final second = b['book_index'] as int? ?? 1;
        return first.compareTo(second);
      });

    final currentBook = rightBibleTab.book!;
    final currentChapter = rightBibleTab.chapter!;
    var currentBookIndex = sortedBooks.indexWhere((book) {
      return (book['book'] as String?) == currentBook;
    });
    if (currentBookIndex < 0) {
      final normalizedCurrent = currentBook.trim().toLowerCase();
      currentBookIndex = sortedBooks.indexWhere((book) {
        final name = (book['book'] as String? ?? '').trim().toLowerCase();
        return name == normalizedCurrent;
      });
    }
    if (currentBookIndex < 0) return;

    var nextBookIndex = currentBookIndex;
    var nextChapter = currentChapter;
    if (direction > 0) {
      final chapterCount =
          sortedBooks[currentBookIndex]['chapters'] as int? ?? 1;
      if (currentChapter < chapterCount) {
        nextChapter = currentChapter + 1;
      } else if (currentBookIndex < sortedBooks.length - 1) {
        nextBookIndex = currentBookIndex + 1;
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
      } else if (currentBookIndex > 0) {
        nextBookIndex = currentBookIndex - 1;
        nextChapter = sortedBooks[nextBookIndex]['chapters'] as int? ?? 1;
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
    ref
        .read(readerProvider.notifier)
        .replaceActiveSplitRightTab(
          rightBibleTab.copyWith(
            title: '$nextBook $nextChapter',
            book: nextBook,
            chapter: nextChapter,
            verse: null,
            bibleLang: lang,
          ),
        );
  }

  Future<void> _openSplitRightBibleQuickNav({
    required ReaderTab sourceLeftTab,
    required ReaderTab rightBibleTab,
  }) async {
    final lang = (rightBibleTab.bibleLang ?? sourceLeftTab.bibleLang) ?? 'en';
    final result = await showResponsiveBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      maxWidth: 980,
      builder: (_) => QuickNavigationSheet(initialLang: lang),
    );
    if (result == null) return;

    final selectedBook = result['book'] as String?;
    final selectedChapter = result['chapter'] as int?;
    final selectedVerse = result['verse'] as int?;
    if (selectedBook == null || selectedChapter == null) return;

    ref
        .read(readerProvider.notifier)
        .replaceActiveSplitRightTab(
          rightBibleTab.copyWith(
            title: '$selectedBook $selectedChapter',
            book: selectedBook,
            chapter: selectedChapter,
            verse: selectedVerse,
            bibleLang: lang,
          ),
        );
  }

  Future<void> _openAdjacentSplitRightSermon({
    required ReaderTab rightSermonTab,
    required int direction,
  }) async {
    final id = rightSermonTab.sermonId;
    if (id == null || id.isEmpty) return;
    final lang =
        rightSermonTab.sermonLang ??
        ref.read(selectedSermonLangProvider) ??
        'en';
    final repo = await ref.read(sermonRepositoryByLangProvider(lang).future);
    final adjacent = await repo.getAdjacentSermon(id, direction);
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
        .read(readerProvider.notifier)
        .replaceActiveSplitRightTab(
          rightSermonTab.copyWith(
            title: adjacent.title,
            sermonId: adjacent.id,
            sermonLang: lang,
          ),
        );
  }

  Future<void> _changeSplitRightSermon(ReaderTab rightSermonTab) async {
    final lang =
        rightSermonTab.sermonLang ??
        ref.read(selectedSermonLangProvider) ??
        'en';
    final picked = await _pickSermonForBm(lang);
    if (!mounted || picked == null) return;
    ref
        .read(readerProvider.notifier)
        .replaceActiveSplitRightTab(
          rightSermonTab.copyWith(
            title: picked.title,
            sermonId: picked.id,
            sermonLang: lang,
          ),
        );
  }

  Widget _buildSplitSermonPane({
    required ReaderTab sermonTab,
    required TypographySettings typography,
    required double bodyFontSize,
    bool showHeaderControls = true,
    ScrollController? controller,
  }) {
    final sermonId = sermonTab.sermonId;
    final sermonLang =
        (sermonTab.sermonLang ?? ref.watch(selectedSermonLangProvider)) ?? 'en';

    if (sermonId == null || sermonId.isEmpty) {
      return const Center(child: Text('No sermon selected.'));
    }

    final paragraphsFuture = _getSplitSermonParagraphsFuture(
      sermonLang: sermonLang,
      sermonId: sermonId,
    );

    return Column(
      children: [
        Expanded(
          child: FutureBuilder<List<SermonParagraphEntity>>(
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
              final paragraphs =
                  snapshot.data ?? const <SermonParagraphEntity>[];
              if (paragraphs.isEmpty) {
                return const Center(
                  child: Text('No message paragraphs found.'),
                );
              }

              return ListView.builder(
                controller: controller,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                itemCount: paragraphs.length,
                itemBuilder: (context, index) {
                  final p = paragraphs[index];
                  final body = p.text.trim();
                  if (body.isEmpty) return const SizedBox.shrink();

                  final label = p.paragraphNumber != null
                      ? '${p.paragraphNumber} '
                      : '';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SelectableText.rich(
                      TextSpan(
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontSize: bodyFontSize,
                          height: typography.lineHeight,
                          fontFamily: typography.resolvedFontFamily,
                        ),
                        children: [
                          if (label.isNotEmpty)
                            TextSpan(
                              text: label,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          TextSpan(text: body),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildUnifiedSplitContent({
    required ReaderTab bibleTab,
    required ReaderState readerState,
    required TypographySettings typography,
  }) {
    final splitTabs = readerState.splitRightTabs;
    final splitIndex = readerState.splitRightActiveIndex.clamp(
      0,
      splitTabs.length - 1,
    );
    final activeRightTab = splitTabs[splitIndex];
    final splitRatio = readerState.splitViewRatio;
    final isCompact = MediaQuery.sizeOf(context).width < 640;

    if (splitTabs.length <= 1) {
      _splitTabChipKeys..removeWhere((key, value) => true);
      _lastSplitAutoScrollTabId = null;
    } else {
      final liveIds = splitTabs.map(_splitTabIdentity).toSet();
      _splitTabChipKeys.removeWhere((key, value) => !liveIds.contains(key));
      _syncSplitTabAutoScroll(tabs: splitTabs, activeIndex: splitIndex);
    }

    final biblePane = _buildTabContent(bibleTab, typography);
    final splitSermonFontSize = _parallelPaneFontSize(typography, false);
    final rightPane = activeRightTab.type == ReaderContentType.bible
        ? _buildParallelBiblePanel(
            tab: activeRightTab,
            typography: typography,
            controller: _parallelSecondaryScrollController,
            panelTitle: _languageLabel(activeRightTab.bibleLang ?? 'en'),
            panelSubtitle:
                '${activeRightTab.book ?? ''} ${activeRightTab.chapter ?? ''}'
                    .trim(),
            showControls: true,
            isPrimaryPane: false,
            onPrevious: () => _openAdjacentSplitRightBiblePassage(
              sourceLeftTab: bibleTab,
              rightBibleTab: activeRightTab,
              direction: -1,
            ),
            onNext: () => _openAdjacentSplitRightBiblePassage(
              sourceLeftTab: bibleTab,
              rightBibleTab: activeRightTab,
              direction: 1,
            ),
            onAllBooks: () => _openSplitRightBibleQuickNav(
              sourceLeftTab: bibleTab,
              rightBibleTab: activeRightTab,
            ),
            allBooksLabel: 'All Books',
          )
        : _buildSplitSermonPane(
            sermonTab: activeRightTab,
            typography: typography,
            bodyFontSize: splitSermonFontSize,
            controller: _parallelSecondaryScrollController,
          );

    final rightPaneWithTabs = Column(
      children: [
        if (splitTabs.length > 1)
          SizedBox(
            height: isCompact ? 36 : 40,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // We'll show scroll buttons if the scroll extent is greater than the viewport
                final showScrollButtons =
                    _splitTabsScrollController.hasClients &&
                    _splitTabsScrollController.position.maxScrollExtent > 0.0;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    ListView.builder(
                      controller: _splitTabsScrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      scrollDirection: Axis.horizontal,
                      itemCount: splitTabs.length,
                      itemBuilder: (context, index) {
                        final tab = splitTabs[index];
                        final isActive = index == splitIndex;
                        final tabKey = _splitTabIdentity(tab);
                        final chipKey = _splitTabChipKeys.putIfAbsent(
                          tabKey,
                          () => GlobalKey(),
                        );
                        final title = tab.type == ReaderContentType.bible
                            ? '${tab.book ?? ''} ${tab.chapter ?? ''}'.trim()
                            : tab.title;
                        return Container(
                          key: chipKey,
                          margin: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: isCompact ? 8 : 10,
                          ),
                          decoration: BoxDecoration(
                            color: isActive
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Theme.of(
                                context,
                              ).colorScheme.outlineVariant,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                onTap: () => ref
                                    .read(readerProvider.notifier)
                                    .setActiveSplitRightTab(index),
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                    vertical: isCompact ? 5 : 6,
                                  ),
                                  child: Tooltip(
                                    message: title,
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxWidth: isCompact ? 130 : 220,
                                      ),
                                      child: Text(
                                        title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: () => ref
                                    .read(readerProvider.notifier)
                                    .closeSplitRightTab(index),
                                child: Icon(
                                  Icons.close,
                                  size: isCompact ? 15 : 16,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    if (showScrollButtons)
                      Positioned(
                        left: 0,
                        child: IconButton(
                          icon: const Icon(Icons.chevron_left),
                          tooltip: 'Scroll left',
                          onPressed: () {
                            if (_splitTabsScrollController.hasClients) {
                              final pos =
                                  _splitTabsScrollController.position.pixels;
                              _splitTabsScrollController.animateTo(
                                (pos - 120).clamp(
                                  0.0,
                                  _splitTabsScrollController
                                      .position
                                      .maxScrollExtent,
                                ),
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOut,
                              );
                            }
                          },
                        ),
                      ),
                    if (showScrollButtons)
                      Positioned(
                        right: 0,
                        child: IconButton(
                          icon: const Icon(Icons.chevron_right),
                          tooltip: 'Scroll right',
                          onPressed: () {
                            if (_splitTabsScrollController.hasClients) {
                              final pos =
                                  _splitTabsScrollController.position.pixels;
                              _splitTabsScrollController.animateTo(
                                (pos + 120).clamp(
                                  0.0,
                                  _splitTabsScrollController
                                      .position
                                      .maxScrollExtent,
                                ),
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOut,
                              );
                            }
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        Expanded(child: rightPane),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= _parallelWideBreakpoint;
        final ratio = splitRatio.clamp(_bmSplitMin, _bmSplitMax);
        if (isWide) {
          final leftWidth = constraints.maxWidth * ratio;
          final rightWidth =
              constraints.maxWidth - leftWidth - _bmSplitterWidth;
          return Row(
            children: [
              SizedBox(width: leftWidth, child: biblePane),
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (details) {
                  if (constraints.maxWidth <= 0) return;
                  final currentRatio = ref.read(readerProvider).splitViewRatio;
                  final next =
                      (currentRatio + details.delta.dx / constraints.maxWidth)
                          .clamp(_bmSplitMin, _bmSplitMax)
                          .toDouble();
                  ref
                      .read(readerProvider.notifier)
                      .setSplitViewRatio(next, persist: false);
                },
                onHorizontalDragEnd: (_) {
                  ref
                      .read(readerProvider.notifier)
                      .setSplitViewRatio(
                        ref.read(readerProvider).splitViewRatio,
                        persist: true,
                      );
                },
                onDoubleTap: () {
                  ref
                      .read(readerProvider.notifier)
                      .setSplitViewRatio(_bmSplitDefault);
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: Container(
                    width: _bmSplitterWidth,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              SizedBox(width: rightWidth, child: rightPaneWithTabs),
            ],
          );
        }

        final topFlex = (ratio * 100).round().clamp(35, 75);
        final bottomFlex = 100 - topFlex;
        return Column(
          children: [
            Expanded(flex: topFlex, child: biblePane),
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onVerticalDragUpdate: (details) {
                final height = constraints.maxHeight;
                if (height <= 0) return;
                final next = (ratio + details.delta.dy / height)
                    .clamp(_bmSplitMin, _bmSplitMax)
                    .toDouble();
                ref
                    .read(readerProvider.notifier)
                    .setSplitViewRatio(next, persist: false);
              },
              onVerticalDragEnd: (_) {
                ref
                    .read(readerProvider.notifier)
                    .setSplitViewRatio(
                      ref.read(readerProvider).splitViewRatio,
                      persist: true,
                    );
              },
              onDoubleTap: () {
                ref
                    .read(readerProvider.notifier)
                    .setSplitViewRatio(_bmSplitDefault);
              },
              child: Container(
                height: _bmSplitterWidth,
                color: Theme.of(context).colorScheme.outlineVariant,
                child: Center(
                  child: Container(
                    width: 48,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(flex: bottomFlex, child: rightPaneWithTabs),
          ],
        );
      },
    );
  }

  Widget _buildReaderSplitContentV2({
    required ReaderTab bibleTab,
    required ReaderState readerState,
    required TypographySettings typography,
  }) {
    final readerTabs = ref.watch(readerProvider.select((s) => s.tabs));
    final activeTabIndex = ref.watch(
      readerProvider.select((s) => s.activeTabIndex),
    );

    if (readerState.secondaryTabs.isEmpty) {
      return Column(
        children: [
          if (!typography.isFullscreen && readerTabs.isNotEmpty)
            BottomTabRail(
              tabs: readerTabs,
              activeIndex: activeTabIndex,
              onTapTab: (index) => _onMainTabTap(index, readerTabs),
              onCloseTab: (index) =>
                  ref.read(readerProvider.notifier).closeTab(index),
              onOpenNew: _openQuickNav,
            ),
          Expanded(child: _buildTabContent(bibleTab, typography)),
        ],
      );
    }

    final secondaryTabs = readerState.secondaryTabs;
    final secondaryIndex = readerState.secondaryActiveIndex.clamp(
      0,
      secondaryTabs.length - 1,
    );
    final activeSecondary = secondaryTabs[secondaryIndex];

    final primaryContent = _buildTabContent(
      bibleTab,
      typography.copyWith(fontSize: _parallelPaneFontSize(typography, true)),
    );
    final secondarySplitSermonFontSize =
        _parallelPaneFontSize(typography, false);
    final secondaryContent = activeSecondary.type == ReaderContentType.bible
        ? _buildParallelBiblePanel(
            tab: activeSecondary,
            typography: typography,
            controller: _parallelSecondaryScrollController,
            panelTitle: _languageLabel(activeSecondary.bibleLang ?? 'en'),
            panelSubtitle:
                '${activeSecondary.book ?? ''} ${activeSecondary.chapter ?? ''}'
                    .trim(),
            showHeader: false,
            showControls: false,
            isPrimaryPane: false,
            searchQuery: _secondaryMiniSearchController.text,
            searchMatchVerseIndices: _secondaryMatchVerseIndices,
            searchCurrentMatchIndex: _secondaryCurrentMatchIndex,
            onVersesResolved: (verses) {
              final signature =
                  '${activeSecondary.id}:${activeSecondary.book}:${activeSecondary.chapter}';
              if (_lastSecondaryChapterSignature != signature ||
                  _secondaryVerses.length != verses.length) {
                _lastSecondaryChapterSignature = signature;
                _secondaryVerses = verses;
                if (_secondaryMiniSearchController.text.trim().isNotEmpty) {
                  _computeSecondaryBibleMatches(
                    _secondaryMiniSearchController.text,
                    scrollToMatch: false,
                  );
                }
              }
            },
          )
        : _buildSplitSermonPane(
            sermonTab: activeSecondary,
            typography: typography,
            bodyFontSize: secondarySplitSermonFontSize,
            showHeaderControls: false,
            controller: _parallelSecondaryScrollController,
          );

    final primaryPane = Column(
      children: [
        PaneHeader(
          tab: bibleTab,
          isPrimary: true,
          displayFontSize: _parallelPaneFontSize(typography, true),
          isSearchActive: _primaryMiniSearchActive,
          onOpenPicker: () => _openQuickNav(
            initialLang: bibleTab.bibleLang,
            initialOpenInNewTab: false,
          ),
          onPrev: () => _openAdjacentParallelBiblePassage(-1),
          onNext: () => _openAdjacentParallelBiblePassage(1),
          onDecreaseFont: () =>
              _adjustParallelPaneFontSize(isPrimary: true, delta: -1),
          onIncreaseFont: () =>
              _adjustParallelPaneFontSize(isPrimary: true, delta: 1),
          onToggleSearch: () {
            setState(() {
              _primaryMiniSearchActive = !_primaryMiniSearchActive;
              if (_primaryMiniSearchActive) {
                _isSearching = true;
                _searchScope = BibleSearchScope.chapter;
                _searchController.text = _primaryMiniSearchController.text;
                _computeMatches(_searchController.text);
              }
            });
          },
          onSourceSelected: (value) => _onPaneSourceSelected(
            isPrimary: true,
            activeTab: bibleTab,
            selectedSource: value,
          ),
          onDisableSplitView: () {
            _clearParallelMode();
            ref.read(readerProvider.notifier).closeSecondaryPane();
          },
          onMenuSelected: (val) => _handleMenuAction(val, bibleTab),
        ),
        if (!typography.isFullscreen && readerTabs.isNotEmpty)
          BottomTabRail(
            tabs: readerTabs,
            activeIndex: activeTabIndex,
            onTapTab: (index) => _onMainTabTap(index, readerTabs),
            onCloseTab: (index) =>
                ref.read(readerProvider.notifier).closeTab(index),
            onOpenNew: _openQuickNav,
          ),
        Expanded(
          child: ReadingPane(
            child: primaryContent,
            isSearchActive: _primaryMiniSearchActive,
            searchController: _primaryMiniSearchController,
            searchFocusNode: _primaryMiniSearchFocusNode,
            matchCounterText: _totalMatches > 0
                ? '${_currentMatchIndex + 1}/$_totalMatches'
                : '0/0',
            onSearchChanged: (value) {
              setState(() {
                _isSearching = true;
                _searchScope = BibleSearchScope.chapter;
                _searchController.text = value;
                _computeMatches(value);
              });
            },
            onPrevMatch: () => _navigateToMatch(-1),
            onNextMatch: () => _navigateToMatch(1),
            onCloseSearch: () {
              setState(() {
                _primaryMiniSearchActive = false;
                _resetGlobalSearchState(clearQuery: false);
              });
            },
          ),
        ),
        PaneGotoBar(
          tab: bibleTab,
          onGoto: (value) => _jumpToPara(value, bibleTab, _scrollController),
        ),
      ],
    );

    final rightPaneTabs = SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: secondaryTabs.length,
              itemBuilder: (context, index) {
                final tab = secondaryTabs[index];
                final isActive = index == secondaryIndex;
                final title = tab.type == ReaderContentType.bible
                    ? '${tab.book ?? ''} ${tab.chapter ?? ''}'.trim()
                    : tab.title;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  child: FilterChip(
                    selected: isActive,
                    label: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onSelected: (_) async {
                      if (isActive) {
                        if (tab.type == ReaderContentType.bible) {
                          await _openSplitRightBibleQuickNav(
                            sourceLeftTab: bibleTab,
                            rightBibleTab: tab,
                          );
                          return;
                        }

                        await _changeSplitRightSermon(tab);
                        return;
                      }

                      ref
                          .read(readerProvider.notifier)
                          .setActiveSecondaryTab(index);
                      setState(() {
                        _secondaryMiniSearchController.clear();
                        _secondaryMatchVerseIndices = [];
                        _secondaryTotalMatches = 0;
                        _secondaryCurrentMatchIndex = 0;
                        _lastSecondaryChapterSignature = null;
                        _secondaryVerses = [];
                      });
                    },
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => ref
                        .read(readerProvider.notifier)
                        .closeSecondaryTab(index),
                  ),
                );
              },
            ),
          ),
          IconButton(
            tooltip: 'Open new tab in right pane',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add),
            onPressed: () => _onPaneSourceSelected(
              isPrimary: false,
              activeTab: bibleTab,
              forceNewTab: true,
            ),
          ),
        ],
      ),
    );

    final secondaryPane = Column(
      children: [
        PaneHeader(
          tab: activeSecondary,
          isPrimary: false,
          showClose: true,
          displayFontSize: _parallelPaneFontSize(typography, false),
          isSearchActive: _secondaryMiniSearchActive,
          onOpenPicker: () {
            if (activeSecondary.type == ReaderContentType.bible) {
              _openSplitRightBibleQuickNav(
                sourceLeftTab: bibleTab,
                rightBibleTab: activeSecondary,
              );
              return;
            }
            _changeSplitRightSermon(activeSecondary);
          },
          onPrev: () {
            if (activeSecondary.type == ReaderContentType.bible) {
              _openAdjacentSplitRightBiblePassage(
                sourceLeftTab: bibleTab,
                rightBibleTab: activeSecondary,
                direction: -1,
              );
              return;
            }
            _openAdjacentSplitRightSermon(
              rightSermonTab: activeSecondary,
              direction: -1,
            );
          },
          onNext: () {
            if (activeSecondary.type == ReaderContentType.bible) {
              _openAdjacentSplitRightBiblePassage(
                sourceLeftTab: bibleTab,
                rightBibleTab: activeSecondary,
                direction: 1,
              );
              return;
            }
            _openAdjacentSplitRightSermon(
              rightSermonTab: activeSecondary,
              direction: 1,
            );
          },
          onDecreaseFont: () =>
              _adjustParallelPaneFontSize(isPrimary: false, delta: -1),
          onIncreaseFont: () =>
              _adjustParallelPaneFontSize(isPrimary: false, delta: 1),
          onToggleSearch: () {
            setState(() {
              _secondaryMiniSearchActive = !_secondaryMiniSearchActive;
            });
          },
          onClose: () => ref.read(readerProvider.notifier).closeSecondaryPane(),
          onSourceSelected: (value) => _onPaneSourceSelected(
            isPrimary: false,
            activeTab: bibleTab,
            selectedSource: value,
          ),
          onDisableSplitView: () {
            _clearParallelMode();
            ref.read(readerProvider.notifier).closeSecondaryPane();
          },
          onMenuSelected: (val) => _handleMenuAction(val, activeSecondary),
        ),
        rightPaneTabs,
        Expanded(
          child: ReadingPane(
            child: secondaryContent,
            isSearchActive: _secondaryMiniSearchActive,
            searchController: _secondaryMiniSearchController,
            searchFocusNode: _secondaryMiniSearchFocusNode,
            matchCounterText: activeSecondary.type == ReaderContentType.bible
                ? (_secondaryTotalMatches > 0
                      ? '${_secondaryCurrentMatchIndex + 1}/$_secondaryTotalMatches'
                      : '0/0')
                : '0/0',
            onSearchChanged: (value) {
              if (activeSecondary.type == ReaderContentType.bible) {
                _computeSecondaryBibleMatches(value);
              }
            },
            onPrevMatch: activeSecondary.type == ReaderContentType.bible
                ? () => _navigateSecondaryBibleMatch(-1)
                : null,
            onNextMatch: activeSecondary.type == ReaderContentType.bible
                ? () => _navigateSecondaryBibleMatch(1)
                : null,
            onCloseSearch: () {
              setState(() {
                _secondaryMiniSearchActive = false;
                _secondaryMiniSearchController.clear();
                _secondaryMatchVerseIndices = [];
                _secondaryTotalMatches = 0;
                _secondaryCurrentMatchIndex = 0;
              });
            },
          ),
        ),
        PaneGotoBar(
          tab: activeSecondary,
          onGoto: (value) => _jumpToPara(
            value,
            activeSecondary,
            _parallelSecondaryScrollController,
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= _parallelWideBreakpoint;
        final ratio = readerState.splitViewRatio.clamp(
          _bmSplitMin,
          _bmSplitMax,
        );
        if (isWide) {
          final leftWidth = constraints.maxWidth * ratio;
          final rightWidth =
              constraints.maxWidth - leftWidth - _bmSplitterWidth;
          return Row(
            children: [
              SizedBox(width: leftWidth, child: primaryPane),
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (details) {
                  if (constraints.maxWidth <= 0) return;
                  final currentRatio = ref.read(readerProvider).splitViewRatio;
                  final next =
                      (currentRatio + details.delta.dx / constraints.maxWidth)
                          .clamp(_bmSplitMin, _bmSplitMax)
                          .toDouble();
                  ref
                      .read(readerProvider.notifier)
                      .setSplitViewRatio(next, persist: false);
                },
                onHorizontalDragEnd: (_) {
                  ref
                      .read(readerProvider.notifier)
                      .setSplitViewRatio(
                        ref.read(readerProvider).splitViewRatio,
                        persist: true,
                      );
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: Container(
                    width: _bmSplitterWidth,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              SizedBox(width: rightWidth, child: secondaryPane),
            ],
          );
        }

        final topFlex = (ratio * 100).round().clamp(35, 75);
        final bottomFlex = 100 - topFlex;
        return Column(
          children: [
            Expanded(flex: topFlex, child: primaryPane),
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onVerticalDragUpdate: (details) {
                final height = constraints.maxHeight;
                if (height <= 0) return;
                final next = (ratio + details.delta.dy / height)
                    .clamp(_bmSplitMin, _bmSplitMax)
                    .toDouble();
                ref
                    .read(readerProvider.notifier)
                    .setSplitViewRatio(next, persist: false);
              },
              onVerticalDragEnd: (_) {
                ref
                    .read(readerProvider.notifier)
                    .setSplitViewRatio(
                      ref.read(readerProvider).splitViewRatio,
                      persist: true,
                    );
              },
              onDoubleTap: () {
                ref
                    .read(readerProvider.notifier)
                    .setSplitViewRatio(_bmSplitDefault);
              },
              child: Container(
                height: _bmSplitterWidth,
                color: Theme.of(context).colorScheme.outlineVariant,
                child: Center(
                  child: Container(
                    width: 48,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(flex: bottomFlex, child: secondaryPane),
          ],
        );
      },
    );
  }

  void _handleNavResult(Map<String, dynamic>? result) {
    if (result == null) return;
    final verse = result['verse'] as int?;
    final lang = result['lang'] as String?;
    final newTab = ReaderTab(
      type: ReaderContentType.bible,
      title: "${result['book']} ${result['chapter']}",
      book: result['book'] as String,
      chapter: result['chapter'] as int,
      verse: verse,
      bibleLang: lang,
    );
    if (result['newTab'] == true) {
      ref.read(readerProvider.notifier).openTab(newTab);
    } else {
      final idx = ref.read(readerProvider).activeTabIndex;
      if (idx >= 0) {
        ref.read(readerProvider.notifier).replaceCurrentTab(newTab);
      } else {
        ref.read(readerProvider.notifier).openTab(newTab);
      }
    }
    // Clear selection and search when navigating to a new chapter.
    setState(() {
      _selectedVerseNumbers.clear();
      _activeSelectionText = null;
      _lastVerseTapped = null;
    });
    _resetGlobalSearchState();
  }

  // ── In-page search helpers ─────────────────────────────────────────────────

  void _computeMatches(String query, {bool scrollToMatch = true}) {
    if (query.isEmpty || _currentVerses.isEmpty) {
      setState(() {
        _matchVerseIndices = [];
        _totalMatches = 0;
        _currentMatchIndex = 0;
      });
      return;
    }

    final pattern = RegExp(RegExp.escape(query), caseSensitive: false);
    final indices = <int>[];

    for (var i = 0; i < _currentVerses.length; i++) {
      final count = pattern.allMatches(_currentVerses[i].text).length;
      for (var j = 0; j < count; j++) {
        indices.add(i);
      }
    }

    setState(() {
      _matchVerseIndices = indices;
      _totalMatches = indices.length;
      _currentMatchIndex = 0;
    });

    if (indices.isNotEmpty && scrollToMatch) {
      _scrollToCurrentMatch();
    }
  }

  void _clearMatches() {
    _matchVerseIndices = [];
    _totalMatches = 0;
    _currentMatchIndex = 0;
  }

  void _resetSearchFilters() {
    _bookRangeStartIndex = null;
    _bookRangeEndIndex = null;
    _chapterRangeStart = null;
    _chapterRangeEnd = null;
  }

  void _resetGlobalSearchState({bool clearQuery = true}) {
    if (!mounted) return;
    setState(() {
      _isSearching = false;
      _showSearchOptions = true;
      if (clearQuery) {
        _searchController.clear();
      }
      _clearMatches();
      _searchScope = BibleSearchScope.chapter;
      _resetSearchFilters();
      _globalBibleResults = [];
      _globalSearchLoading = false;
      _globalSearchLoadingMore = false;
      _globalSearchTotalCount = 0;
      _lastSearchActivatedTabId = null;
    });
  }

  BibleSearchMode? _modeFromName(String? name) {
    if (name == null || name.isEmpty) return null;
    for (final mode in BibleSearchMode.values) {
      if (mode.name == name) return mode;
    }
    return null;
  }

  Future<void> _loadSearchPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = _modeFromName(prefs.getString(_searchModePrefKey));
    if (!mounted || savedMode == null) return;
    setState(() => _searchMode = savedMode);
  }

  Future<void> _persistSearchMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_searchModePrefKey, _searchMode.name);
  }

  bool get _hasBookRangeSelection {
    return _bookRangeStartIndex != null || _bookRangeEndIndex != null;
  }

  List<Map<String, dynamic>> _resolveBookRangeBooks(
    List<Map<String, dynamic>> books, {
    bool includeAllWhenUnset = false,
  }) {
    if (books.isEmpty) return [];
    final startIndex = _bookRangeStartIndex;
    final endIndex = _bookRangeEndIndex;
    if (startIndex == null && endIndex == null) {
      return includeAllWhenUnset ? books : [];
    }

    final resolvedStart = startIndex ?? endIndex;
    final resolvedEnd = endIndex ?? startIndex;
    if (resolvedStart == null || resolvedEnd == null) {
      return includeAllWhenUnset ? books : [];
    }

    final fromIndex = resolvedStart <= resolvedEnd
        ? resolvedStart
        : resolvedEnd;
    final toIndex = resolvedStart <= resolvedEnd ? resolvedEnd : resolvedStart;

    return books.where((book) {
      final index = book['book_index'] as int? ?? -1;
      return index >= fromIndex && index <= toIndex;
    }).toList();
  }

  List<String>? _buildBookFilters(
    List<Map<String, dynamic>> books,
    ReaderTab? activeTab,
  ) {
    if (_hasBookRangeSelection) {
      final selectedBooks = _resolveBookRangeBooks(books);
      if (selectedBooks.isEmpty) return null;
      return selectedBooks.map((book) => book['book'] as String).toList();
    }

    if (_searchScope == BibleSearchScope.book && activeTab?.book != null) {
      return <String>[activeTab!.book!];
    }

    return null;
  }

  int _bookRangeChapterMax(List<Map<String, dynamic>> books) {
    final selectedBooks = _resolveBookRangeBooks(
      books,
      includeAllWhenUnset: true,
    );
    if (selectedBooks.isEmpty) return 1;

    var maxChapters = 1;
    for (final book in selectedBooks) {
      final chapters = book['chapters'] as int? ?? 1;
      if (chapters > maxChapters) {
        maxChapters = chapters;
      }
    }
    return maxChapters;
  }

  void _sanitizeChapterSelections(int maxChapter) {
    final start = _chapterRangeStart;
    final end = _chapterRangeEnd;
    if ((start == null || start <= maxChapter) &&
        (end == null || end <= maxChapter)) {
      return;
    }

    setState(() {
      if (_chapterRangeStart != null && _chapterRangeStart! > maxChapter) {
        _chapterRangeStart = null;
      }
      if (_chapterRangeEnd != null && _chapterRangeEnd! > maxChapter) {
        _chapterRangeEnd = null;
      }
    });
  }

  int? _chapterRangeStartEffective() {
    final start = _chapterRangeStart;
    final end = _chapterRangeEnd;
    if (start == null && end == null) return null;
    if (start != null && end == null) return start;
    if (start == null && end != null) return end;
    return start! <= end! ? start : end;
  }

  int? _chapterRangeEndEffective() {
    final start = _chapterRangeStart;
    final end = _chapterRangeEnd;
    if (start == null && end == null) return null;
    if (start != null && end == null) return start;
    if (start == null && end != null) return end;
    return start! >= end! ? start : end;
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
    if (_matchVerseIndices.isEmpty || _currentVerses.isEmpty) return;
    final verseIndex = _matchVerseIndices[_currentMatchIndex];
    if (verseIndex < 0 || verseIndex >= _currentVerses.length) return;

    void doScroll() {
      if (!mounted || !_scrollController.hasClients || _currentVerses.isEmpty) {
        return;
      }
      final clamped = verseIndex.clamp(0, _currentVerses.length - 1);
      final frac = (clamped / _currentVerses.length).clamp(0.0, 1.0);
      final target = frac * _scrollController.position.maxScrollExtent;
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }

    if (_scrollController.hasClients) {
      doScroll();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => doScroll());
    }
  }

  void _scrollToVerseIndex(int verseIndex) {
    if (_currentVerses.isEmpty) return;
    void doScroll() {
      if (!mounted || !_scrollController.hasClients || _currentVerses.isEmpty) {
        return;
      }
      final clamped = verseIndex.clamp(0, _currentVerses.length - 1);
      final frac = (clamped / _currentVerses.length).clamp(0.0, 1.0);
      final target = frac * _scrollController.position.maxScrollExtent;
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }

    if (_scrollController.hasClients) {
      doScroll();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => doScroll());
    }
  }

  void _applyInitialSearchFocus(ReaderTab tab) {
    if (_initialSearchScrollTabId == tab.id) return;
    final query = tab.initialSearchQuery;
    if (query == null || query.isEmpty || _currentVerses.isEmpty) return;

    _computeMatches(query, scrollToMatch: false);

    int? focusIndex;
    if (tab.verse != null) {
      focusIndex = _currentVerses.indexWhere((v) => v.verse == tab.verse);
      if (focusIndex < 0) focusIndex = null;
    }

    if (focusIndex != null) {
      final matchIndex = _matchVerseIndices.indexWhere(
        (idx) => idx == focusIndex,
      );
      if (matchIndex != -1) {
        setState(() => _currentMatchIndex = matchIndex);
        _initialSearchScrollTabId = tab.id;
        _scrollToCurrentMatch();
        return;
      }
      _initialSearchScrollTabId = tab.id;
      _scrollToVerseIndex(focusIndex);
      return;
    }

    if (_matchVerseIndices.isNotEmpty) {
      _initialSearchScrollTabId = tab.id;
      _scrollToCurrentMatch();
    }
  }

  Future<void> _triggerScopeSearch(
    ReaderTab? activeTab, {
    bool append = false,
  }) async {
    if (!_isSearching || _searchScope == BibleSearchScope.chapter) {
      return;
    }

    final requestId = ++_globalSearchRequestId;
    final query = _searchController.text.trim();
    if (query.length < 2) {
      if (!mounted) return;
      setState(() {
        _globalSearchLoading = false;
        _globalSearchLoadingMore = false;
        _globalBibleResults = [];
        _globalSearchTotalCount = 0;
      });
      return;
    }

    if (append && _globalBibleResults.length >= _globalSearchTotalCount) {
      return;
    }

    setState(() {
      if (append) {
        _globalSearchLoadingMore = true;
      } else {
        _globalSearchLoading = true;
      }
    });

    try {
      final lang =
          (activeTab?.bibleLang ?? ref.read(selectedBibleLangProvider)) ?? 'en';
      final books = await ref
          .read(bibleBookListByLangProvider(lang).future)
          .timeout(const Duration(seconds: 8));
      final bookFilters = _buildBookFilters(books, activeTab);
      final chapterFrom = _chapterRangeStartEffective();
      final chapterTo = _chapterRangeEndEffective();
      final fetchLimit = _globalBiblePageSize;
      final fetchOffset = append ? _globalBibleResults.length : 0;
      final repo = await ref.read(bibleRepositoryByLangProvider(lang).future);
      final both = await Future.wait<dynamic>([
        repo.searchVerses(
          query: query,
          limit: fetchLimit,
          offset: fetchOffset,
          bookFilters: bookFilters,
          chapterFrom: chapterFrom,
          chapterTo: chapterTo,
          sortOrder: 'bookOrder',
          exactMatch: _searchMode == BibleSearchMode.exactPhrase,
          anyWord: _searchMode == BibleSearchMode.anyWord,
          accurateMatch: _searchMode == BibleSearchMode.accurate,
        ),
        repo.countSearchResults(
          query,
          bookFilters: bookFilters,
          chapterFrom: chapterFrom,
          chapterTo: chapterTo,
          exactMatch: _searchMode == BibleSearchMode.exactPhrase,
          anyWord: _searchMode == BibleSearchMode.anyWord,
          accurateMatch: _searchMode == BibleSearchMode.accurate,
        ),
      ]).timeout(const Duration(seconds: 12));
      final results = both[0] as List<BibleSearchResult>;
      final totalCount = both[1] as int;

      if (!mounted) return;
      if (requestId != _globalSearchRequestId) return;

      final queryStillSame = _searchController.text.trim() == query;
      final scopeStillGlobal = _searchScope != BibleSearchScope.chapter;
      if (!queryStillSame || !_isSearching || !scopeStillGlobal) return;

      setState(() {
        _globalBibleResults = append
            ? <BibleSearchResult>[..._globalBibleResults, ...results]
            : results;
        _globalSearchTotalCount = totalCount;
        _globalSearchLoading = false;
        _globalSearchLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      if (requestId != _globalSearchRequestId) return;
      setState(() {
        _globalSearchLoading = false;
        _globalSearchLoadingMore = false;
      });
    }
  }

  void _scheduleScopeSearch(ReaderTab? activeTab, {bool immediate = false}) {
    if (_searchScope == BibleSearchScope.chapter) return;
    _globalSearchDebounce?.cancel();
    if (immediate) {
      _triggerScopeSearch(activeTab);
      return;
    }
    _globalSearchDebounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      _triggerScopeSearch(activeTab);
    });
  }

  void _loadMoreScopeResults(ReaderTab? activeTab) {
    _globalSearchDebounce?.cancel();
    _triggerScopeSearch(activeTab, append: true);
  }

  // ── Verse selection helpers ───────────────────────────────────────────────

  void _toggleVerseSelection(int verseNumber) {
    setState(() {
      final hasShift = HardwareKeyboard.instance.isShiftPressed;
      if (hasShift && _lastVerseTapped != null) {
        final start = _lastVerseTapped!;
        final from = start < verseNumber ? start : verseNumber;
        final to = start < verseNumber ? verseNumber : start;
        for (final verse in _currentVerses) {
          if (verse.verse >= from && verse.verse <= to) {
            _selectedVerseNumbers.add(verse.verse);
          }
        }
      } else {
        if (_selectedVerseNumbers.contains(verseNumber)) {
          _selectedVerseNumbers.remove(verseNumber);
        } else {
          _selectedVerseNumbers.add(verseNumber);
        }
      }
      _activeSelectionText = null;
      _lastVerseTapped = _selectedVerseNumbers.isEmpty ? null : verseNumber;
    });
  }

  bool get _hasAnySelection {
    final textSelected = _activeSelectionText?.trim().isNotEmpty ?? false;
    return textSelected || _selectedVerseNumbers.isNotEmpty;
  }

  void _shareSelectedVerses() {
    if (_selectedVerseNumbers.isEmpty || _currentVerses.isEmpty) return;
    final activeTab = ref.read(readerProvider).activeTab;
    final text = _buildSelectedVersesPayload(activeTab);
    if (text.isEmpty) return;
    // Note: Assuming SharePlus or similar is available.
    // For now using simple debug print as fallback if not.
    debugPrint('Sharing: $text');
    setState(() {
      _selectedVerseNumbers.clear();
      _activeSelectionText = null;
      _lastVerseTapped = null;
    });
  }

  void _copySelectedVerses() {
    if (_selectedVerseNumbers.isEmpty || _currentVerses.isEmpty) return;
    final activeTab = ref.read(readerProvider).activeTab;
    final text = _buildSelectedVersesPayload(activeTab);
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
    setState(() {
      _selectedVerseNumbers.clear();
      _activeSelectionText = null;
      _lastVerseTapped = null;
    });
  }

  /// Builds the text payload for share / copy, including a header like
  /// `Genesis 1:1-3` when one or more verses are selected.
  String _buildSelectedVersesPayload(ReaderTab? activeTab) {
    if (_selectedVerseNumbers.isEmpty || _currentVerses.isEmpty) {
      return '';
    }

    final sorted = _selectedVerseNumbers.toList()..sort();
    final firstVerseNumber = sorted.first;
    final lastVerseNumber = sorted.last;

    final firstVerse = _currentVerses.firstWhere(
      (v) => v.verse == firstVerseNumber,
      orElse: () => _currentVerses.first,
    );
    final lastVerse = _currentVerses.firstWhere(
      (v) => v.verse == lastVerseNumber,
      orElse: () => firstVerse,
    );

    final book = (activeTab?.book ?? firstVerse.book).trim();
    final chapter = firstVerse.chapter;
    final sameChapter = firstVerse.chapter == lastVerse.chapter;

    final header = sameChapter
        ? '$book $chapter:${firstVerse.verse == lastVerse.verse ? firstVerse.verse : '${firstVerse.verse}-${lastVerse.verse}'}'
        : '$book ${firstVerse.chapter}:${firstVerse.verse}-${lastVerse.chapter}:${lastVerse.verse}';

    final bodyLines = sorted.map((vNum) {
      final verse = _currentVerses.firstWhere(
        (v) => v.verse == vNum,
        orElse: () => _currentVerses.first,
      );
      return '${book.isEmpty ? verse.book : book} ${verse.chapter}:${verse.verse}  ${verse.text}';
    });

    return '$header\n\n${bodyLines.join('\n\n')}';
  }

  // ── Close other tabs ─────────────────────────────────────────────────────

  void _closeOtherTabs() {
    final state = ref.read(readerProvider);
    // Close from highest index downward so indices stay stable.
    for (var i = state.tabs.length - 1; i >= 1; i--) {
      ref.read(readerProvider.notifier).closeTab(i);
    }
  }

  // ── PDF generation (Bible) ────────────────────────────────────────────────

  Map<String, dynamic> _buildBiblePdfPayload() {
    final activeTab = ref.read(readerProvider).activeTab;
    final lang =
        activeTab?.bibleLang ?? ref.read(selectedBibleLangProvider) ?? 'en';
    final typography = ref.read(typographyProvider(lang));
    final verses = _currentVerses
        .map((v) => <String, dynamic>{'verse': v.verse, 'text': v.text})
        .toList(growable: false);

    return <String, dynamic>{
      'type': 'bible',
      'lang': lang == 'ta' ? 'ta' : 'en',
      'title': activeTab?.title ?? 'Bible',
      'meta': <String, dynamic>{
        'book': activeTab?.book,
        'chapter': activeTab?.chapter,
      },
      'settings': <String, dynamic>{
        'fontSize': typography.fontSize,
        'lineHeight': typography.lineHeight,
        'titleFontSize': typography.titleFontSize,
        'fontFamily': typography.resolvedFontFamily ?? '',
      },
      'content': <String, dynamic>{'verses': verses},
    };
  }

  Future<Uint8List> _fetchBiblePdfBytes() async {
    final payload = _buildBiblePdfPayload();
    final bytes = await _pdfExportService.export(payload);
    return bytes;
  }

  String _sanitizePdfName(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[<>:"/\\\\|?*]'), '-').trim();
    return cleaned.isEmpty ? 'Document' : cleaned;
  }

  Future<void> _withPdfProgress(Future<void> Function() task) async {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      await task();
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  Future<void> _printBiblePdf() async {
    await _withPdfProgress(() async {
      try {
        final bytes = await _fetchBiblePdfBytes();
        final rawTitle = ref.read(readerProvider).activeTab?.title ?? 'Bible';
        final safeTitle = _sanitizePdfName(rawTitle);
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: safeTitle);
      } on PdfExportException catch (e) {
        if (!mounted) return;
        final message = e.isNetworkIssue
            ? 'PDF export requires internet connection.'
            : e.message;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    });
  }

  Future<void> _downloadBiblePdf() async {
    await _withPdfProgress(() async {
      final rawTitle = ref.read(readerProvider).activeTab?.title ?? 'Bible';
      final safeTitle = _sanitizePdfName(rawTitle);
      final filename = '$safeTitle.pdf';
      late final Uint8List bytes;
      try {
        bytes = await _fetchBiblePdfBytes();
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

      // Desktop: use native Save dialog and explorer reveal.
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

      // Mobile: save into app documents directory and allow opening the file.
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

  // ── Highlighted text spans ────────────────────────────────────────────────

  List<TextSpan> _buildHighlightedSpans(
    String text,
    TextStyle baseStyle,
    TextStyle highlightStyle,
    TextStyle currentMatchStyle, {
    int? currentOccurrenceIndex,
  }) {
    if (!_isSearching || _searchController.text.isEmpty) {
      return [TextSpan(text: text, style: baseStyle)];
    }

    final query = RegExp.escape(_searchController.text);
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
          style: isCurrent ? currentMatchStyle : highlightStyle,
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

  List<TextSpan> _buildHighlightedSpansForQuery(
    String text,
    TextStyle baseStyle,
    TextStyle highlightStyle,
    TextStyle currentMatchStyle,
    String query, {
    int? currentOccurrenceIndex,
  }) {
    if (query.trim().isEmpty) {
      return [TextSpan(text: text, style: baseStyle)];
    }

    final escaped = RegExp.escape(query);
    final matches = RegExp(
      escaped,
      caseSensitive: false,
    ).allMatches(text).toList();
    if (matches.isEmpty) {
      return [TextSpan(text: text, style: baseStyle)];
    }

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
          style: isCurrent ? currentMatchStyle : highlightStyle,
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

  void _computeSecondaryBibleMatches(
    String query, {
    bool scrollToMatch = true,
  }) {
    final trimmed = query.trim();
    if (trimmed.isEmpty || _secondaryVerses.isEmpty) {
      setState(() {
        _secondaryMatchVerseIndices = [];
        _secondaryTotalMatches = 0;
        _secondaryCurrentMatchIndex = 0;
      });
      return;
    }

    final escaped = RegExp.escape(trimmed);
    final pattern = RegExp(escaped, caseSensitive: false);
    final indices = <int>[];
    for (var i = 0; i < _secondaryVerses.length; i++) {
      final count = pattern.allMatches(_secondaryVerses[i].text).length;
      if (count > 0) {
        indices.addAll(List<int>.filled(count, i));
      }
    }

    setState(() {
      _secondaryMatchVerseIndices = indices;
      _secondaryTotalMatches = indices.length;
      _secondaryCurrentMatchIndex = 0;
    });

    if (scrollToMatch && indices.isNotEmpty) {
      _scrollToSecondaryMatch();
    }
  }

  void _navigateSecondaryBibleMatch(int direction) {
    if (_secondaryMatchVerseIndices.isEmpty || _secondaryVerses.isEmpty) return;

    setState(() {
      _secondaryCurrentMatchIndex =
          (_secondaryCurrentMatchIndex + direction) %
          _secondaryMatchVerseIndices.length;
      if (_secondaryCurrentMatchIndex < 0) {
        _secondaryCurrentMatchIndex = _secondaryMatchVerseIndices.length - 1;
      }
    });

    _scrollToSecondaryMatch();
  }

  void _scrollToSecondaryMatch() {
    if (_secondaryMatchVerseIndices.isEmpty || _secondaryVerses.isEmpty) return;
    final verseIndex = _secondaryMatchVerseIndices[_secondaryCurrentMatchIndex];
    if (verseIndex < 0 || verseIndex >= _secondaryVerses.length) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_parallelSecondaryScrollController.hasClients ||
          _secondaryVerses.isEmpty) {
        return;
      }
      final clamped = verseIndex.clamp(0, _secondaryVerses.length - 1);
      final frac = (clamped / _secondaryVerses.length).clamp(0.0, 1.0);
      final target =
          frac * _parallelSecondaryScrollController.position.maxScrollExtent;
      _parallelSecondaryScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Widget _buildMatchMarkers(
    int itemCount,
    List<int> matchIndices,
    int? currentItemIndex,
  ) {
    if (!_isSearching || matchIndices.isEmpty || itemCount <= 1) {
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

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final readerState = ref.watch(readerProvider);
    final activeTab = readerState.activeTab;
    final bibleReadLang =
        activeTab?.bibleLang ?? ref.watch(selectedBibleLangProvider) ?? 'en';
    final typographyState = ref.watch(typographyProvider(bibleReadLang));

    final isFullscreen = typographyState.isFullscreen;

    // Clear search state only when the active tab changes and the new tab
    // doesn't request auto-search.
    final activeTabId = activeTab?.id;
    final tabChanged = activeTabId != _lastActiveTabId;
    if (tabChanged) {
      if (_parallelSourceTabId != null && activeTabId != _parallelSourceTabId) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _clearParallelMode();
        });
      }
      _lastActiveTabId = activeTabId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isSearching && activeTab?.initialSearchQuery == null) {
          _resetGlobalSearchState();
        }
      });
    }

    final isParallelMode = _isParallelActiveFor(activeTab);
    final englishParallelTab = _parallelEnglishTab;
    final bmState = ref.watch(readerProvider);
    final isSplitViewOpen =
        bmState.splitViewEnabled && bmState.secondaryTabs.isNotEmpty;
    final hasUnifiedSplit =
        bmState.secondaryTabs.isNotEmpty &&
        bmState.splitViewEnabled &&
        activeTab?.type == ReaderContentType.bible;

    if (!isParallelMode &&
        (_parallelSourceTabId != null || _parallelEnglishTab != null)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _clearParallelMode();
      });
    }

    return Shortcuts(
      shortcuts: {
        // Only when in-page search mode with matches — otherwise Enter is used
        // elsewhere (e.g. Goto verse bar) when that UI is reachable.
        if (_isSearching && _totalMatches > 0)
          LogicalKeySet(LogicalKeyboardKey.enter): const _NextMatchIntent(),
        if (_isSearching && _totalMatches > 0)
          LogicalKeySet(
            LogicalKeyboardKey.shift,
            LogicalKeyboardKey.enter,
          ): const _PrevMatchIntent(),
      },
      child: Actions(
        actions: {
          _NextMatchIntent: CallbackAction<_NextMatchIntent>(
            onInvoke: (intent) {
              if (_isSearching && _totalMatches > 0) {
                _navigateToMatch(1);
              }
              return null;
            },
          ),
          _PrevMatchIntent: CallbackAction<_PrevMatchIntent>(
            onInvoke: (intent) {
              if (_isSearching && _totalMatches > 0) {
                _navigateToMatch(-1);
              }
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: isFullscreen
                ? null
                : ((!hasUnifiedSplit && _isSearching)
                      ? _buildSearchAppBar(context, activeTab)
                      : _buildDefaultAppBar(
                          context,
                          activeTab,
                          isInSplitView: hasUnifiedSplit,
                        )),
            body: activeTab == null
                ? const Center(child: Text('No open tabs. Please open a book.'))
                : isFullscreen
                ? Stack(
                    children: [
                      Column(
                        children: [
                          Expanded(
                            child: hasUnifiedSplit
                                ? _buildReaderSplitContentV2(
                                    bibleTab: activeTab,
                                    readerState: bmState,
                                    typography: typographyState,
                                  )
                                : (isParallelMode && englishParallelTab != null
                                      ? _buildParallelContent(
                                          primaryTab: activeTab,
                                          secondaryTab: englishParallelTab,
                                          typography: typographyState,
                                        )
                                      : _buildTabContent(
                                          activeTab,
                                          typographyState,
                                        )),
                          ),
                          SelectionActionBar(
                            isVisible:
                                (_activeSelectionText?.trim().isNotEmpty ??
                                false),
                            selectedText: _activeSelectionText,
                            onCopy: () => _copySelectedVerses(),
                            onShare: () => _shareSelectedVerses(),
                            onDismiss: () {
                              setState(() => _activeSelectionText = null);
                            },
                          ),
                        ],
                      ),
                      // Fullscreen exit overlay — always visible in top-right corner.
                      Positioned(
                        top: 12,
                        right: 12,
                        child: SafeArea(
                          child: Material(
                            color: Colors.black45,
                            borderRadius: BorderRadius.circular(20),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () => ref
                                  .read(typographyGlobalProvider.notifier)
                                  .toggleFullscreen(),
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
                  )
                : Column(
                    children: [
                      if (_isSearching)
                        AnimatedSize(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeInOutCubic,
                          alignment: Alignment.topCenter,
                          child: ClipRect(
                            child: _showSearchOptions
                                ? Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildSearchChipsRow(activeTab),
                                      if (_searchScope !=
                                          BibleSearchScope.chapter)
                                        _buildCompactRangeFiltersRow(activeTab),
                                    ],
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ),
                      if (_isSearching)
                        Padding(
                          padding: const EdgeInsets.only(right: 8, bottom: 2),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: _buildSearchOptionsToggleButton(),
                          ),
                        ),
                      Expanded(
                        child:
                            _isSearching &&
                                _searchScope != BibleSearchScope.chapter
                            ? _buildScopeSearchResults(activeTab)
                            : Column(
                                children: [
                                  if (!isFullscreen &&
                                      !hasUnifiedSplit &&
                                      !isParallelMode &&
                                      readerState.tabs.isNotEmpty &&
                                      !_isSearching)
                                    BottomTabRail(
                                      tabs: readerState.tabs,
                                      activeIndex: readerState.activeTabIndex,
                                      onTapTab: (index) => _onMainTabTap(
                                        index,
                                        readerState.tabs,
                                      ),
                                      onCloseTab: (index) => ref
                                          .read(readerProvider.notifier)
                                          .closeTab(index),
                                      onOpenNew: _openQuickNav,
                                    ),
                                  Expanded(
                                    child: (hasUnifiedSplit
                                        ? _buildReaderSplitContentV2(
                                            bibleTab: activeTab,
                                            readerState: bmState,
                                            typography: typographyState,
                                          )
                                        : (isParallelMode &&
                                                  englishParallelTab != null
                                              ? _buildParallelContent(
                                                  primaryTab: activeTab,
                                                  secondaryTab:
                                                      englishParallelTab,
                                                  typography: typographyState,
                                                )
                                              : _buildTabContent(
                                                  activeTab,
                                                  typographyState,
                                                ))),
                                  ),
                                ],
                              ),
                      ),
                      SelectionActionBar(
                        isVisible:
                            (_activeSelectionText?.trim().isNotEmpty ?? false),
                        selectedText: _activeSelectionText,
                        onCopy: () => _copySelectedVerses(),
                        onShare: () => _shareSelectedVerses(),
                        onDismiss: () {
                          setState(() => _activeSelectionText = null);
                        },
                      ),
                    ],
                  ),
            // FAB opens Quick Navigation sheet.
            floatingActionButton:
                (activeTab == null ||
                    isFullscreen ||
                    _isSearching ||
                    _hasAnySelection ||
                    isSplitViewOpen)
                ? null
                : FloatingActionButton(
                    onPressed: _openQuickNav,
                    child: const Icon(Icons.menu_book_rounded),
                  ),
            floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
            bottomNavigationBar: null,
          ),
        ),
      ),
    );
  }

  // ── App bars ──────────────────────────────────────────────────────────────

  AppBar _buildSearchAppBar(BuildContext context, ReaderTab? activeTab) {
    final isChapterScope = _searchScope == BibleSearchScope.chapter;
    final counterText = _totalMatches > 0
        ? '${_currentMatchIndex + 1}/$_totalMatches'
        : '0/0';
    final loadedCount = _globalBibleResults.length;
    final totalCount = _globalSearchTotalCount;
    final resultCountText = totalCount > 0
        ? '$loadedCount/$totalCount'
        : '$loadedCount';

    final hintText = switch (_searchScope) {
      BibleSearchScope.chapter => 'Search in chapter...',
      BibleSearchScope.book => 'Search in current book...',
      BibleSearchScope.all => 'Search in all books...',
    };

    return AppBar(
      centerTitle: false,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () {
          // Exit search mode
          _resetGlobalSearchState();
        },
      ),
      title: TextField(
        focusNode: _searchFieldFocusNode,
        controller: _searchController,
        autofocus: true,
        decoration: InputDecoration(
          hintText: hintText,
          border: InputBorder.none,
          filled: false,
          fillColor: Colors.transparent,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
        ),
        onSubmitted: (_) async {
          if (isChapterScope) {
            if (_totalMatches > 0) _navigateToMatch(1);
            return;
          }
          _scheduleScopeSearch(activeTab, immediate: true);
        },
        onChanged: (val) {
          if (isChapterScope) {
            _computeMatches(val);
          } else {
            _scheduleScopeSearch(activeTab);
          }
        },
      ),
      actions: [
        if (_searchController.text.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              _searchController.clear();
              if (isChapterScope) {
                _computeMatches('');
              } else {
                setState(() {
                  _globalBibleResults = [];
                  _globalSearchLoading = false;
                  _globalSearchLoadingMore = false;
                  _globalSearchTotalCount = 0;
                });
              }
            },
          ),
        if (isChapterScope)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                counterText,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        if (isChapterScope)
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_up),
            onPressed: _totalMatches == 0 ? null : () => _navigateToMatch(-1),
          ),
        if (isChapterScope)
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: _totalMatches == 0 ? null : () => _navigateToMatch(1),
          ),
        if (!isChapterScope)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: _globalSearchLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      resultCountText,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
            ),
          ),
      ],
    );
  }

  Widget _buildSearchOptionsToggleButton() {
    return IconButton(
      tooltip: _showSearchOptions ? 'Hide options' : 'Show options',
      icon: Icon(_showSearchOptions ? Icons.visibility_off : Icons.visibility),
      onPressed: () {
        setState(() => _showSearchOptions = !_showSearchOptions);
      },
    );
  }

  Widget _buildSearchChipsRow(ReaderTab? activeTab) {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text('Current Chapter'),
                  selected: _searchScope == BibleSearchScope.chapter,
                  onSelected: (selected) {
                    if (!selected) return;
                    setState(() {
                      _searchScope = BibleSearchScope.chapter;
                      _globalBibleResults = [];
                      _globalSearchLoading = false;
                      _globalSearchLoadingMore = false;
                      _globalSearchTotalCount = 0;
                    });
                    _computeMatches(_searchController.text);
                  },
                ),
                ChoiceChip(
                  label: const Text('Current Book'),
                  selected: _searchScope == BibleSearchScope.book,
                  onSelected: (selected) {
                    if (!selected) return;
                    setState(() {
                      _searchScope = BibleSearchScope.book;
                      _clearMatches();
                      _globalSearchTotalCount = 0;
                    });
                    _scheduleScopeSearch(activeTab, immediate: true);
                  },
                ),
                ChoiceChip(
                  label: const Text('All Books'),
                  selected: _searchScope == BibleSearchScope.all,
                  onSelected: (selected) {
                    if (!selected) return;
                    setState(() {
                      _searchScope = BibleSearchScope.all;
                      _clearMatches();
                      _globalSearchTotalCount = 0;
                    });
                    _scheduleScopeSearch(activeTab, immediate: true);
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Smart'),
                  selected: _searchMode == BibleSearchMode.smart,
                  onSelected: (selected) {
                    if (!selected) return;
                    setState(() => _searchMode = BibleSearchMode.smart);
                    unawaited(_persistSearchMode());
                    _scheduleScopeSearch(activeTab, immediate: true);
                  },
                ),
                ChoiceChip(
                  label: const Text('Exact Phrase'),
                  selected: _searchMode == BibleSearchMode.exactPhrase,
                  onSelected: (selected) {
                    if (!selected) return;
                    setState(() => _searchMode = BibleSearchMode.exactPhrase);
                    unawaited(_persistSearchMode());
                    _scheduleScopeSearch(activeTab, immediate: true);
                  },
                ),
                ChoiceChip(
                  label: const Text('Any Word'),
                  selected: _searchMode == BibleSearchMode.anyWord,
                  onSelected: (selected) {
                    if (!selected) return;
                    setState(() => _searchMode = BibleSearchMode.anyWord);
                    unawaited(_persistSearchMode());
                    _triggerScopeSearch(activeTab);
                  },
                ),
                ChoiceChip(
                  label: const Text('Accurate'),
                  selected: _searchMode == BibleSearchMode.accurate,
                  onSelected: (selected) {
                    if (!selected) return;
                    setState(() => _searchMode = BibleSearchMode.accurate);
                    unawaited(_persistSearchMode());
                    _triggerScopeSearch(activeTab);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactRangeFiltersRow(ReaderTab? activeTab) {
    final lang =
        (activeTab?.bibleLang ?? ref.read(selectedBibleLangProvider)) ?? 'en';
    final booksAsync = ref.watch(bibleBookListByLangProvider(lang));

    return booksAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (books) {
        final sortedBooks = [...books]
          ..sort(
            (a, b) =>
                (a['book_index'] as int).compareTo(b['book_index'] as int),
          );
        final maxChapter = _bookRangeChapterMax(sortedBooks);
        final chapterStartInvalid =
            _chapterRangeStart != null && _chapterRangeStart! > maxChapter;
        final chapterEndInvalid =
            _chapterRangeEnd != null && _chapterRangeEnd! > maxChapter;
        if (chapterStartInvalid || chapterEndInvalid) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _sanitizeChapterSelections(maxChapter);
            }
          });
        }

        final chapterItems = List<DropdownMenuItem<int?>>.generate(maxChapter, (
          index,
        ) {
          final value = index + 1;
          return DropdownMenuItem<int?>(
            value: value,
            child: Text(value.toString()),
          );
        });

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (_searchScope != BibleSearchScope.book)
                    SizedBox(
                      width: 190,
                      child: DropdownButtonFormField<int?>(
                        value: _bookRangeStartIndex,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'From Book',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('All Books'),
                          ),
                          ...sortedBooks.map((book) {
                            final bookIndex = book['book_index'] as int;
                            return DropdownMenuItem<int?>(
                              value: bookIndex,
                              child: Text(book['book'] as String),
                            );
                          }),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _bookRangeStartIndex = value;
                          });
                          _sanitizeChapterSelections(
                            _bookRangeChapterMax(sortedBooks),
                          );
                          _scheduleScopeSearch(activeTab, immediate: true);
                        },
                      ),
                    ),
                  if (_searchScope != BibleSearchScope.book)
                    SizedBox(
                      width: 190,
                      child: DropdownButtonFormField<int?>(
                        value: _bookRangeEndIndex,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'To Book',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('All Books'),
                          ),
                          ...sortedBooks.map((book) {
                            final bookIndex = book['book_index'] as int;
                            return DropdownMenuItem<int?>(
                              value: bookIndex,
                              child: Text(book['book'] as String),
                            );
                          }),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _bookRangeEndIndex = value;
                          });
                          _sanitizeChapterSelections(
                            _bookRangeChapterMax(sortedBooks),
                          );
                          _scheduleScopeSearch(activeTab, immediate: true);
                        },
                      ),
                    ),
                  SizedBox(
                    width: 165,
                    child: DropdownButtonFormField<int?>(
                      value: _chapterRangeStart,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'From Chapter',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('All'),
                        ),
                        ...chapterItems,
                      ],
                      onChanged: (value) {
                        setState(() {
                          _chapterRangeStart = value;
                        });
                        _scheduleScopeSearch(activeTab, immediate: true);
                      },
                    ),
                  ),
                  SizedBox(
                    width: 165,
                    child: DropdownButtonFormField<int?>(
                      value: _chapterRangeEnd,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'To Chapter',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('All'),
                        ),
                        ...chapterItems,
                      ],
                      onChanged: (value) {
                        setState(() {
                          _chapterRangeEnd = value;
                        });
                        _scheduleScopeSearch(activeTab, immediate: true);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildScopeSearchResults(ReaderTab? activeTab) {
    if (_searchController.text.trim().length < 2) {
      return const Center(child: Text('Type at least 2 characters to search.'));
    }

    if (_globalSearchLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_globalBibleResults.isEmpty) {
      return const Center(child: Text('No verses found.'));
    }

    final lang =
        (activeTab?.bibleLang ?? ref.read(selectedBibleLangProvider)) ?? 'en';

    final hasMore = _globalBibleResults.length < _globalSearchTotalCount;
    final showFooter = hasMore || _globalSearchLoadingMore;

    return ListView.builder(
      controller: _scopeSearchScrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _globalBibleResults.length + (showFooter ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _globalBibleResults.length) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
            child: Center(
              child: _globalSearchLoadingMore
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : FilledButton.tonal(
                      onPressed: () => _loadMoreScopeResults(activeTab),
                      child: const Text('Load more'),
                    ),
            ),
          );
        }
        final r = _globalBibleResults[index];
        final title = '${r.book} ${r.chapter}:${r.verse}';
        final snippet = (r.highlighted?.trim().isNotEmpty ?? false)
            ? r.highlighted!
            : r.text;
        return Card(
          child: ListTile(
            dense: true,
            title: Text(title, style: Theme.of(context).textTheme.labelLarge),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: FtsHighlightText(rawSnippet: snippet),
            ),
            onTap: () {
              final query = _searchController.text.trim();
              final replacement = ReaderTab(
                type: ReaderContentType.bible,
                title: '${r.book} ${r.chapter}',
                book: r.book,
                chapter: r.chapter,
                verse: r.verse,
                bibleLang: lang,
                initialSearchQuery: query.isEmpty ? null : query,
              );
              final idx = ref.read(readerProvider).activeTabIndex;
              if (idx >= 0) {
                ref
                    .read(readerProvider.notifier)
                    .replaceCurrentTab(replacement);
              } else {
                ref.read(readerProvider.notifier).openTab(replacement);
              }

              _resetGlobalSearchState();
            },
          ),
        );
      },
    );
  }

  Widget _buildSplitViewPopupMenu(
    BuildContext context,
    ReaderTab? activeTab,
    BoxConstraints constraints,
    bool splitEnabled,
    ThemeData theme, {
    String? label,
  }) {
    final icon = Icon(
      Icons.splitscreen,
      size: constraints.maxWidth >= 900 ? 28 : 24,
      color: (splitEnabled || _isParallelActiveFor(activeTab))
          ? theme.colorScheme.primary
          : null,
    );

    if (label != null) {
      return PopupMenuButton<String>(
        tooltip: label,
        onSelected: (value) async {
          await _onSplitViewSourceSelected(activeTab, value);
        },
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
      onSelected: (value) async {
        await _onSplitViewSourceSelected(activeTab, value);
      },
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

  AppBar _buildDefaultAppBar(
    BuildContext context,
    ReaderTab? activeTab, {
    required bool isInSplitView,
  }) {
    final splitEnabled = ref.watch(
      readerProvider.select(
        (s) => s.splitViewEnabled && s.splitRightTabs.isNotEmpty,
      ),
    );
    final hasSelection = _selectedVerseNumbers.isNotEmpty;
    final openedFromSearch = activeTab?.openedFromSearch ?? false;
    final isBibleTab =
        activeTab?.type == ReaderContentType.bible && activeTab?.book != null;
    final activeLang =
        (activeTab?.bibleLang ?? ref.read(selectedBibleLangProvider)) ?? 'en';
    final chapterNo = activeTab?.chapter;
    final chapterLabel = chapterNo == null
        ? ''
        : (activeLang == 'ta' ? 'அதிகாரம் $chapterNo' : 'Chapter $chapterNo');
    final isTamilBibleTab = isBibleTab && activeLang == 'ta';
    final isCompactAppBar = MediaQuery.sizeOf(context).width < 700;
    final showCompactTamilOptions = isTamilBibleTab && isCompactAppBar;

    final theme = Theme.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWide = screenWidth >= 900;
    final isSermonTab =
        activeTab?.type == ReaderContentType.sermon &&
        activeTab?.sermonId != null;
    final showPcShortcuts = screenWidth >= 700 && (isBibleTab || isSermonTab);

    return AppBar(
      toolbarHeight: isWide ? 64.0 : (isSermonTab ? 88.0 : 72.0),
      titleSpacing: 0,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, size: isWide ? 28 : 24),
            onPressed: () {
              if (openedFromSearch) {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/search?tab=bible');
                }
              } else {
                context.pop();
              }
            },
          ),
        ],
      ),
      title: LayoutBuilder(
        builder: (context, constraints) {
          if (!showPcShortcuts) {
            return SizedBox(
              width: constraints.maxWidth,
              child: InkWell(
                onTap: _openQuickNav,
                child: Row(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            activeTab?.title ?? 'Reader',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontSize: constraints.maxWidth >= 700 ? 20 : 18,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (isSermonTab)
                            Consumer(
                              builder: (context, ref, _) {
                                final sermonAsync = ref.watch(
                                  sermonByIdProvider(activeTab!.sermonId!),
                                );
                                return sermonAsync.maybeWhen(
                                  data: (s) => s == null
                                      ? const SizedBox.shrink()
                                      : Text(
                                          '${s.id} - ${s.year} - ${s.totalParagraphs ?? 0}',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: theme
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                  orElse: () => const SizedBox.shrink(),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_drop_down, size: isWide ? 28 : 24),
                  ],
                ),
              ),
            );
          }

          return Row(
            mainAxisAlignment: MainAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: _openQuickNav,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          activeTab?.title ?? 'Reader',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (isSermonTab)
                          Consumer(
                            builder: (context, ref, _) {
                              final sermonAsync = ref.watch(
                                sermonByIdProvider(activeTab!.sermonId!),
                              );
                              return sermonAsync.maybeWhen(
                                data: (s) => s == null
                                    ? const SizedBox.shrink()
                                    : Text(
                                        '${s.id} - ${s.year} - ${s.totalParagraphs ?? 0}',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                orElse: () => const SizedBox.shrink(),
                              );
                            },
                          ),
                      ],
                    ),
                    Icon(Icons.arrow_drop_down, size: isWide ? 28 : 24),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              if (isSermonTab) ...[
                // Split View Controls for Sermon Reading
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
                        activeTab,
                        constraints,
                        splitEnabled,
                        theme,
                        label: 'Split View',
                      ),
                      if (isInSplitView) ...[
                        const SizedBox(width: 8),
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: theme.colorScheme.error,
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: () {
                            _clearParallelMode();
                            ref
                                .read(readerProvider.notifier)
                                .closeSecondaryPane();
                          },
                          child: const Text('Disable Split View'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (isBibleTab)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6.0,
                    vertical: 2.0,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceVariant.withAlpha(80),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => _openQuickNavForTestament(0),
                        child: Text(
                          'Old Testament',
                          style: TextStyle(
                            fontSize: constraints.maxWidth >= 900 ? 15 : 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _openQuickNavForTestament(1),
                        child: Text(
                          'New Testament',
                          style: TextStyle(
                            fontSize: constraints.maxWidth >= 900 ? 15 : 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (isTamilBibleTab) ...[
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: () => _openEnglishParallel(
                            activeTab,
                            sourceLangOverride: activeLang,
                          ),
                          child: Text(
                            'English Parallel',
                            style: TextStyle(
                              fontSize: constraints.maxWidth >= 900 ? 15 : 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => _switchToEnglishBible(
                            activeTab,
                            sourceLangOverride: activeLang,
                          ),
                          child: Text(
                            'Switch to English',
                            style: TextStyle(
                              fontSize: constraints.maxWidth >= 900 ? 15 : 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ] else if (isBibleTab && activeLang == 'en') ...[
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: () => _switchToTamilBible(activeTab),
                          child: Text(
                            'Switch to Tamil',
                            style: TextStyle(
                              fontSize: constraints.maxWidth >= 900 ? 15 : 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 8),
                      _buildSplitViewPopupMenu(
                        context,
                        activeTab,
                        constraints,
                        splitEnabled,
                        theme,
                        label: 'Split View',
                      ),
                      if (isInSplitView) ...[
                        const SizedBox(width: 8),
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: theme.colorScheme.error,
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: () {
                            _clearParallelMode();
                            ref
                                .read(readerProvider.notifier)
                                .closeSecondaryPane();
                          },
                          child: const Text('Disable Split View'),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
      actions: [
        LayoutBuilder(
          builder: (context, constraints) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasSelection) ...[
                  IconButton(
                    icon: const Icon(Icons.copy),
                    onPressed: _copySelectedVerses,
                  ),
                  IconButton(
                    icon: const Icon(Icons.share),
                    onPressed: _shareSelectedVerses,
                  ),
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() {
                      _selectedVerseNumbers.clear();
                      _activeSelectionText = null;
                      _lastVerseTapped = null;
                    }),
                  ),
                ] else ...[
                  if (showCompactTamilOptions)
                    PopupMenuButton<String>(
                      tooltip: 'English options',
                      icon: const Icon(Icons.language),
                      onSelected: (value) {
                        if (value == 'parallel') {
                          _openEnglishParallel(
                            activeTab,
                            sourceLangOverride: activeLang,
                          );
                        } else if (value == 'switch') {
                          _switchToEnglishBible(
                            activeTab,
                            sourceLangOverride: activeLang,
                          );
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem<String>(
                          value: 'parallel',
                          child: Text('English Parallel'),
                        ),
                        PopupMenuItem<String>(
                          value: 'switch',
                          child: Text('English Bible'),
                        ),
                      ],
                    ),
                
                  // Only show the split icon in actions on small screens;
                  // wide screens already show the 'Split View' text in the title row.
                  if (!showPcShortcuts)
                    _buildSplitViewPopupMenu(
                      context,
                      activeTab,
                      constraints,
                      splitEnabled,
                      theme,
                    ),
                  if (isBibleTab)
                    IconButton(
                      tooltip: 'Advanced Search',
                      icon: Icon(
                        Icons.manage_search,
                        size: constraints.maxWidth >= 900 ? 28 : 24,
                      ),
                      onPressed: () => context.go('/search?tab=bible'),
                    ),
                  IconButton(
                    icon: Icon(
                      Icons.search,
                      size: constraints.maxWidth >= 900 ? 28 : 24,
                    ),
                    onPressed: () {
                      if (isInSplitView) {
                        context.go('/search?tab=bible');
                        return;
                      }
                      _resetGlobalSearchState();
                      setState(() {
                        _isSearching = true;
                      });
                    },
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.home,
                      size: constraints.maxWidth >= 900 ? 28 : 24,
                    ),
                    onPressed: () => context.go('/'),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.settings,
                      size: constraints.maxWidth >= 900 ? 28 : 24,
                    ),
                    onPressed: () => ReaderSettingsSheet.show(context),
                  ),
                  const HelpButton(topicId: 'reader'),
                  const SectionMenuButton()
                ],
              ],
            );
          },
        ),
      ],
      bottom: (!isInSplitView && isBibleTab)
          ? PreferredSize(
              preferredSize: Size.fromHeight(
                MediaQuery.sizeOf(context).width >= 900 ? 44 : 40,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isDesktopNav = constraints.maxWidth >= 900;
                  final iconSize = isDesktopNav ? 26.0 : 22.0;
                  final labelSize = isDesktopNav ? 17.0 : 14.0;
                  final buttonHeight = isDesktopNav ? 46.0 : 38.0;
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
                      crossAxisAlignment: CrossAxisAlignment.center,
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
                          onPressed: () =>
                              _openAdjacentParallelBiblePassage(-1),
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
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Tooltip(
                                message: activeLang == 'ta'
                                    ? 'புத்தகம் மற்றும் அதிகாரத் தேர்வு'
                                    : 'Book & chapter (quick navigation)',
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () => _openQuickNav(),
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: isDesktopNav ? 10 : 6,
                                      vertical: 6,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            chapterLabel,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: labelSize,
                                              height: 1.1,
                                              fontWeight: FontWeight.w700,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          width:
                                              isDesktopNav ? 2 : 0,
                                        ),
                                        Icon(
                                          Icons.arrow_drop_down,
                                          size:
                                              iconSize * 0.92,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(width: isDesktopNav ? 22 : 14),
                              SizedBox(
                                width: isDesktopNav ? 96 : 84,
                                height: isDesktopNav ? 34 : 30,
                                child: TextField(
                                  controller: _gotoVerseController,
                                  focusNode: _gotoVerseFocusNode,
                                  keyboardType: TextInputType.number,
                                  textInputAction: TextInputAction.go,
                                  textAlign: TextAlign.center,
                                  textAlignVertical: TextAlignVertical.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        fontSize: isDesktopNav ? 13 : 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    hintText: 'Goto Verse',
                                    hintStyle: TextStyle(
                                      fontSize: isDesktopNav ? 11 : 10,
                                    ),
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 6,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  onEditingComplete: () =>
                                      _submitGotoVerseField(activeTab),
                                  onSubmitted: (_) =>
                                      _submitGotoVerseField(activeTab),
                                ),
                              ),
                            ],
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
                          onPressed: () => _openAdjacentParallelBiblePassage(1),
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

  Widget _buildTabContent(ReaderTab tab, TypographySettings typography) {
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
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 40),
              const SizedBox(height: 12),
              Text(
                'Error loading chapter',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Bible database is not installed. Import Tamil/English Bible database to continue.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
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
        );
      }

      final asyncVerses = ref.watch(chapterVersesProvider(tab));

      return asyncVerses.when(
        data: (verses) {
          // Keep render path side-effect free: no setState/post-frame callbacks.
          final chapterSig = '${tab.id}:${tab.book}:${tab.chapter}';
          final chapterChanged = _lastChapterSignature != chapterSig;
          if (chapterChanged) {
            _lastChapterSignature = chapterSig;
            _pruneVerseAnchorsForTab(tab.id);
            // Clear stale search state when chapter changes.
            _clearMatches();

            if (_isSearching && _searchController.text.isNotEmpty) {
              _pendingSearchRecalcSignature = chapterSig;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted || _pendingSearchRecalcSignature != chapterSig) {
                  return;
                }
                _pendingSearchRecalcSignature = null;
                _computeMatches(_searchController.text);
              });
            }

            if (tab.verse != null &&
                verses.isNotEmpty &&
                !(tab.openedFromSearch && tab.initialSearchQuery != null)) {
              final jumpSig = '$chapterSig:${tab.verse}';
              final verseToJump = tab.verse!;
              _pendingVerseJumpSignature = jumpSig;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted || _pendingVerseJumpSignature != jumpSig) return;
                _pendingVerseJumpSignature = null;
                unawaited(
                  _jumpToBibleVerse(verseToJump, tab, _scrollController),
                );
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
                  _searchController.text = tab.initialSearchQuery!;
                  _lastSearchActivatedTabId = tab.id;
                });
                _applyInitialSearchFocus(tab);
              });
            }
          }

          _currentVerses = verses;

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
              SelectionArea(
                child: ListView.builder(
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
                    final plainText = '${verse.verse} ${verse.text}';

                    // Compute which occurrence within this verse is the current match.
                    int? currentOccurrence;
                    if (_matchVerseIndices.isNotEmpty &&
                        _matchVerseIndices[_currentMatchIndex] == index) {
                      currentOccurrence = _matchVerseIndices
                          .sublist(0, _currentMatchIndex)
                          .where((vi) => vi == index)
                          .length;
                    }

                    return GestureDetector(
                      key: _ensureBibleVerseKey(tab, verse.verse),
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
                        child: SelectableText.rich(
                          TextSpan(
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
                          onSelectionChanged: (selection, cause) {
                            if (selection.start == selection.end) {
                              if (_activeSelectionText != null) {
                                setState(() => _activeSelectionText = null);
                              }
                              return;
                            }
                            final start = selection.start.clamp(
                              0,
                              plainText.length,
                            );
                            final end = selection.end.clamp(
                              0,
                              plainText.length,
                            );
                            if (start >= end) return;
                            final selected = plainText
                                .substring(start, end)
                                .trim();
                            if (selected.isEmpty) return;
                            setState(() {
                              _activeSelectionText = selected;
                              _selectedVerseNumbers.clear();
                              _lastVerseTapped = null;
                            });
                          },
                        ),
                      ),
                    );
                  },
                ),
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
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) {
          final isFileError = err is FileSystemException;
          final lower = err.toString().toLowerCase();
          final message =
              isFileError &&
                  lower.contains('database file not found') &&
                  lower.contains('bible_') &&
                  lower.contains('.db')
              ? 'Bible database is not installed. Import Tamil/English Bible database to continue.'
              : err.toString();

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 40),
                const SizedBox(height: 12),
                Text(
                  'Error loading chapter',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (isFileError) ...[
                  const SizedBox(height: 20),
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
          );
        },
      );
    }

    return Center(child: Text('Unsupported content for ${tab.title}'));
  }

  Widget _buildParallelContent({
    required ReaderTab primaryTab,
    required ReaderTab secondaryTab,
    required TypographySettings typography,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= _parallelWideBreakpoint;
        final ratio = _parallelSplitRatio.clamp(
          _parallelSplitMin,
          _parallelSplitMax,
        );

        final primaryPanel = _buildParallelBiblePanel(
          tab: primaryTab,
          typography: typography,
          controller: _parallelPrimaryScrollController,
          panelTitle: _languageLabel(primaryTab.bibleLang ?? 'en'),
          panelSubtitle: '${primaryTab.book ?? ''} ${primaryTab.chapter ?? ''}'
              .trim(),
          showControls: true,
          isPrimaryPane: true,
        );

        final secondaryPanel = _buildParallelBiblePanel(
          tab: secondaryTab,
          typography: typography,
          controller: _parallelSecondaryScrollController,
          panelTitle: _languageLabel(secondaryTab.bibleLang ?? 'en'),
          panelSubtitle:
              '${secondaryTab.book ?? ''} ${secondaryTab.chapter ?? ''}'.trim(),
          showControls: true,
          isPrimaryPane: false,
        );

        if (isWide) {
          final width = constraints.maxWidth;
          final leftWidth = (width * ratio).clamp(
            width * _parallelSplitMin,
            width * _parallelSplitMax,
          );
          final rightWidth = width - leftWidth - _parallelSplitterWidth;

          return Row(
            children: [
              SizedBox(width: leftWidth, child: primaryPanel),
              MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      final next =
                          _parallelSplitRatio + details.delta.dx / width;
                      _parallelSplitRatio = next.clamp(
                        _parallelSplitMin,
                        _parallelSplitMax,
                      );
                    });
                  },
                  onHorizontalDragEnd: (_) {
                    unawaited(_persistParallelSplitRatio());
                  },
                  onDoubleTap: () {
                    setState(() {
                      _parallelSplitRatio = _parallelSplitDefault;
                    });
                    unawaited(_persistParallelSplitRatio());
                  },
                  child: SizedBox(
                    width: _parallelSplitterWidth,
                    child: Center(
                      child: Container(
                        width: 2,
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: rightWidth, child: secondaryPanel),
            ],
          );
        }

        final height = constraints.maxHeight;
        final topHeight = (height * ratio).clamp(
          height * _parallelSplitMin,
          height * _parallelSplitMax,
        );
        final bottomHeight = height - topHeight - _parallelSplitterWidth;

        return Column(
          children: [
            SizedBox(height: topHeight, child: primaryPanel),
            MouseRegion(
              cursor: SystemMouseCursors.resizeRow,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: (details) {
                  setState(() {
                    final next =
                        _parallelSplitRatio + details.delta.dy / height;
                    _parallelSplitRatio = next.clamp(
                      _parallelSplitMin,
                      _parallelSplitMax,
                    );
                  });
                },
                onVerticalDragEnd: (_) {
                  unawaited(_persistParallelSplitRatio());
                },
                onDoubleTap: () {
                  setState(() {
                    _parallelSplitRatio = _parallelSplitDefault;
                  });
                  unawaited(_persistParallelSplitRatio());
                },
                child: SizedBox(
                  height: _parallelSplitterWidth,
                  child: Center(
                    child: Container(
                      height: 2,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: bottomHeight, child: secondaryPanel),
          ],
        );
      },
    );
  }

  Widget _buildParallelBiblePanel({
    required ReaderTab tab,
    required TypographySettings typography,
    required ScrollController controller,
    required String panelTitle,
    required String panelSubtitle,
    bool showHeader = true,
    required bool showControls,
    required bool isPrimaryPane,
    VoidCallback? onPrevious,
    VoidCallback? onNext,
    VoidCallback? onAllBooks,
    String allBooksLabel = 'All Books',
    String? searchQuery,
    List<int>? searchMatchVerseIndices,
    int searchCurrentMatchIndex = 0,
    ValueChanged<List<BibleSearchResult>>? onVersesResolved,
  }) {
    final asyncVerses = ref.watch(chapterVersesProvider(tab));
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: cs.outlineVariant.withAlpha(90))),
      ),
      child: Column(
        children: [
          if (showHeader)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withAlpha(160),
                border: Border(
                  bottom: BorderSide(color: cs.outlineVariant.withAlpha(100)),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    panelTitle,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      panelSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (showControls) ...[
                    IconButton(
                      icon: const Icon(Icons.remove),
                      tooltip: 'Decrease text size',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _adjustParallelPaneFontSize(
                        isPrimary: isPrimaryPane,
                        delta: -1,
                      ),
                    ),
                    Text(
                      _parallelPaneFontSize(
                        typography,
                        isPrimaryPane,
                      ).toStringAsFixed(0),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      tooltip: 'Increase text size',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _adjustParallelPaneFontSize(
                        isPrimary: isPrimaryPane,
                        delta: 1,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (showControls)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: cs.outlineVariant.withAlpha(85)),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    tooltip: 'Previous chapter',
                    visualDensity: VisualDensity.compact,
                    onPressed:
                        onPrevious ??
                        () => _openAdjacentParallelBiblePassage(-1),
                  ),
                  Expanded(
                    child: Center(
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed:
                            onAllBooks ??
                            () => _openParallelQuickNav(
                              forPrimaryPane: isPrimaryPane,
                            ),
                        icon: const Icon(Icons.menu_book_outlined, size: 16),
                        label: Text(allBooksLabel),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    tooltip: 'Next chapter',
                    visualDensity: VisualDensity.compact,
                    onPressed:
                        onNext ?? () => _openAdjacentParallelBiblePassage(1),
                  ),
                ],
              ),
            ),
          Expanded(
            child: asyncVerses.when(
              data: (verses) {
                final paneSig = '${tab.id}|${tab.book}|${tab.chapter}';
                if (_lastParallelBiblePaneSig[tab.id] != paneSig) {
                  _lastParallelBiblePaneSig[tab.id] = paneSig;
                  _pruneVerseAnchorsForTab(tab.id);
                }

                if (onVersesResolved != null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    onVersesResolved(verses);
                  });
                }
                if (verses.isEmpty) {
                  return const Center(
                    child: Text('No verses found in this chapter.'),
                  );
                }

                final paneFontSize = _parallelPaneFontSize(
                  typography,
                  isPrimaryPane,
                );
                final baseStyle =
                    Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontSize: paneFontSize,
                      height: typography.lineHeight,
                      fontFamily: typography.resolvedFontFamily,
                    ) ??
                    const TextStyle();
                final paneQuery = searchQuery?.trim() ?? '';
                final paneMatches = searchMatchVerseIndices ?? const <int>[];
                final paneCurrentItemIndex = paneMatches.isNotEmpty
                    ? paneMatches[searchCurrentMatchIndex.clamp(
                        0,
                        paneMatches.length - 1,
                      )]
                    : null;
                final highlightStyle = TextStyle(
                  backgroundColor: Colors.yellow.withAlpha(100),
                  color: Colors.black,
                );
                final currentMatchStyle = TextStyle(
                  backgroundColor: Colors.orange.withAlpha(170),
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                );

                return SelectionArea(
                  child: ListView.builder(
                    controller: controller,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: verses.length,
                    itemBuilder: (context, index) {
                      final verse = verses[index];
                      final isSelected = _selectedVerseNumbers.contains(
                        verse.verse,
                      );
                      final plainText = '${verse.verse} ${verse.text}';
                      int? currentOccurrence;
                      if (paneMatches.isNotEmpty &&
                          paneCurrentItemIndex == index) {
                        currentOccurrence = paneMatches
                            .sublist(
                              0,
                              searchCurrentMatchIndex.clamp(
                                0,
                                paneMatches.length,
                              ),
                            )
                            .where((vi) => vi == index)
                            .length;
                      }

                      return GestureDetector(
                        key: _ensureBibleVerseKey(tab, verse.verse),
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
                          child: SelectableText.rich(
                            TextSpan(
                              style: baseStyle,
                              children: [
                                TextSpan(
                                  text: '${verse.verse} ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: paneFontSize * 0.8,
                                    color: isSelected
                                        ? cs.primary
                                        : cs.onSurfaceVariant,
                                  ),
                                ),
                                ..._buildHighlightedSpansForQuery(
                                  verse.text,
                                  baseStyle,
                                  highlightStyle,
                                  currentMatchStyle,
                                  paneQuery,
                                  currentOccurrenceIndex: currentOccurrence,
                                ),
                              ],
                            ),
                            onSelectionChanged: (selection, cause) {
                              if (selection.start == selection.end) {
                                if (_activeSelectionText != null) {
                                  setState(() => _activeSelectionText = null);
                                }
                                return;
                              }
                              final start = selection.start.clamp(
                                0,
                                plainText.length,
                              );
                              final end = selection.end.clamp(
                                0,
                                plainText.length,
                              );
                              if (start >= end) return;
                              final selected = plainText
                                  .substring(start, end)
                                  .trim();
                              if (selected.isEmpty) return;
                              setState(() {
                                _activeSelectionText = selected;
                                _selectedVerseNumbers.clear();
                                _lastVerseTapped = null;
                              });
                            },
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    err.toString(),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom tab bar ────────────────────────────────────────────────────────

  Widget _buildBottomTabBar(
    BuildContext context,
    ReaderState state,
    WidgetRef ref,
  ) {
    final theme = Theme.of(context);
    final activeTab = state.activeTab;
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
                // Scrollable tab chips
                Expanded(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: state.tabs.length,
                    itemBuilder: (context, index) {
                      final tab = state.tabs[index];
                      final isActive = index == state.activeTabIndex;
                      return GestureDetector(
                        onTap: () {
                          if (isActive && tab.type == ReaderContentType.bible) {
                            _openQuickNav(
                              initialLang: tab.bibleLang,
                              initialOpenInNewTab: false,
                            );
                            return;
                          }
                          ref.read(readerProvider.notifier).switchTab(index);
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
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
                              Text(
                                _shortenTabTitle(tab.title),
                                style: TextStyle(
                                  fontWeight: isActive
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isActive
                                      ? theme.colorScheme.onPrimaryContainer
                                      : theme.colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(width: 4),
                              InkWell(
                                onTap: () => ref
                                    .read(readerProvider.notifier)
                                    .closeTab(index),
                                child: Icon(
                                  Icons.close,
                                  size: 16,
                                  color: isActive
                                      ? theme.colorScheme.onPrimaryContainer
                                      : theme.colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // "+" opens Quick Navigation
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _openQuickNav,
                  visualDensity: VisualDensity.compact,
                ),

                // "⋮" three-dots popup
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  itemBuilder: (_) => [
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
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'close_others',
                      child: Text('Close Other Tabs'),
                    ),
                  ],
                  onSelected: (val) {
                    if (val == 'share_link' || val == 'copy_link') {
                      final lang =
                          activeTab?.bibleLang ??
                          ref.read(selectedBibleLangProvider);
                      final book = Uri.encodeComponent(activeTab?.book ?? '');
                      final chapter = activeTab?.chapter ?? 1;
                      final deepLink =
                          'https://endtimebride.in/appshare/bible?book=$book&chapter=$chapter&lang=$lang';

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
                    if (val == 'download_pdf') _downloadBiblePdf();
                    if (val == 'print_pdf') _printBiblePdf();
                    if (val == 'close_others') _closeOtherTabs();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _shortenTabTitle(String title) {
    if (title.length > 15) return '${title.substring(0, 12)}...';
    return title;
  }
}
