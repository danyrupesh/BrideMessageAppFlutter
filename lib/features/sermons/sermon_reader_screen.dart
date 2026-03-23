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
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/desktop_file_saver.dart';
import '../../core/widgets/responsive_bottom_sheet.dart';
import '../../core/widgets/selection_action_bar.dart';
import 'providers/sermon_flow_provider.dart';
import 'providers/sermon_provider.dart';
import 'utils/sermon_pdf_generator.dart';
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
import '../notes/notes_edit_screen.dart';
import '../notes/models/source_ref.dart';
import '../notes/data/notes_append_extension.dart';
import '../notes/providers/notes_provider.dart';
import '../../core/widgets/previous_notes_widget.dart';

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

  const _AppBarChip({required this.label, required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: cs.primaryContainer.withAlpha(160),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: cs.primary),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
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
  final ValueChanged<String>? onAddToNote;

  const SermonSelectionWidget({
    super.key,
    required this.combinedSpan,
    required this.scrollController,
    this.onAddToNote,
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
                    if (widget.onAddToNote != null) ...[
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () {
                          widget.onAddToNote!(selectedText!);
                          _removePopover();
                        },
                        child: const Text(
                          "Add to Note",
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
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
  // ── Note pane state ──────────────────────────────────────────────────────
  bool _isNotePaneOpen = false;

  // ── Scroll controller (preserves position across fullscreen toggle) ────────
  final ScrollController _scrollController = ScrollController();

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
  String? _lastActiveTabId;
  String? _initialSearchScrollTabId;

  // ── Paragraph cache (for "This Sermon" in-page search) ───────────────────
  List<SermonParagraphEntity> _currentParagraphs = [];
  int? _selectionFirstParagraph;
  int? _selectionLastParagraph;

  // ── UI state ──────────────────────────────────────────────────────────────
  bool _fabExpanded = false;
  bool _hideBottomTabs = false;
  final ScrollController _bmBibleScrollController = ScrollController();
  static const double _bmWideBreakpoint = 900.0;
  static const double _bmSplitDefault = 0.6;
  static const double _bmSplitMin = 0.35;
  static const double _bmSplitMax = 0.75;
  static const double _bmSplitterWidth = 8.0;
  static const String _bmSplitRatioKey = 'sermon_bm_split_ratio';
  double _bmSplitRatio = _bmSplitDefault;
  final FocusNode _searchFieldFocusNode = FocusNode();
  late final bool Function(KeyEvent) _searchKeyHandler;

  void _toggleNotePane() {
    final width = MediaQuery.of(context).size.width;
    if (width > 800) {
      setState(() => _isNotePaneOpen = !_isNotePaneOpen);
    } else {
      context.push('/notes/edit?attach=true', extra: null); 
      // Extra could be null, but we probably want a quick sheet, or navigate to edit with attach=true. 
      // Actually we'll implement _SermonNoteSheet but since NotesEditScreen is a top level screen,
      // wait! We can just use the Navigator and push a MaterialPageRoute for a more integrated feeling.
    }
  }

  void _handleAddToNote([String? optionalText]) async {
    String? text = optionalText ?? _activeSelectionText;
    if (text == null || text.trim().isEmpty) return;
    
    final footer = _buildSermonSelectionFooter();
    final combined = '$text\n— $footer\n';

    final activeNoteId = ref.read(sermonFlowProvider).activeNoteId;
    if (activeNoteId == null) {
      // If there's no active note, just open the pane/screen
      _toggleNotePane();
    } else {
      // Automatically append to the bottom
      await appendTextToNote(ref, activeNoteId, combined);
      
      setState(() => _activeSelectionText = null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Appended to current Note'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

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
    _loadBmSplitRatio();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _bmBibleScrollController.dispose();
    _searchController.dispose();
    _searchFieldFocusNode.dispose();
    HardwareKeyboard.instance.removeHandler(_searchKeyHandler);
    super.dispose();
  }

  Future<void> _loadBmSplitRatio() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getDouble(_bmSplitRatioKey);
    if (!mounted || stored == null) return;
    setState(() {
      _bmSplitRatio = stored.clamp(_bmSplitMin, _bmSplitMax);
    });
  }

  Future<void> _persistBmSplitRatio() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_bmSplitRatioKey, _bmSplitRatio);
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
    ref
        .read(sermonFlowProvider.notifier)
        .addSermonTab(
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
    });
  }

  // ── Quick-nav — Bible ──────────────────────────────────────────────────────

  Future<void> _openQuickNav() async {
    final flowState = ref.read(sermonFlowProvider);
    final isBmMode = flowState.bmMode;
    setState(() => _fabExpanded = false);
    final result = await showResponsiveBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      maxWidth: 980,
      builder: (_) => const QuickNavigationSheet(),
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
    ref
        .read(sermonFlowProvider.notifier)
        .upsertBmBibleTab(
          bibleTab: newTab,
          openInNewTab: result['newTab'] == true,
        );
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
      builder: (_) => const QuickNavigationSheet(),
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
      ref
          .read(sermonFlowProvider.notifier)
          .upsertBmBibleTab(bibleTab: newTab, openInNewTab: false);
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
          ref
              .read(sermonFlowProvider.notifier)
              .addSermonTab(
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
    ref
        .read(sermonFlowProvider.notifier)
        .addSermonTab(
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

  int? _currentOccurrenceForItem(int itemIndex) {
    if (_matchVerseIndices.isEmpty) return null;
    if (_currentMatchIndex < 0 ||
        _currentMatchIndex >= _matchVerseIndices.length) {
      return null;
    }
    if (_matchVerseIndices[_currentMatchIndex] != itemIndex) return null;

    var count = 0;
    for (var i = 0; i < _currentMatchIndex; i++) {
      if (_matchVerseIndices[i] == itemIndex) count++;
    }
    return count;
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

  void _scrollToCurrentMatch({int retryCount = 0, bool instantScroll = false}) {
    if (_matchVerseIndices.isEmpty) return;
    final vi = _matchVerseIndices[_currentMatchIndex];
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
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
          _jumpAlignParagraphUnderBars(vi);
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

  bool get _hasSelectionPopover {
    final textSelected = _activeSelectionText?.trim().isNotEmpty ?? false;
    return textSelected;
  }

  void _clearSelectionPopover() {
    setState(() {
      _activeSelectionText = null;
    });
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

  Future<pw.Document> _buildSermonPdf() async {
    final flowState = ref.read(sermonFlowProvider);
    final activeTab = flowState.activeTab;
    final lang = ref.read(selectedSermonLangProvider);

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

    return buildTamilSermonPdf(sermon: sermon, paragraphs: _currentParagraphs);
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
      final doc = await _buildSermonPdf();
      final rawTitle =
          ref.read(sermonFlowProvider).activeTab?.title ?? 'Sermon';
      final safeTitle = _sanitizePdfName(rawTitle);
      await Printing.layoutPdf(
        onLayout: (_) async => doc.save(),
        name: safeTitle,
      );
    });
  }

  Future<void> _downloadSermonPdf() async {
    await _withPdfProgress(() async {
      final doc = await _buildSermonPdf();
      final bytes = await doc.save();

      final rawTitle =
          ref.read(sermonFlowProvider).activeTab?.title ?? 'Sermon';
      final safeTitle = _sanitizePdfName(rawTitle);
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
          'prefix': 'கேள்வி',
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
          'prefix': 'Question',
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
    int? currentOccurrenceIndex,
  }) {
    // Don't highlight while browsing All-Sermons results — text not visible.
    if (!_isSearching || _searchAllSermons || _searchController.text.isEmpty) {
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

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final flowState = ref.watch(sermonFlowProvider);
    final typographyState = ref.watch(typographyProvider);
    final activeTab = flowState.activeTab;
    final sermonLang = ref.watch(selectedSermonLangProvider);
    final bibleLangFallback = ref.watch(selectedBibleLangProvider);
    final readerTypographyLang = activeTab?.type == ReaderContentType.bible
        ? (activeTab?.bibleLang ?? bibleLangFallback)
        : sermonLang;
    ref
        .read(typographyProvider.notifier)
        .setReaderContentLanguage(readerTypographyLang);
    final isFullscreen = typographyState.isFullscreen;
    final openedFromSearch = activeTab?.openedFromSearch ?? false;

    // Clear search state if tab changed and doesn't have initialSearchQuery
    WidgetsBinding.instance.addPostFrameCallback((_) async {
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
      
      // Attempt to load existing Note connection for this sermon.
      if (tabChanged && 
          activeTab?.type == ReaderContentType.sermon && 
          activeTab?.sermonId != null &&
          flowState.activeNoteId == null) {
        final repo = ref.read(notesRepositoryProvider);
        final existingNote = await repo.findRecentNoteBySourceId('sermon', activeTab!.sermonId!);
        if (existingNote != null && mounted) {
           ref.read(sermonFlowProvider.notifier).setActiveNoteId(existingNote.id!);
        }
      }

      _lastActiveTabId = activeId;
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
              child: _buildMainContent(
                context,
                activeTab,
                flowState,
                typographyState,
                isFullscreen,
                openedFromSearch,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent(
    BuildContext context,
    ReaderTab? activeTab,
    SermonFlowState flowState,
    TypographySettings typographyState,
    bool isFullscreen,
    bool openedFromSearch,
  ) {
    final mainScaffold = Scaffold(
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
    );

    if (_isNotePaneOpen && MediaQuery.of(context).size.width > 800) {
      final sourceRef = activeTab != null
          ? NoteSourceRef(
              id: activeTab.sermonId ?? 'unknown',
              title: activeTab.title,
              type: NoteSourceType.sermon,
              sermonId: activeTab.sermonId,
            )
          : null;

      return Row(
        children: [
          Expanded(
            flex: 2,
            child: mainScaffold,
          ),
          const VerticalDivider(width: 1, thickness: 1),
          // We wrap NotesEditScreen in Expanded & its own key so it rebuilds properly if noteId changes.
          // In a real app we might want a localized state inside NotesEditScreen to observe activeNoteId changes.
          Expanded(
            flex: 1,
            child: NotesEditScreen(
              key: ValueKey('note_${flowState.activeNoteId}'),
              noteId: flowState.activeNoteId,
              initialSource: sourceRef,
            ),
          ),
        ],
      );
    }
    
    return mainScaffold;
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
          onAddToNote: _handleAddToNote,
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
                      ref.read(typographyProvider.notifier).toggleFullscreen(),
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
          }
        },
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
            onPressed: _totalMatches == 0 ? null : () => _navigateToMatch(-1),
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: _totalMatches == 0 ? null : () => _navigateToMatch(1),
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
    TypographySettings typography, {
    bool openedFromSearch = false,
  }) {
    final theme = Theme.of(context);
    final hasSelection = _selectedVerseNumbers.isNotEmpty;
    final isOnBibleTab = flowState.activeTab?.type == ReaderContentType.bible;
    final isSermonTab =
        flowState.activeTab?.type == ReaderContentType.sermon &&
        activeTab?.sermonId != null;

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
              fontSize: typography.titleFontSize,
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
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(activeTab?.title ?? 'Bible Reference'),
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
      toolbarHeight: isOnBibleTab ? kToolbarHeight : 76.0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.pop(),
      ),
      title: LayoutBuilder(
        builder: (context, constraints) {
          final showPcChips = constraints.maxWidth >= 900 && isSermonTab;
          if (!showPcChips) {
            return titleWidget;
          }

          final lang = ref.watch(selectedSermonLangProvider);
          final codLabel = lang == 'ta' ? 'COD Tamil' : 'COD English';
          final sealsLabel = lang == 'ta' ? 'ஏழு முத்திரைகள்' : 'Seven Seals';

          return Row(
            mainAxisAlignment: MainAxisAlignment.start,
            mainAxisSize: MainAxisSize.max,
            children: [
              Expanded(child: titleWidget),
              const SizedBox(width: 16),
              Wrap(
                spacing: 8,
                children: [
                  _AppBarChip(
                    label: codLabel,
                    icon: Icons.article_outlined,
                    onTap: () => _openCodList(context),
                  ),
                  _AppBarChip(
                    label: sealsLabel,
                    icon: Icons.layers_outlined,
                    onTap: () => _openSevenSealsList(context),
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
          if (!openedFromSearch) ...[
            IconButton(
              icon: const Icon(Icons.note_alt_outlined),
              tooltip: 'Notes',
              onPressed: _toggleNotePane,
            ),
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
                itemCount: verses.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                     return PreviousNotesWidget(
                        sourceType: NoteSourceType.bible,
                        sourceId: '${tab.book}_${tab.chapter}',
                     );
                  }
                  
                  final arrayIndex = index - 1;
                  final verse = verses[arrayIndex];
                  final isSelected = _selectedVerseNumbers.contains(
                    verse.verse,
                  );
                  final key = arrayIndex < _verseKeys.length
                      ? _verseKeys[arrayIndex]
                      : GlobalKey();

                  final currentOccurrence = _currentOccurrenceForItem(arrayIndex);

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
        error: (err, _) => Center(child: Text('Error: $err')),
      );
    }

    // Sermon tab (index 0)
    if (tab.type == ReaderContentType.sermon && tab.sermonId != null) {
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
          final sermonList = _buildSermonParagraphList(
            paragraphs,
            typography,
            cs,
          );

          return Column(
            children: [
              _buildSermonNavRow(flowState),
              Expanded(
                child: flowState.bmMode
                    ? _buildBmSplitContent(
                        flowState: flowState,
                        typography: typography,
                        sermonList: sermonList,
                      )
                    : sermonList,
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
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
    final theme = Theme.of(context);
    final bmMode = flowState.bmMode;
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
        mainAxisAlignment: bmMode
            ? MainAxisAlignment.center
            : MainAxisAlignment.spaceBetween,
        children: [
          if (!bmMode)
            TextButton.icon(
              icon: const Icon(Icons.chevron_left, size: 18),
              label: const Text('Previous'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => _openAdjacentSermon(-1),
            ),
          if (!_isSearching)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _NavIconButton(
                  label: 'BM',
                  icon: Icons.view_week,
                  isActive: bmMode,
                  onPressed: () =>
                      ref.read(sermonFlowProvider.notifier).setBmMode(true),
                ),
                const SizedBox(width: 8),
                _NavIconButton(
                  label: 'M',
                  icon: Icons.import_contacts,
                  isActive: !bmMode,
                  onPressed: () =>
                      ref.read(sermonFlowProvider.notifier).setBmMode(false),
                ),
              ],
            ),
          if (!bmMode)
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
    final typography = ref.watch(typographyProvider);
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
                    final lang = ref.read(selectedSermonLangProvider);
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
                      if (lang == 'en') {
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
                    }
                    items.add(
                      const PopupMenuItem(
                        value: 'add_note',
                        child: ListTile(
                          leading: Icon(Icons.note_add_outlined),
                          title: Text('Add Note'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                    );
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
                    if (val == 'add_note') {
                      final sourceLang = isOnBibleTab
                          ? ref.read(selectedBibleLangProvider)
                          : ref.read(selectedSermonLangProvider);
                      final query = isOnBibleTab
                          ? <String, String>{
                              'type': 'bible',
                              'id':
                                  '${activeTab?.book ?? 'Bible'}-${activeTab?.chapter ?? 1}',
                              if ((activeTab?.title ?? '').trim().isNotEmpty)
                                'title': activeTab!.title,
                              if ((activeTab?.book ?? '').trim().isNotEmpty)
                                'book': activeTab!.book!,
                              'chapter': '${activeTab?.chapter ?? 1}',
                              if (activeTab?.verse != null)
                                'verse': '${activeTab!.verse}',
                              'lang': sourceLang,
                            }
                          : <String, String>{
                              'type': 'sermon',
                              'id': activeTab?.sermonId ?? '',
                              if ((activeTab?.title ?? '').trim().isNotEmpty)
                                'title': activeTab!.title,
                              if ((activeTab?.sermonId ?? '').trim().isNotEmpty)
                                'sermonId': activeTab!.sermonId!,
                              'lang': sourceLang,
                            };
                      showModalBottomSheet<void>(
                        context: context,
                        builder: (sheetContext) => SafeArea(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                leading: const Icon(Icons.note_add_outlined),
                                title: const Text('Create New Note'),
                                onTap: () {
                                  Navigator.of(sheetContext).pop();
                                  context.push(
                                    Uri(
                                      path: '/notes/edit',
                                      queryParameters: query,
                                    ).toString(),
                                  );
                                },
                              ),
                              ListTile(
                                leading: const Icon(Icons.link_outlined),
                                title: const Text('Add to Existing Note'),
                                onTap: () {
                                  Navigator.of(sheetContext).pop();
                                  context.push(
                                    Uri(
                                      path: '/notes',
                                      queryParameters: {
                                        ...query,
                                        'attach': '1',
                                      },
                                    ).toString(),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    }
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
    return _buildSermonBody(paragraphs, typography, cs);
  }

  String _shortenTitle(String title) {
    if (title.length > 15) return '${title.substring(0, 12)}...';
    return title;
  }

  Widget _buildSermonBody(
    List<SermonParagraphEntity> paragraphs,
    TypographySettings typography,
    ColorScheme cs,
  ) {
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

    final children = <InlineSpan>[];
    final paragraphRanges = <Map<String, int?>>[];
    var offset = 0;

    for (var i = 0; i < paragraphs.length; i++) {
      final paragraph = paragraphs[i];
      final currentOccurrence = _currentOccurrenceForItem(i);

      // Paragraph number
      if (paragraph.paragraphNumber != null) {
        children.add(
          TextSpan(
            text: '${paragraph.paragraphNumber}¶ ',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: typography.fontSize * 0.8,
              color: Colors.grey,
            ),
          ),
        );
      }

      // Paragraph text
      children.addAll(
        _buildHighlightedSpans(
          paragraph.text,
          baseStyle,
          highlightStyle,
          currentMatchStyle,
          currentOccurrenceIndex: currentOccurrence,
        ),
      );

      if (i < paragraphs.length - 1) {
        // Use a single line break between paragraphs to avoid large gaps.
        children.add(TextSpan(text: '\n', style: baseStyle));
        offset += 1;
      }

      final prefixLength = paragraph.paragraphNumber != null
          ? '${paragraph.paragraphNumber}¶ '.length
          : 0;
      final paraLength = paragraph.text.length;
      paragraphRanges.add({
        'start': offset - prefixLength - paraLength,
        'end': offset,
        'number': paragraph.paragraphNumber,
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
            controller: _scrollController,
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
                            final number = range['number'] as int?;
                            if (number == null) continue;
                            final intersects = start < rEnd && end > rStart;
                            if (!intersects) continue;
                            first = (first == null || number < first!)
                                ? number
                                : first;
                            last = (last == null || number > last!)
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
                _matchVerseIndices,
                _matchVerseIndices.isNotEmpty
                    ? _matchVerseIndices[_currentMatchIndex]
                    : null,
                enabled: _isSearching && !_searchAllSermons,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectionPopover(ColorScheme cs) {
    final theme = Theme.of(context);
    const label = 'Text selected';
    return Material(
      elevation: 6,
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant.withAlpha(140)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.labelMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton.icon(
              onPressed: _copyCurrentSelection,
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy'),
            ),
            const SizedBox(width: 6),
            TextButton.icon(
              onPressed: _shareCurrentSelection,
              icon: const Icon(Icons.share_outlined, size: 18),
              label: const Text('Share'),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Clear selection',
              onPressed: _clearSelectionPopover,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBmSplitContent({
    required SermonFlowState flowState,
    required TypographySettings typography,
    required Widget sermonList,
  }) {
    final theme = Theme.of(context);
    final bmGroup = flowState.bmBibleGroup;
    final bibleTab = bmGroup.tabs.isEmpty
        ? null
        : bmGroup.tabs[bmGroup.activeIndex.clamp(0, bmGroup.tabs.length - 1)];

    final bibleHeader = _buildBmBibleHeader(group: bmGroup);
    final sermonHeader = _buildBmSermonHeader(flowState: flowState);

    final biblePanel = _buildBmPanel(
      header: bibleHeader,
      child: _buildBmBibleContent(bibleTab, typography),
    );

    final sermonPanel = _buildBmPanel(header: sermonHeader, child: sermonList);

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
              SizedBox(width: leftWidth, child: sermonPanel),
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
              SizedBox(width: rightWidth, child: biblePanel),
            ],
          );
        }
        return Column(
          children: [
            Expanded(child: sermonPanel),
            Divider(
              height: 12,
              thickness: 1,
              color: theme.colorScheme.outlineVariant.withAlpha(120),
            ),
            Expanded(child: biblePanel),
          ],
        );
      },
    );
  }

  Widget _buildBmPanel({required Widget header, required Widget child}) {
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
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _buildBmBibleHeader({required BmBibleGroup? group}) {
    final theme = Theme.of(context);
    final typography = ref.watch(typographyProvider);
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
                    onTap: () =>
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
    final typography = ref.watch(typographyProvider);
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
                    onDoubleTap: _isDesktopPlatform
                        ? () => _openSermonQuickNavForTab(index)
                        : null,
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
        title: const Text('Sermon Tabs'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Single click / tap: open this sermon'),
            SizedBox(height: 6),
            Text('Double-click (desktop): change/replace this sermon tab'),
            SizedBox(height: 6),
            Text('Long-press (mobile): change/replace this sermon tab'),
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
    required VoidCallback onClose,
  }) {
    final theme = Theme.of(context);
    final typography = ref.watch(typographyProvider);
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
        final cs = Theme.of(context).colorScheme;
        final baseStyle =
            Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontSize: typography.fontSize,
              height: typography.lineHeight,
              fontFamily: typography.resolvedFontFamily,
            ) ??
            const TextStyle();

        return SelectionArea(
          child: ListView.builder(
            controller: _bmBibleScrollController,
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            itemCount: verses.length,
            itemBuilder: (context, index) {
              final verse = verses[index];
              final isSelected = _selectedVerseNumbers.contains(verse.verse);
              return GestureDetector(
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
                        TextSpan(text: verse.text),
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
      error: (err, _) => Center(child: Text('Error: $err')),
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
