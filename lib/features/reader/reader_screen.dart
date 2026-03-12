import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart' show SharePlus, ShareParams;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/utils/desktop_file_saver.dart';
import 'providers/reader_provider.dart';
import 'providers/typography_provider.dart';
import 'models/reader_tab.dart';
import 'widgets/reader_settings_sheet.dart';
import 'widgets/quick_navigation_sheet.dart';
import '../../core/database/models/bible_search_result.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key});

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  // ── Scroll controller (preserves position across fullscreen toggle) ────────
  final ScrollController _scrollController = ScrollController();

  // ── In-page search ────────────────────────────────────────────────────────
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  /// Flat list of verse indices (one entry per individual match occurrence).
  List<int> _matchVerseIndices = [];
  int _currentMatchIndex = 0;
  int _totalMatches = 0;

  // ── Verse selection ───────────────────────────────────────────────────────
  final Set<int> _selectedVerseNumbers = {};

  // ── Current verses cache (needed for search + share) ─────────────────────
  List<BibleSearchResult> _currentVerses = [];
  String? _lastChapterSignature;
  String? _pendingSearchRecalcSignature;
  String? _pendingVerseJumpSignature;

  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ── Navigation handler (shared by AppBar title + FAB) ─────────────────────

  Future<void> _openQuickNav() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const QuickNavigationSheet(),
    );
    _handleNavResult(result);
  }

  void _handleNavResult(Map<String, dynamic>? result) {
    if (result == null) return;
    final verse = result['verse'] as int?;
    final newTab = ReaderTab(
      type: ReaderContentType.bible,
      title: "${result['book']} ${result['chapter']}",
      book: result['book'] as String,
      chapter: result['chapter'] as int,
      verse: verse,
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
      _isSearching = false;
      _searchController.clear();
      _clearMatches();
    });
  }

  // ── In-page search helpers ─────────────────────────────────────────────────

  void _computeMatches(String query) {
    if (query.isEmpty || _currentVerses.isEmpty) {
      setState(() {
        _matchVerseIndices = [];
        _totalMatches = 0;
        _currentMatchIndex = 0;
      });
      return;
    }

    final pattern = RegExp(query, caseSensitive: false);
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

    if (indices.isNotEmpty) {
      _scrollToCurrentMatch();
    }
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
    final activeTab = ref.read(readerProvider).activeTab;
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

  void _copySelectedVerses() {
    if (_selectedVerseNumbers.isEmpty || _currentVerses.isEmpty) return;
    final activeTab = ref.read(readerProvider).activeTab;
    final sorted = _selectedVerseNumbers.toList()..sort();
    final lines = sorted.map((vNum) {
      final verse = _currentVerses.firstWhere(
        (v) => v.verse == vNum,
        orElse: () => _currentVerses.first,
      );
      return '${activeTab?.book ?? verse.book} ${verse.chapter}:${verse.verse}  ${verse.text}';
    });
    final text = lines.join('\n\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
    );
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
    final lang = ref.read(selectedBibleLangProvider);

    // Use Tamil-specific fonts if needed, otherwise fallback to standard Noto Sans.
    final bodyFont = lang == 'ta'
        ? await PdfGoogleFonts.notoSansTamilRegular()
        : await PdfGoogleFonts.notoSansRegular();
    final boldFont = lang == 'ta'
        ? await PdfGoogleFonts.notoSansTamilBold()
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
            final rawText = v.text.replaceAll(
              RegExp(
                r'[^\x20-\x7E\u0B80-\u0BFF\u2013-\u2014\u2018-\u201D\u2026\n ]',
              ),
              '',
            );

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
                    lineSpacing: (typography.lineHeight - 1) *
                        typography.fontSize *
                        0.5,
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
    final cleaned =
        raw.replaceAll(RegExp(r'[<>:"/\\\\|?*]'), '-').trim();
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

    final savedPath = await DesktopFileSaver.savePdf(
      suggestedName: '$safeTitle.pdf',
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

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final readerState = ref.watch(readerProvider);
    final typographyState = ref.watch(typographyProvider);
    final activeTab = readerState.activeTab;
    final isFullscreen = typographyState.isFullscreen;

    return Scaffold(
      appBar: isFullscreen
          ? null
          : (_isSearching
                ? _buildSearchAppBar(context)
                : _buildDefaultAppBar(context, activeTab)),
      body: activeTab == null
          ? const Center(child: Text('No open tabs. Please open a book.'))
          : isFullscreen
          ? Stack(
              children: [
                _buildTabContent(activeTab, typographyState),
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
          : _buildTabContent(activeTab, typographyState),
      // FAB opens Quick Navigation sheet.
      floatingActionButton: (activeTab == null || isFullscreen)
          ? null
          : FloatingActionButton(
              onPressed: _openQuickNav,
              child: const Icon(Icons.menu_book_rounded),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: (!isFullscreen && readerState.tabs.isNotEmpty)
          ? _buildBottomTabBar(context, readerState, ref)
          : null,
    );
  }

  // ── App bars ──────────────────────────────────────────────────────────────

  AppBar _buildSearchAppBar(BuildContext context) {
    final counterText = _totalMatches > 0
        ? '${_currentMatchIndex + 1}/$_totalMatches'
        : '0/0';

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () {
          setState(() {
            _isSearching = false;
            _searchController.clear();
            _clearMatches();
          });
        },
      ),
      title: TextField(
        controller: _searchController,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'Search in chapter...',
          border: InputBorder.none,
        ),
        onChanged: (val) => _computeMatches(val),
      ),
      actions: [
        if (_searchController.text.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              _searchController.clear();
              _computeMatches('');
            },
          ),
        // Match counter
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              counterText,
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
    );
  }

  AppBar _buildDefaultAppBar(BuildContext context, ReaderTab? activeTab) {
    final hasSelection = _selectedVerseNumbers.isNotEmpty;

    return AppBar(
      title: InkWell(
        onTap: _openQuickNav,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(activeTab?.title ?? 'Reader'),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
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
            onPressed: () => setState(() => _selectedVerseNumbers.clear()),
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
            if (tab.verse != null && verses.isNotEmpty) {
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

          return SelectionArea(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              itemCount: verses.length,
              itemBuilder: (context, index) {
                final verse = verses[index];
                final isSelected = _selectedVerseNumbers.contains(verse.verse);

                // Compute which occurrence within this verse is the current match.
                int? currentOccurrence;
                if (_matchVerseIndices.isNotEmpty &&
                    _matchVerseIndices[_currentMatchIndex] == index) {
                  currentOccurrence =
                      _currentMatchIndex -
                      _matchVerseIndices
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
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      );
    }

    return Center(child: Text('Unsupported content for ${tab.title}'));
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
                      final lang = ref.read(selectedBibleLangProvider);
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
                          const SnackBar(content: Text('Link copied to clipboard')),
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
