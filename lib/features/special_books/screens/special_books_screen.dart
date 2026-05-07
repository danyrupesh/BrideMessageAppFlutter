import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/models/special_book_models.dart';
import '../../../core/database/special_books_catalog_repository.dart';
import '../../common/widgets/section_menu_button.dart';
import '../../settings/widgets/theme_picker_sheet.dart';
import '../providers/special_book_catalog_provider.dart';
import '../providers/special_book_download_provider.dart';

class SpecialBooksScreen extends ConsumerStatefulWidget {
  const SpecialBooksScreen({super.key, required this.lang});

  final String lang;

  @override
  ConsumerState<SpecialBooksScreen> createState() => _SpecialBooksScreenState();
}

class _SpecialBooksScreenState extends ConsumerState<SpecialBooksScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  bool _searchInContent = false;
  Future<Map<String, String>>? _contentFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(specialBooksCatalogAvailableProvider(widget.lang));
      ref.invalidate(specialBooksListProvider(widget.lang));
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    final q = value.trim();
    setState(() {
      _query = q;
      if (_searchInContent && q.isNotEmpty) {
        _contentFuture = SpecialBooksCatalogRepository(lang: widget.lang)
            .searchBooksWithSnippets(q);
      } else {
        _contentFuture = null;
      }
    });
  }

  void _onModeChanged(bool inContent) {
    setState(() {
      _searchInContent = inContent;
      if (inContent && _query.isNotEmpty) {
        _contentFuture = SpecialBooksCatalogRepository(lang: widget.lang)
            .searchBooksWithSnippets(_query);
      } else {
        _contentFuture = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final catalogAvail = ref.watch(
      specialBooksCatalogAvailableProvider(widget.lang),
    );
    final booksAsync = ref.watch(specialBooksListProvider(widget.lang));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.lang == 'ta' ? 'சிறப்பு புத்தகங்கள்' : 'Special Books',
        ),
        leading: const BackButton(),
        actions: [
          IconButton(
            tooltip: 'Home',
            icon: const Icon(Icons.home_outlined),
            onPressed: () => context.go('/'),
          ),
          IconButton(
            tooltip: 'Theme',
            icon: const Icon(Icons.palette_outlined),
            onPressed: () => ThemePickerSheet.show(context),
          ),
          SectionMenuButton(),
          IconButton(
            tooltip: 'Help',
            icon: const Icon(Icons.help_outline),
            onPressed: () => context.push('/search-help'),
          ),
        ],
      ),
      body: catalogAvail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorState(message: e.toString()),
        data: (available) {
          if (!available) return const SizedBox.shrink();
          return booksAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _ErrorState(message: e.toString()),
            data: (books) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: widget.lang == 'ta'
                          ? 'புத்தகங்களைத் தேடுங்கள்...'
                          : 'Search books...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchController.clear();
                                _onQueryChanged('');
                              },
                              icon: const Icon(Icons.clear),
                            ),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: _onQueryChanged,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: Text(
                            widget.lang == 'ta' ? 'தலைப்பு' : 'Title',
                          ),
                          selected: !_searchInContent,
                          onSelected: (_) => _onModeChanged(false),
                        ),
                        ChoiceChip(
                          label: Text(
                            widget.lang == 'ta' ? 'உள்ளடக்கம்' : 'Content',
                          ),
                          selected: _searchInContent,
                          onSelected: (_) => _onModeChanged(true),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(child: _buildBookBody(books)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBookBody(List<SpecialBook> books) {
    // ── Content search ──────────────────────────────────────────────────────
    if (_searchInContent && _query.isNotEmpty) {
      return FutureBuilder<Map<String, String>>(
        future: _contentFuture,
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final snippets = snap.data ?? {};
          final matched =
              books.where((b) => snippets.containsKey(b.id)).toList();
          if (matched.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  widget.lang == 'ta'
                      ? 'உள்ளடக்கத்தில் பொருந்தும் புத்தகங்கள் இல்லை.'
                      : 'No books match your content search.',
                  style: const TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          // Content search always uses list view (to show snippets)
          return _BookList(
            books: matched,
            lang: widget.lang,
            query: _query,
            snippets: snippets,
            contentSearchQuery: _query,
          );
        },
      );
    }

    // ── Title search ────────────────────────────────────────────────────────
    final filtered = _query.isEmpty
        ? books
        : books.where((b) {
            final q = _query.toLowerCase();
            return b.title.toLowerCase().contains(q) ||
                (b.titleEn ?? '').toLowerCase().contains(q) ||
                (b.author ?? '').toLowerCase().contains(q) ||
                (b.description ?? '').toLowerCase().contains(q);
          }).toList(growable: false);

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.auto_stories_outlined,
              size: 56,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              _query.isEmpty
                  ? (widget.lang == 'ta'
                      ? 'புத்தகங்கள் எதுவும் இல்லை.'
                      : 'No books available yet.')
                  : (widget.lang == 'ta'
                      ? 'தேடலுக்கு பொருந்தும் புத்தகங்கள் இல்லை.'
                      : 'No books match your search.'),
              style: const TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return _BookList(books: filtered, lang: widget.lang, query: _query);
  }

}

// ── Navigation helper ─────────────────────────────────────────────────────────

void _navigateToBook(
  BuildContext context,
  SpecialBook book,
  String lang, {
  String? initialQuery,
}) {
  if (book.totalChapters == 1) {
    // Skip detail screen — go straight to the single chapter
    final params = <String, String>{'lang': lang};
    if (initialQuery != null && initialQuery.isNotEmpty) {
      params['q'] = initialQuery;
    }
    context.push(
      Uri(
        path:
            '/special-books/reader/${Uri.encodeComponent(book.id)}/${Uri.encodeComponent('${book.id}_ch_0001')}',
        queryParameters: params,
      ).toString(),
    );
  } else {
    context.push(
      Uri(
        path: '/special-books/detail/${Uri.encodeComponent(book.id)}',
        queryParameters: {'lang': lang},
      ).toString(),
    );
  }
}

// ── Book list ─────────────────────────────────────────────────────────────────

class _BookList extends ConsumerWidget {
  const _BookList({
    required this.books,
    required this.lang,
    this.query = '',
    this.snippets,
    this.contentSearchQuery,
  });

  final List<SpecialBook> books;
  final String lang;
  final String query;
  // If non-null, we're in content-search mode; values are text snippets
  final Map<String, String>? snippets;
  // When set, tapping a book opens the reader with this query pre-searched
  final String? contentSearchQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: books.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final book = books[index];
        final isDownloaded = ref.watch(
          specialBookDownloadStatusProvider(
            SpecialBookKey(bookId: book.id, lang: lang),
          ),
        );

        final snippet = snippets?[book.id];

        return ListTile(
          tileColor: Theme.of(context).colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          leading: SizedBox(
            width: 46,
            height: 60,
            child: book.coverUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      book.coverUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.auto_stories_outlined),
                    ),
                  )
                : const Icon(Icons.auto_stories_outlined),
          ),
          title: _HighlightText(
            text: book.title,
            query: query,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: snippet != null
              ? _HighlightText(
                  text: snippet,
                  query: query,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                )
              : Text(
                  '${book.totalChapters} ch${book.totalChapters == 1 ? '' : 's'}',
                ),
          trailing: Icon(
            (isDownloaded.asData?.value ?? false)
                ? Icons.check_circle
                : Icons.chevron_right,
          ),
          onTap: () => _navigateToBook(
            context,
            book,
            lang,
            initialQuery: contentSearchQuery,
          ),
        );
      },
    );
  }
}

// ── Highlight text widget ─────────────────────────────────────────────────────

class _HighlightText extends StatelessWidget {
  const _HighlightText({
    required this.text,
    required this.query,
    this.style,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final String query;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return Text(text, style: style, maxLines: maxLines, overflow: overflow);
    }
    final cs = Theme.of(context).colorScheme;
    final hlStyle = TextStyle(
      backgroundColor: cs.primaryContainer,
      color: cs.onPrimaryContainer,
      fontWeight: FontWeight.bold,
    );
    final lText = text.toLowerCase();
    final lQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;
    int idx;
    while ((idx = lText.indexOf(lQuery, start)) != -1) {
      if (idx > start) spans.add(TextSpan(text: text.substring(start, idx)));
      spans.add(
        TextSpan(
          text: text.substring(idx, idx + lQuery.length),
          style: hlStyle,
        ),
      );
      start = idx + lQuery.length;
    }
    if (start < text.length) spans.add(TextSpan(text: text.substring(start)));
    return Text.rich(
      TextSpan(children: spans, style: style),
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}

// ── Error state ───────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
