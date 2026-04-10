import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart' show SharePlus, ShareParams;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/desktop_file_saver.dart';
import '../../core/widgets/responsive_bottom_sheet.dart';
import '../../core/widgets/selection_action_bar.dart';
import 'providers/reader_provider.dart';
import 'providers/typography_provider.dart';
import 'models/reader_tab.dart';
import 'widgets/reader_settings_sheet.dart';
import 'widgets/quick_navigation_sheet.dart';
import '../../core/database/models/bible_search_result.dart';
import '../../core/utils/pdf_fonts.dart';
import '../common/widgets/fts_highlight_text.dart';
import '../onboarding/onboarding_screen.dart';

enum BibleSearchScope { chapter, book, all }

enum BibleSearchMode { smart, exactPhrase, anyWord }

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
  static const int _globalBiblePageSize = 50;
  static const String _searchModePrefKey = 'reader_search_mode';
  static const String _parallelSplitRatioPrefKey = 'reader_en_ta_split_ratio';
  static const double _parallelWideBreakpoint = 900.0;
  static const double _parallelSplitDefault = 0.5;
  static const double _parallelSplitMin = 0.3;
  static const double _parallelSplitMax = 0.7;
  static const double _parallelSplitterWidth = 8.0;

  // ── Scroll controller (preserves position across fullscreen toggle) ────────
  final ScrollController _scrollController = ScrollController();
  final ScrollController _parallelPrimaryScrollController = ScrollController();
  final ScrollController _parallelSecondaryScrollController =
      ScrollController();
  final FocusNode _searchFieldFocusNode = FocusNode();
  late final bool Function(KeyEvent) _searchKeyHandler;

  String? _parallelSourceTabId;
  ReaderTab? _parallelEnglishTab;
  double _parallelSplitRatio = _parallelSplitDefault;
  double _parallelPrimaryFontOffset = 0;
  double _parallelSecondaryFontOffset = 0;

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
  String? _pendingSearchRecalcSignature;
  String? _pendingVerseJumpSignature;
  String? _initialSearchScrollTabId;

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

  @override
  void dispose() {
    _scrollController.dispose();
    _parallelPrimaryScrollController.dispose();
    _parallelSecondaryScrollController.dispose();
    _searchController.dispose();
    _searchFieldFocusNode.dispose();
    _globalSearchDebounce?.cancel();
    HardwareKeyboard.instance.removeHandler(_searchKeyHandler);
    super.dispose();
  }

  // ── Navigation handler (shared by AppBar title + FAB) ─────────────────────

  Future<void> _openQuickNav() async {
    final result = await showResponsiveBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      maxWidth: 980,
      builder: (_) => const QuickNavigationSheet(),
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

    final englishTab = ReaderTab(
      type: ReaderContentType.bible,
      title: '$mappedBook ${activeTab.chapter}',
      book: mappedBook,
      chapter: activeTab.chapter,
      verse: activeTab.verse,
      bibleLang: 'en',
    );

    _resetGlobalSearchState(clearQuery: false);
    if (!mounted) return;
    setState(() {
      _parallelSourceTabId = activeTab.id;
      _parallelEnglishTab = englishTab;
    });
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
    final offset = isPrimary
        ? _parallelPrimaryFontOffset
        : _parallelSecondaryFontOffset;
    return (typography.fontSize + offset).clamp(12.0, 56.0);
  }

  void _adjustParallelPaneFontSize({
    required bool isPrimary,
    required double delta,
  }) {
    setState(() {
      if (isPrimary) {
        _parallelPrimaryFontOffset = (_parallelPrimaryFontOffset + delta).clamp(
          12.0 - ref.read(typographyProvider).fontSize,
          56.0 - ref.read(typographyProvider).fontSize,
        );
      } else {
        _parallelSecondaryFontOffset = (_parallelSecondaryFontOffset + delta)
            .clamp(
              12.0 - ref.read(typographyProvider).fontSize,
              56.0 - ref.read(typographyProvider).fontSize,
            );
      }
    });
  }

  Future<void> _openAdjacentParallelBiblePassage(int direction) async {
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
    final mappedEnglishBook = await _mapBookNameForLanguage(
      sourceBook: nextSourceBook,
      sourceLang: sourceLang,
      targetLang: 'en',
    );

    final nextSourceTab = activeTab.copyWith(
      title: '$nextSourceBook $nextChapter',
      book: nextSourceBook,
      chapter: nextChapter,
      verse: null,
      initialSearchQuery: null,
      openedFromSearch: false,
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

    ref.read(readerProvider.notifier).replaceCurrentTab(nextSourceTab);
    if (!mounted) return;
    setState(() {
      _parallelEnglishTab = nextEnglishTab;
    });
  }

  Future<void> _openParallelQuickNav() async {
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
    final result = await showResponsiveBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      maxWidth: 980,
      builder: (_) => QuickNavigationSheet(initialLang: sourceLang),
    );
    if (result == null) return;

    final selectedBook = result['book'] as String?;
    final selectedChapter = result['chapter'] as int?;
    final selectedVerse = result['verse'] as int?;
    if (selectedBook == null || selectedChapter == null) return;

    final mappedEnglishBook = await _mapBookNameForLanguage(
      sourceBook: selectedBook,
      sourceLang: sourceLang,
      targetLang: 'en',
    );

    final nextSourceTab = activeTab.copyWith(
      title: '$selectedBook $selectedChapter',
      book: selectedBook,
      chapter: selectedChapter,
      verse: selectedVerse,
      initialSearchQuery: null,
      openedFromSearch: false,
    );

    final nextEnglishTab = englishTab.copyWith(
      title: '$mappedEnglishBook $selectedChapter',
      book: mappedEnglishBook,
      chapter: selectedChapter,
      verse: selectedVerse,
      bibleLang: 'en',
      initialSearchQuery: null,
      openedFromSearch: false,
    );

    ref.read(readerProvider.notifier).replaceCurrentTab(nextSourceTab);
    if (!mounted) return;
    setState(() {
      _parallelEnglishTab = nextEnglishTab;
      _selectedVerseNumbers.clear();
      _activeSelectionText = null;
      _lastVerseTapped = null;
    });
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
        ),
        repo.countSearchResults(
          query,
          bookFilters: bookFilters,
          chapterFrom: chapterFrom,
          chapterTo: chapterTo,
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
    SharePlus.instance.share(ShareParams(text: text));
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

  Future<pw.Document> _buildBiblePdf() async {
    final activeTab = ref.read(readerProvider).activeTab;
    final typography = ref.read(typographyProvider);
    final verses = _currentVerses;

    final doc = pw.Document();
    const accentColor = PdfColor.fromInt(0xFF1C6BC9);
    final lang = activeTab?.bibleLang ?? ref.read(selectedBibleLangProvider);

    // Use embedded Tamil fonts when lang == 'ta', otherwise fallback to
    // standard Noto Sans via PdfGoogleFonts.
    final bodyFont = lang == 'ta'
        ? await AppPdfFonts.tamilRegular()
        : await PdfGoogleFonts.notoSansRegular();
    final boldFont = lang == 'ta'
        ? await AppPdfFonts.tamilBold()
        : await PdfGoogleFonts.notoSansBold();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          final List<pw.Widget> widgets = [];

          // Header
          widgets.add(
            pw.Center(
              child: pw.Text(
                activeTab?.title ?? 'Bible',
                style: pw.TextStyle(
                  font: boldFont,
                  fontSize: 18,
                  color: accentColor,
                ),
              ),
            ),
          );
          widgets.add(pw.SizedBox(height: 12));
          widgets.add(pw.Divider(color: PdfColors.grey300));
          widgets.add(pw.SizedBox(height: 8));

          // Content
          for (final v in verses) {
            final rawText = v.text;

            // Emit verse number
            widgets.add(pw.SizedBox(height: 8));
            widgets.add(
              pw.Text(
                'Verse ${v.verse}',
                style: pw.TextStyle(
                  font: boldFont,
                  fontSize: 8,
                  color: accentColor,
                ),
              ),
            );

            // Split text by actual newlines and render as simple breakable Text widgets.
            // Do NOT use pw.Padding or pw.Container, as they are unbreakable across pages.
            final rawLines = const LineSplitter().convert(rawText);
            for (final rawLine in rawLines) {
              if (rawLine.trim().isEmpty) continue;

              widgets.add(
                pw.Text(
                  rawLine,
                  style: pw.TextStyle(
                    font: bodyFont,
                    fontSize: typography.fontSize * 0.9,
                    lineSpacing:
                        (typography.lineHeight - 1) * typography.fontSize * 0.5,
                  ),
                ),
              );
              // Add vertical spacing using a peer widget instead of Padding
              widgets.add(pw.SizedBox(height: 4));
            }
          }

          return widgets;
        },
      ),
    );
    return doc;
  }

  String _sanitizePdfName(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[<>:"/\\\\|?*]'), '-').trim();
    return cleaned.isEmpty ? 'Document' : cleaned;
  }

  Future<void> _printBiblePdf() async {
    final doc = await _buildBiblePdf();
    final rawTitle = ref.read(readerProvider).activeTab?.title ?? 'Bible';
    final safeTitle = _sanitizePdfName(rawTitle);
    await Printing.layoutPdf(
      onLayout: (_) async => doc.save(),
      name: safeTitle,
    );
  }

  Future<void> _downloadBiblePdf() async {
    final doc = await _buildBiblePdf();
    final bytes = await doc.save();

    final rawTitle = ref.read(readerProvider).activeTab?.title ?? 'Bible';
    final safeTitle = _sanitizePdfName(rawTitle);
    final filename = '$safeTitle.pdf';

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

    final query = _searchController.text;
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
    final typographyState = ref.watch(typographyProvider);
    final activeTab = readerState.activeTab;
    final bibleReadLang =
        activeTab?.bibleLang ?? ref.watch(selectedBibleLangProvider) ?? 'en';
    ref
        .read(typographyProvider.notifier)
        .setReaderContentLanguage(bibleReadLang);
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

    if (!isParallelMode &&
        (_parallelSourceTabId != null || _parallelEnglishTab != null)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _clearParallelMode();
      });
    }

    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.enter): const _NextMatchIntent(),
        LogicalKeySet(LogicalKeyboardKey.shift, LogicalKeyboardKey.enter):
            const _PrevMatchIntent(),
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
                : (_isSearching
                      ? _buildSearchAppBar(context, activeTab)
                      : _buildDefaultAppBar(context, activeTab)),
            body: activeTab == null
                ? const Center(child: Text('No open tabs. Please open a book.'))
                : isFullscreen
                ? Stack(
                    children: [
                      Column(
                        children: [
                          Expanded(
                            child: isParallelMode && englishParallelTab != null
                                ? _buildParallelContent(
                                    primaryTab: activeTab,
                                    secondaryTab: englishParallelTab,
                                    typography: typographyState,
                                  )
                                : _buildTabContent(activeTab, typographyState),
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
                                  .read(typographyProvider.notifier)
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
                    _hasAnySelection)
                ? null
                : FloatingActionButton(
                    onPressed: _openQuickNav,
                    child: const Icon(Icons.menu_book_rounded),
                  ),
            floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
            bottomNavigationBar:
                (!isFullscreen && readerState.tabs.isNotEmpty && !_isSearching)
                ? _buildBottomTabBar(context, readerState, ref)
                : null,
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
                    _scheduleScopeSearch(activeTab, immediate: true);
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
      controller: _scrollController,
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

  AppBar _buildDefaultAppBar(BuildContext context, ReaderTab? activeTab) {
    final hasSelection = _selectedVerseNumbers.isNotEmpty;
    final openedFromSearch = activeTab?.openedFromSearch ?? false;
    final isBibleTab =
        activeTab?.type == ReaderContentType.bible && activeTab?.book != null;
    final activeLang =
        (activeTab?.bibleLang ?? ref.read(selectedBibleLangProvider)) ?? 'en';
    final isTamilBibleTab = isBibleTab && activeLang == 'ta';
    final isCompactAppBar = MediaQuery.sizeOf(context).width < 700;
    final showCompactTamilOptions = isTamilBibleTab && isCompactAppBar;

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
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
      title: LayoutBuilder(
        builder: (context, constraints) {
          final showPcShortcuts = constraints.maxWidth >= 700 && isBibleTab;
          if (!showPcShortcuts) {
            return InkWell(
              onTap: _openQuickNav,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(activeTab?.title ?? 'Reader'),
                  const Icon(Icons.arrow_drop_down),
                ],
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
                    Text(activeTab?.title ?? 'Reader'),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
              const SizedBox(width: 24),
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
                      child: const Text('Old Testament'),
                    ),
                    TextButton(
                      onPressed: () => _openQuickNavForTestament(1),
                      child: const Text('New Testament'),
                    ),
                    if (isTamilBibleTab) ...[
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: () => _openEnglishParallel(
                          activeTab,
                          sourceLangOverride: activeLang,
                        ),
                        child: const Text('English Parallel'),
                      ),
                      TextButton(
                        onPressed: () => _switchToEnglishBible(
                          activeTab,
                          sourceLangOverride: activeLang,
                        ),
                        child: const Text('English Bible'),
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
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              _resetGlobalSearchState();
              setState(() {
                _isSearching = true;
              });
            },
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

  Widget _buildTabContent(ReaderTab tab, TypographySettings typography) {
    if (tab.type == ReaderContentType.bible &&
        tab.book != null &&
        tab.chapter != null) {
      final asyncVerses = ref.watch(chapterVersesProvider(tab));

      return asyncVerses.when(
        data: (verses) {
          // Keep render path side-effect free: no setState/post-frame callbacks.
          final chapterSig = '${tab.id}:${tab.book}:${tab.chapter}';
          final chapterChanged = _lastChapterSignature != chapterSig;
          if (chapterChanged) {
            _lastChapterSignature = chapterSig;
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

            // Re-enable quick-nav verse jump once per chapter signature.
            if (tab.verse != null &&
                verses.isNotEmpty &&
                !(tab.openedFromSearch && tab.initialSearchQuery != null)) {
              final jumpSig = '$chapterSig:${tab.verse}';
              _pendingVerseJumpSignature = jumpSig;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted || _pendingVerseJumpSignature != jumpSig) return;
                _pendingVerseJumpSignature = null;
                if (!_scrollController.hasClients) return;
                final idx = (tab.verse! - 1).clamp(0, verses.length - 1);
                final frac = (idx / verses.length).clamp(0.0, 1.0);
                final target =
                    frac * _scrollController.position.maxScrollExtent;
                _scrollController.animateTo(
                  target,
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
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
                      key: ValueKey<int>(verse.verse),
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
          final message = err.toString();

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
          panelTitle: 'Tamil',
          panelSubtitle: '${primaryTab.book ?? ''} ${primaryTab.chapter ?? ''}'
              .trim(),
          showControls: true,
          isPrimaryPane: true,
        );

        final secondaryPanel = _buildParallelBiblePanel(
          tab: secondaryTab,
          typography: typography,
          controller: _parallelSecondaryScrollController,
          panelTitle: 'English',
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
    required bool showControls,
    required bool isPrimaryPane,
  }) {
    final asyncVerses = ref.watch(chapterVersesProvider(tab));
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: cs.outlineVariant.withAlpha(90))),
      ),
      child: Column(
        children: [
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
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
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
                    icon: const Icon(Icons.chevron_left),
                    tooltip: 'Previous chapter',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _openAdjacentParallelBiblePassage(-1),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    tooltip: 'Next chapter',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _openAdjacentParallelBiblePassage(1),
                  ),
                  IconButton(
                    icon: const Icon(Icons.menu_book_outlined),
                    tooltip: 'Choose chapter',
                    visualDensity: VisualDensity.compact,
                    onPressed: _openParallelQuickNav,
                  ),
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
          Expanded(
            child: asyncVerses.when(
              data: (verses) {
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

                      return GestureDetector(
                        key: ValueKey<String>('${tab.id}:${verse.verse}'),
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
                                TextSpan(text: verse.text),
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
                        onTap: () =>
                            ref.read(readerProvider.notifier).switchTab(index),
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
