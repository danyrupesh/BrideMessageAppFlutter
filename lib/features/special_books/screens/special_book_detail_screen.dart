import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/models/special_book_models.dart';
import '../../../core/database/special_books_catalog_repository.dart';
import '../../../core/database/special_books_content_repository.dart';
import '../../common/widgets/section_menu_button.dart';
import '../../settings/widgets/theme_picker_sheet.dart';
import '../providers/special_book_catalog_provider.dart';
import '../providers/special_book_download_provider.dart';
import '../widgets/download_progress_widget.dart';

class SpecialBookDetailScreen extends ConsumerStatefulWidget {
  const SpecialBookDetailScreen({
    super.key,
    required this.bookId,
    required this.lang,
  });

  final String bookId;
  final String lang;

  @override
  ConsumerState<SpecialBookDetailScreen> createState() =>
      _SpecialBookDetailScreenState();
}

class _SpecialBookDetailScreenState
    extends ConsumerState<SpecialBookDetailScreen> {
  String _chapterQuery = '';
  bool _searchInContent = false;

  @override
  Widget build(BuildContext context) {
    final key = SpecialBookDetailKey(bookId: widget.bookId, lang: widget.lang);
    final sbKey = SpecialBookKey(bookId: widget.bookId, lang: widget.lang);

    final bookAsync = ref.watch(specialBookDetailProvider(key));
    final chaptersAsync = ref.watch(specialBookChapterTitlesProvider(key));
    final hasCatalogContentAsync = ref.watch(
      specialBookHasCatalogContentProvider(key),
    );
    final isDownloadedAsync = ref.watch(specialBookDownloadStatusProvider(sbKey));
    final downloadState = ref.watch(specialBookDownloadProvider(widget.bookId));

    return Scaffold(
      body: bookAsync.when(
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (e, _) => Scaffold(
          appBar: AppBar(title: const Text('Book')),
          body: Center(
            child: Text(e.toString(),
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error)),
          ),
        ),
        data: (book) {
          if (book == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('Book not found')),
              body: const Center(child: Text('Book not found in catalog.')),
            );
          }

          final isDownloaded = isDownloadedAsync.asData?.value ?? false;
          final hasCatalogContent = hasCatalogContentAsync.asData?.value ?? false;
          final canRead = isDownloaded || hasCatalogContent;

          return _BookDetailBody(
            book: book,
            bookId: widget.bookId,
            lang: widget.lang,
            isDownloaded: isDownloaded,
            hasCatalogContent: hasCatalogContent,
            canRead: canRead,
            chaptersAsync: chaptersAsync,
            chapterQuery: _chapterQuery,
            searchInContent: _searchInContent,
            downloadState: downloadState,
            onChapterQueryChanged: (value) =>
                setState(() => _chapterQuery = value.trim()),
            onSearchModeChanged: (searchInContent) =>
                setState(() => _searchInContent = searchInContent),
            onDownload: () => _startDownload(book),
            onImport: () => _importFromFile(book),
            onDeleteDownload: () => _deleteDownload(),
            onSearch: () => _showSearchDialog(),
            onChapterTap: (chapter) => _openChapter(chapter),
          );
        },
      ),
    );
  }

  void _startDownload(SpecialBook book) {
    final url = book.contentZipUrl;
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Download URL not available. Try importing from file.'),
        ),
      );
      return;
    }
    ref.read(specialBookDownloadProvider(widget.bookId).notifier).downloadBook(
          url: url,
          lang: widget.lang,
          expectedVersion: book.contentVersion,
        );
  }

  Future<void> _importFromFile(SpecialBook book) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      dialogTitle: 'Select book content ZIP',
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;

    ref.read(specialBookDownloadProvider(widget.bookId).notifier).importFromZip(
          filePath: path,
          lang: widget.lang,
          expectedVersion: book.contentVersion,
        );
  }

  Future<void> _deleteDownload() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete downloaded content?'),
        content: const Text(
          'The book list and chapter titles will remain visible, '
          'but you will need to re-download to read the content.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await ref
        .read(specialBookDownloadProvider(widget.bookId).notifier)
        .deleteDownload(widget.lang);
  }

  Future<void> _showSearchDialog() async {
    final catalogRepo = SpecialBooksCatalogRepository(lang: widget.lang);
    final repo = SpecialBooksContentRepository(
      bookId: widget.bookId,
      lang: widget.lang,
    );
    final controller = TextEditingController();
    var loading = false;
    List<BookChapterContent> results = const [];
    bool hasSearched = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            Future<void> runSearch() async {
              final q = controller.text.trim();
              hasSearched = true;
              if (q.isEmpty) {
                setStateDialog(() {
                  loading = false;
                  results = const [];
                });
                return;
              }
              setStateDialog(() => loading = true);
              final catalogFound = await catalogRepo.searchChapters(
                widget.bookId,
                q,
              );
              final localFound = await repo.searchChapters(q);
              final merged = <String, BookChapterContent>{
                for (final item in catalogFound) item.id: item,
                for (final item in localFound) item.id: item,
              };
              if (!context.mounted) return;
              setStateDialog(() {
                results = merged.values.toList(growable: false);
                loading = false;
              });
            }

            return AlertDialog(
              title: const Text('Search in this book'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Search chapter text...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.send),
                          onPressed: runSearch,
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => runSearch(),
                    ),
                    const SizedBox(height: 12),
                    if (loading)
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: CircularProgressIndicator(),
                      )
                    else if (results.isEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          hasSearched ? 'No matches found.' : 'Enter text and search.',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 360),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: results.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = results[index];
                            final snippet = (item.contentText ?? '')
                                .replaceAll(RegExp(r'\s+'), ' ')
                                .trim();
                            return ListTile(
                              title: Text(item.title),
                              subtitle: Text(
                                snippet.length > 120
                                    ? '${snippet.substring(0, 120)}...'
                                    : snippet,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () {
                                Navigator.of(ctx).pop();
                                context.push(
                                  Uri(
                                    path:
                                        '/special-books/reader/${Uri.encodeComponent(widget.bookId)}/${Uri.encodeComponent(item.id)}',
                                    queryParameters: {'lang': widget.lang},
                                  ).toString(),
                                );
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
  }

  void _openChapter(BookChapterTitle chapter) {
    context.push(
      Uri(
        path: '/special-books/reader/${Uri.encodeComponent(widget.bookId)}/${Uri.encodeComponent(chapter.id)}',
        queryParameters: {'lang': widget.lang},
      ).toString(),
    );
  }
}

// ── Book detail body ──────────────────────────────────────────────────────────

class _BookDetailBody extends StatelessWidget {
  const _BookDetailBody({
    required this.book,
    required this.bookId,
    required this.lang,
    required this.isDownloaded,
    required this.hasCatalogContent,
    required this.canRead,
    required this.chaptersAsync,
    required this.chapterQuery,
    required this.searchInContent,
    required this.downloadState,
    required this.onChapterQueryChanged,
    required this.onSearchModeChanged,
    required this.onDownload,
    required this.onImport,
    required this.onDeleteDownload,
    required this.onSearch,
    required this.onChapterTap,
  });

  final SpecialBook book;
  final String bookId;
  final String lang;
  final bool isDownloaded;
  final bool hasCatalogContent;
  final bool canRead;
  final AsyncValue<List<BookChapterTitle>> chaptersAsync;
  final String chapterQuery;
  final bool searchInContent;
  final BookDownloadState downloadState;
  final ValueChanged<String> onChapterQueryChanged;
  final ValueChanged<bool> onSearchModeChanged;
  final VoidCallback onDownload;
  final VoidCallback onImport;
  final VoidCallback onDeleteDownload;
  final VoidCallback onSearch;
  final void Function(BookChapterTitle) onChapterTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(book.title, overflow: TextOverflow.ellipsis),
        leading: const BackButton(),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Home',
            onPressed: () => context.go('/'),
          ),
          IconButton(
            icon: const Icon(Icons.palette_outlined),
            tooltip: 'Theme',
            onPressed: () => ThemePickerSheet.show(context),
          ),
          SectionMenuButton(),
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Help',
            onPressed: () => context.push('/search-help'),
          ),
          if (canRead)
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Search in book',
              onPressed: onSearch,
            ),
          if (isDownloaded)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Delete downloaded content',
              onPressed: onDeleteDownload,
            ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // Book header
          SliverToBoxAdapter(
            child: _BookHeader(book: book, lang: lang),
          ),

          // Download progress / buttons
          if (downloadState.isActive || downloadState.hasError)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: DownloadProgressWidget(state: downloadState),
              ),
            )
          else if (!canRead)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: _DownloadButtons(
                  book: book,
                  onDownload: onDownload,
                  onImport: onImport,
                ),
              ),
            )
          else
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: cs.primary, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      hasCatalogContent
                          ? 'Content available in catalog'
                          : 'Content downloaded',
                      style: TextStyle(color: cs.primary, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),

          // Chapter list divider
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'CHAPTERS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: Colors.grey,
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Search title / content...',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: chapterQuery.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => onChapterQueryChanged(''),
                            ),
                    ),
                    onChanged: onChapterQueryChanged,
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Title'),
                          selected: !searchInContent,
                          onSelected: (_) => onSearchModeChanged(false),
                        ),
                        ChoiceChip(
                          label: const Text('Content'),
                          selected: searchInContent,
                          onSelected: (_) => onSearchModeChanged(true),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Chapter titles
          chaptersAsync.when(
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => SliverFillRemaining(
              child: Center(child: Text(e.toString())),
            ),
            data: (chapters) {
              if (chapters.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(
                    child: Text(
                      'No chapters available.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                );
              }
              final q = chapterQuery.trim().toLowerCase();
              if (q.isEmpty) {
                return _buildChapterList(
                  context: context,
                  chapters: chapters,
                  canRead: canRead,
                  colorScheme: cs,
                  onChapterTap: onChapterTap,
                );
              }
              if (!searchInContent) {
                final filtered = chapters
                    .where((c) => c.title.toLowerCase().contains(q))
                    .toList(growable: false);
                return _buildChapterList(
                  context: context,
                  chapters: filtered,
                  canRead: canRead,
                  colorScheme: cs,
                  onChapterTap: onChapterTap,
                );
              }

              return SliverToBoxAdapter(
                child: FutureBuilder<List<BookChapterContent>>(
                  future: _searchContentMatches(lang, bookId, q),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final ids = (snapshot.data ?? const <BookChapterContent>[])
                        .map((e) => e.id)
                        .toSet();
                    final filtered = chapters
                        .where((c) => ids.contains(c.id))
                        .toList(growable: false);
                    if (filtered.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            'No chapters match your content search.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const Divider(height: 1, indent: 56),
                      itemBuilder: (context, index) => _buildChapterTile(
                        context: context,
                        chapter: filtered[index],
                        index: index,
                        canRead: canRead,
                        colorScheme: cs,
                        onChapterTap: onChapterTap,
                      ),
                    );
                  },
                ),
              );
            },
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

Future<List<BookChapterContent>> _searchContentMatches(
  String lang,
  String bookId,
  String query,
) async {
  final catalogRepo = SpecialBooksCatalogRepository(lang: lang);
  final contentRepo = SpecialBooksContentRepository(bookId: bookId, lang: lang);
  final a = await catalogRepo.searchChapters(bookId, query, limit: 250);
  final b = await contentRepo.searchChapters(query);
  final merged = <String, BookChapterContent>{
    for (final item in a) item.id: item,
    for (final item in b) item.id: item,
  };
  return merged.values.toList(growable: false);
}

Widget _buildChapterList({
  required BuildContext context,
  required List<BookChapterTitle> chapters,
  required bool canRead,
  required ColorScheme colorScheme,
  required void Function(BookChapterTitle) onChapterTap,
}) {
  if (chapters.isEmpty) {
    return const SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text(
            'No chapters match your search.',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      ),
    );
  }
  return SliverList.separated(
    itemCount: chapters.length,
    separatorBuilder: (_, _) => const Divider(height: 1, indent: 56),
    itemBuilder: (context, index) => _buildChapterTile(
      context: context,
      chapter: chapters[index],
      index: index,
      canRead: canRead,
      colorScheme: colorScheme,
      onChapterTap: onChapterTap,
    ),
  );
}

Widget _buildChapterTile({
  required BuildContext context,
  required BookChapterTitle chapter,
  required int index,
  required bool canRead,
  required ColorScheme colorScheme,
  required void Function(BookChapterTitle) onChapterTap,
}) {
  return ListTile(
    leading: CircleAvatar(
      radius: 16,
      backgroundColor: colorScheme.primaryContainer,
      child: Text(
        '${index + 1}',
        style: TextStyle(
          fontSize: 12,
          color: colorScheme.onPrimaryContainer,
        ),
      ),
    ),
    title: Text(chapter.title),
    trailing: canRead
        ? const Icon(Icons.chevron_right)
        : Icon(
            Icons.lock_outline,
            size: 16,
            color: colorScheme.outline,
          ),
    onTap: canRead ? () => onChapterTap(chapter) : null,
    enabled: canRead,
  );
}

// ── Book header ───────────────────────────────────────────────────────────────

class _BookHeader extends StatelessWidget {
  const _BookHeader({required this.book, required this.lang});

  final SpecialBook book;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: book.coverUrl != null
                ? Image.network(
                    book.coverUrl!,
                    width: 90,
                    height: 130,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => _PlaceholderCover(
                      size: const Size(90, 130),
                    ),
                  )
                : _PlaceholderCover(size: const Size(90, 130)),
          ),
          const SizedBox(width: 16),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                if (book.titleEn != null && book.titleEn!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    book.titleEn!,
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
                if (book.author != null && book.author!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.person_outline, size: 14, color: cs.outline),
                      const SizedBox(width: 4),
                      Text(
                        book.author!,
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.list_alt, size: 14, color: cs.outline),
                    const SizedBox(width: 4),
                    Text(
                      '${book.totalChapters} chapter${book.totalChapters == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: cs.secondaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        lang.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: cs.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                if (book.description != null &&
                    book.description!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    book.description!,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceholderCover extends StatelessWidget {
  const _PlaceholderCover({required this.size});

  final Size size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.auto_stories, size: 36, color: cs.outline),
    );
  }
}

// ── Download buttons ──────────────────────────────────────────────────────────

class _DownloadButtons extends StatelessWidget {
  const _DownloadButtons({
    required this.book,
    required this.onDownload,
    required this.onImport,
  });

  final SpecialBook book;
  final VoidCallback onDownload;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Download content to read chapters',
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          if (book.contentZipSize != null) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 22),
              child: Text(
                'Size: ${_formatSize(book.contentZipSize!)}',
                style: TextStyle(fontSize: 11, color: cs.outline),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (book.contentZipUrl != null && book.contentZipUrl!.isNotEmpty)
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onDownload,
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Download'),
                  ),
                ),
              if (book.contentZipUrl != null &&
                  book.contentZipUrl!.isNotEmpty)
                const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onImport,
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  label: const Text('Import ZIP'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
