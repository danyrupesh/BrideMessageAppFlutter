import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/reader_provider.dart';

// 12-color pastel palette cycled by book_index for visual variety.
const _kBookColors = [
  0xFFFCE6C9,
  0xFFFDECD9,
  0xFFFBE4E7,
  0xFFEAF4FB,
  0xFFE9EDF6,
  0xFFEAC4EB,
  0xFFEDB0F5,
  0xFFD8ABB1,
  0xFFD6EAF8,
  0xFFD5F5E3,
  0xFFFFF9C4,
  0xFFFFE0B2,
];

class QuickNavigationSheet extends ConsumerStatefulWidget {
  const QuickNavigationSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const QuickNavigationSheet(),
    );
  }

  @override
  ConsumerState<QuickNavigationSheet> createState() =>
      _QuickNavigationSheetState();
}

class _QuickNavigationSheetState extends ConsumerState<QuickNavigationSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final PageController _pageController = PageController();

  bool _openInNewTab = true;
  Map<String, dynamic>? _selectedBook;
  int? _selectedChapter;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  // ── Navigation helpers ────────────────────────────────────────────────────

  void _onBookSelected(Map<String, dynamic> book) {
    setState(() {
      _selectedBook = book;
      _selectedChapter = null;
    });
    _pageController.animateToPage(
      1,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
    );
  }

  void _onChapterSelected(int chapter) {
    setState(() {
      _selectedChapter = chapter;
    });
    _pageController.animateToPage(
      2,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
    );
  }

  void _onVerseSelected(int verse) {
    Navigator.pop(context, {
      'book': _selectedBook!['name'],
      'chapter': _selectedChapter,
      'verse': verse,
      'newTab': _openInNewTab,
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final maxSheetWidth = screenWidth >= 1200
        ? 980.0
        : screenWidth >= 900
        ? 860.0
        : double.infinity;

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxSheetWidth),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.9,
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              _buildDragHandle(theme),
              _buildHeader(),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildBookSelectionPage(theme),
                    _buildChapterSelectionPage(theme),
                    _buildVerseSelectionPage(theme),
                  ],
                ),
              ),
              _buildBottomAction(theme),
            ],
          ),
        ),
      ),
    );
  }

  int _gridColumnsForWidth({
    required double width,
    required int mobile,
    required int tablet,
    required int desktop,
    required int wideDesktop,
  }) {
    if (width >= 1200) return wideDesktop;
    if (width >= 900) return desktop;
    if (width >= 600) return tablet;
    return mobile;
  }

  Widget _buildBooksGrid(List<Map<String, dynamic>> books, ThemeData theme) {
    if (books.isEmpty) {
      return const Center(child: Text('No books found.'));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = _gridColumnsForWidth(
          width: constraints.maxWidth,
          mobile: 4,
          tablet: 5,
          desktop: 6,
          wideDesktop: 7,
        );
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 1.4,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
          ),
          itemCount: books.length,
          itemBuilder: (context, index) {
            final book = books[index];
            final bookIndex = book['book_index'] as int;
            final colorCode = _kBookColors[bookIndex % _kBookColors.length];
            return _BookTile(
              name: book['book'] as String,
              chapters: book['chapters'] as int,
              colorCode: colorCode,
              onTap: () => _onBookSelected({
                'name': book['book'],
                'chapters': book['chapters'],
                'book_index': bookIndex,
                'color': colorCode,
              }),
            );
          },
        );
      },
    );
  }

  // ── Page 0: Book selection ────────────────────────────────────────────────

  Widget _buildBookSelectionPage(ThemeData theme) {
    final booksAsync = ref.watch(bibleBookListProvider);

    return booksAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text('Could not load books: $e', textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
      data: (allBooks) {
        final query = _searchController.text.toLowerCase();
        final filtered = query.isEmpty
            ? allBooks
            : allBooks
                  .where(
                    (b) => (b['book'] as String).toLowerCase().contains(query),
                  )
                  .toList();

        final otBooks = filtered
            .where((b) => (b['book_index'] as int) <= 39)
            .toList();
        final ntBooks = filtered
            .where((b) => (b['book_index'] as int) > 39)
            .toList();

        return Column(
          children: [
            _buildTabBar(theme),
            _buildSearchBar(theme),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildBooksGrid(otBooks, theme),
                  _buildBooksGrid(ntBooks, theme),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTabBar(ThemeData theme) {
    return TabBar(
      controller: _tabController,
      labelColor: theme.colorScheme.primary,
      unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
      indicatorColor: theme.colorScheme.primary,
      tabs: const [
        Tab(text: 'Old Testament'),
        Tab(text: 'New Testament'),
      ],
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search books',
          prefixIcon: const Icon(Icons.search, size: 20),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 8,
            horizontal: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: theme.colorScheme.outline.withAlpha(128),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: theme.colorScheme.outline.withAlpha(128),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: theme.colorScheme.primary),
          ),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  // ── Page 1: Chapter selection ─────────────────────────────────────────────

  Widget _buildChapterSelectionPage(ThemeData theme) {
    if (_selectedBook == null) return const SizedBox.shrink();

    final bookName = _selectedBook!['name'] as String;
    final totalChapters = _selectedBook!['chapters'] as int;
    final isDark = theme.brightness == Brightness.dark;
    final bookColor = Color(
      _selectedBook!['color'] as int,
    ).withAlpha(isDark ? 77 : 200);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Breadcrumb bar
        _buildBreadcrumb(
          theme: theme,
          bookColor: bookColor,
          bookName: bookName,
          chapter: null,
          onChangeBook: () => _pageController.animateToPage(
            0,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOut,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Text(
            'Select Chapter',
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = _gridColumnsForWidth(
                width: constraints.maxWidth,
                mobile: 6,
                tablet: 7,
                desktop: 9,
                wideDesktop: 10,
              );
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: 1.0,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                ),
                itemCount: totalChapters,
                itemBuilder: (context, index) {
                  final chapterNumber = index + 1;
                  return InkWell(
                    onTap: () => _onChapterSelected(chapterNumber),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withAlpha(160),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$chapterNumber',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: theme.colorScheme.onSurface,
                        ),
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

  // ── Page 2: Verse selection ───────────────────────────────────────────────

  Widget _buildVerseSelectionPage(ThemeData theme) {
    if (_selectedBook == null || _selectedChapter == null) {
      return const SizedBox.shrink();
    }

    final bookName = _selectedBook!['name'] as String;
    final isDark = theme.brightness == Brightness.dark;
    final bookColor = Color(
      _selectedBook!['color'] as int,
    ).withAlpha(isDark ? 77 : 200);

    final verseAsync = ref.watch(
      verseCountProvider((bookName, _selectedChapter!)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Breadcrumb bar
        _buildBreadcrumb(
          theme: theme,
          bookColor: bookColor,
          bookName: bookName,
          chapter: _selectedChapter,
          onChangeBook: () => _pageController.animateToPage(
            0,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOut,
          ),
          onChangeChapter: () => _pageController.animateToPage(
            1,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOut,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Text(
            'Select Verse  (optional — tap to jump directly)',
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: verseAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error loading verses: $e')),
            data: (verseCount) {
              if (verseCount == 0) {
                return const Center(child: Text('No verses found.'));
              }
              return LayoutBuilder(
                builder: (context, constraints) {
                  final crossAxisCount = _gridColumnsForWidth(
                    width: constraints.maxWidth,
                    mobile: 7,
                    tablet: 9,
                    desktop: 11,
                    wideDesktop: 12,
                  );
                  return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      childAspectRatio: 1.0,
                      crossAxisSpacing: 5,
                      mainAxisSpacing: 5,
                    ),
                    itemCount: verseCount,
                    itemBuilder: (context, index) {
                      final verseNumber = index + 1;
                      return InkWell(
                        onTap: () => _onVerseSelected(verseNumber),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withAlpha(160),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '$verseNumber',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Breadcrumb ────────────────────────────────────────────────────────────

  Widget _buildBreadcrumb({
    required ThemeData theme,
    required Color bookColor,
    required String bookName,
    required int? chapter,
    required VoidCallback onChangeBook,
    VoidCallback? onChangeChapter,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bookColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outline.withAlpha(40)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                // Book chip
                GestureDetector(
                  onTap: onChangeBook,
                  child: Text(
                    bookName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (chapter != null) ...[
                  Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  // Chapter chip
                  GestureDetector(
                    onTap: onChangeChapter,
                    child: Text(
                      'Ch $chapter',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: theme.colorScheme.primary,
                        decoration: TextDecoration.underline,
                        decorationColor: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Back link
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: chapter != null ? onChangeChapter : onChangeBook,
            child: Text(
              chapter != null ? 'Ch' : 'Book',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared widgets ────────────────────────────────────────────────────────

  Widget _buildDragHandle(ThemeData theme) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 12, bottom: 8),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: theme.colorScheme.onSurfaceVariant.withAlpha(102),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Quick Navigation',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomAction(ThemeData theme) {
    final canProceed = _selectedBook != null && _selectedChapter != null;
    final btnText = canProceed
        ? 'Go to ${_selectedBook!['name']} $_selectedChapter'
        : 'Go to Chapter';

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(13),
              offset: const Offset(0, -4),
              blurRadius: 8,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Checkbox(
                  value: _openInNewTab,
                  onChanged: (val) =>
                      setState(() => _openInNewTab = val ?? false),
                ),
                const Text('Open in new tab', style: TextStyle(fontSize: 15)),
              ],
            ),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: canProceed
                    ? () => Navigator.pop(context, {
                        'book': _selectedBook!['name'],
                        'chapter': _selectedChapter,
                        'verse': null,
                        'newTab': _openInNewTab,
                      })
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  disabledBackgroundColor: theme.colorScheme.onSurface
                      .withAlpha(31),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                child: Text(
                  btnText,
                  style: TextStyle(
                    color: canProceed
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurface.withAlpha(97),
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Book tile ─────────────────────────────────────────────────────────────────

class _BookTile extends StatelessWidget {
  final String name;
  final int chapters;
  final int colorCode;
  final VoidCallback onTap;

  const _BookTile({
    required this.name,
    required this.chapters,
    required this.colorCode,
    required this.onTap,
  });

  /// 3-char abbreviation used at small tile sizes.
  static String _abbrev(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      // e.g. "1 Samuel" → "1Sa", "Song of Solomon" → "SoS"
      final prefix = parts.first;
      final rest = parts.last;
      if (RegExp(r'^\d').hasMatch(prefix)) {
        return '$prefix${rest.substring(0, rest.length.clamp(0, 2))}';
      }
      return parts.map((p) => p[0]).take(3).join();
    }
    return name.substring(0, name.length.clamp(0, 3));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Color tileColor = Color(colorCode);
    if (isDark) {
      final hsl = HSLColor.fromColor(tileColor);
      tileColor = hsl.withLightness(hsl.lightness * 0.4).toColor();
    }

    final abbrev = _abbrev(name);

    return Material(
      color: tileColor,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                abbrev,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              Text(
                '$chapters ch',
                style: TextStyle(
                  fontSize: 9,
                  color: isDark ? Colors.white60 : Colors.black45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
