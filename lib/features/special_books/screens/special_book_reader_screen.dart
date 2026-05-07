import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/database/models/special_book_models.dart';
import '../../../core/database/special_books_catalog_repository.dart';
import '../../../core/database/special_books_content_repository.dart';
import '../../common/widgets/section_menu_button.dart';
import '../../settings/widgets/theme_picker_sheet.dart';
import '../widgets/image_viewer_widget.dart';

class SpecialBookReaderScreen extends ConsumerStatefulWidget {
  const SpecialBookReaderScreen({
    super.key,
    required this.bookId,
    required this.chapterId,
    required this.lang,
    this.initialSearchQuery = '',
  });

  final String bookId;
  final String chapterId;
  final String lang;
  final String initialSearchQuery;

  @override
  ConsumerState<SpecialBookReaderScreen> createState() =>
      _SpecialBookReaderScreenState();
}

class _SpecialBookReaderScreenState
    extends ConsumerState<SpecialBookReaderScreen> {
  BookChapterContent? _chapter;
  bool _loading = true;
  String? _error;
  double _fontSize = 16.0;

  // ── In-passage search ──────────────────────────────────────────────────────
  bool _showSearch = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _searchFocusNode = FocusNode();

  /// Character offsets in contentText where matches start.
  List<int> _matchOffsets = [];
  int _currentMatchIdx = -1;

  @override
  void initState() {
    super.initState();
    _loadChapter();
  }

  /// Called after content is loaded if an [initialSearchQuery] was provided.
  void _applyInitialSearchQuery() {
    final q = widget.initialSearchQuery.trim();
    if (q.isEmpty) return;
    _searchController.text = q;
    final offsets = _computeMatchOffsets(q);
    setState(() {
      _showSearch = true;
      _searchQuery = q;
      _matchOffsets = offsets;
      _currentMatchIdx = offsets.isNotEmpty ? 0 : -1;
    });
    if (offsets.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToMatchIndex(0));
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // ── Content loading ────────────────────────────────────────────────────────

  Future<void> _loadChapter() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final catalogRepo = SpecialBooksCatalogRepository(lang: widget.lang);
      final catalogChapter =
          await catalogRepo.getChapterContent(widget.chapterId);
      if (!mounted) return;
      if (catalogChapter != null) {
        setState(() {
          _chapter = catalogChapter;
          _loading = false;
        });
        _applyInitialSearchQuery();
        return;
      }

      final repo = SpecialBooksContentRepository(
        bookId: widget.bookId,
        lang: widget.lang,
      );
      final chapter = await repo.getChapter(widget.chapterId);
      if (!mounted) return;
      if (chapter == null) {
        setState(() {
          _loading = false;
          _error = 'Content not available - please download the book content.';
        });
        return;
      }
      setState(() {
        _chapter = chapter;
        _loading = false;
      });
      _applyInitialSearchQuery();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load chapter: $e';
      });
    }
  }

  // ── Clipboard ──────────────────────────────────────────────────────────────

  void _copyText() {
    final text = _chapter?.contentText ?? _chapter?.title ?? '';
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Text copied to clipboard')),
    );
  }

  Future<void> _downloadCurrentDocx() async {
    final chapter = _chapter;
    if (chapter == null) return;
    List<int> docxBytes;
    // Prefer exact original DOCX from DB (preserves all formatting/images).
    final originalB64 = chapter.sourceDocxB64;
    if (originalB64 != null && originalB64.isNotEmpty) {
      docxBytes = base64Decode(originalB64);
    } else {
      final content = (chapter.contentText ?? '').trim();
      if (content.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No content available to export.')),
        );
        return;
      }
      docxBytes = _buildDocxBytes(
        title: chapter.title,
        bodyText: content,
      );
    }

    final fileSafeTitle = _safeFileName(chapter.title);
    final outDir = await _getSaveDirectory();
    final file = File(
      '${outDir.path}${Platform.pathSeparator}$fileSafeTitle.docx',
    );
    await file.writeAsBytes(docxBytes, flush: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('DOCX saved: ${file.path}')),
    );
  }

  Future<Directory> _getSaveDirectory() async {
    try {
      final dir = await getDownloadsDirectory();
      if (dir != null) return dir;
    } catch (_) {}
    return getApplicationDocumentsDirectory();
  }

  List<int> _buildDocxBytes({
    required String title,
    required String bodyText,
  }) {
    final archive = Archive();
    archive.addFile(
      ArchiveFile(
        '[Content_Types].xml',
        _contentTypesXml.length,
        utf8.encode(_contentTypesXml),
      ),
    );
    archive.addFile(
      ArchiveFile(
        '_rels/.rels',
        _relsXml.length,
        utf8.encode(_relsXml),
      ),
    );
    final documentXml = _wordDocumentXml(
      title: title,
      bodyText: bodyText,
    );
    archive.addFile(
      ArchiveFile(
        'word/document.xml',
        documentXml.length,
        utf8.encode(documentXml),
      ),
    );
    return ZipEncoder().encode(archive);
  }

  String _wordDocumentXml({
    required String title,
    required String bodyText,
  }) {
    final lines = bodyText.split(RegExp(r'\r?\n')).where((e) => e.isNotEmpty);
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..writeln(
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">',
      )
      ..writeln('<w:body>');

    buffer.writeln(
      '<w:p><w:r><w:rPr><w:b/></w:rPr><w:t>${_escapeXml(title)}</w:t></w:r></w:p>',
    );
    for (final line in lines) {
      buffer.writeln(
        '<w:p><w:r><w:t xml:space="preserve">${_escapeXml(line)}</w:t></w:r></w:p>',
      );
    }
    buffer
      ..writeln(
        '<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>',
      )
      ..writeln('</w:body></w:document>');
    return buffer.toString();
  }

  String _safeFileName(String input) => input
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  String _escapeXml(String input) => input
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  // ── Search helpers ─────────────────────────────────────────────────────────

  void _toggleSearch() {
    setState(() {
      _showSearch = !_showSearch;
      if (!_showSearch) {
        _searchController.clear();
        _searchQuery = '';
        _matchOffsets = [];
        _currentMatchIdx = -1;
        _searchFocusNode.unfocus();
      }
    });
  }

  void _onSearchChanged(String value) {
    final q = value.trim();
    final offsets = _computeMatchOffsets(q);
    final idx = offsets.isNotEmpty ? 0 : -1;
    setState(() {
      _searchQuery = q;
      _matchOffsets = offsets;
      _currentMatchIdx = idx;
    });
    if (idx >= 0) _scrollToMatchIndex(idx);
  }

  List<int> _computeMatchOffsets(String query) {
    if (query.isEmpty || _chapter == null) return [];
    final text = _chapter!.contentText ?? '';
    if (text.isEmpty) return [];
    final lText = text.toLowerCase();
    final lQuery = query.toLowerCase();
    final offsets = <int>[];
    int start = 0;
    int idx;
    while ((idx = lText.indexOf(lQuery, start)) != -1) {
      offsets.add(idx);
      start = idx + 1;
    }
    return offsets;
  }

  void _goToNextMatch() {
    if (_matchOffsets.isEmpty) return;
    final next = (_currentMatchIdx + 1) % _matchOffsets.length;
    setState(() => _currentMatchIdx = next);
    _scrollToMatchIndex(next);
    // Keep focus on the search field so Enter can keep navigating.
    _searchFocusNode.requestFocus();
  }

  void _goToPreviousMatch() {
    if (_matchOffsets.isEmpty) return;
    final prev =
        (_currentMatchIdx - 1 + _matchOffsets.length) % _matchOffsets.length;
    setState(() => _currentMatchIdx = prev);
    _scrollToMatchIndex(prev);
    _searchFocusNode.requestFocus();
  }

  /// Estimates scroll offset for match [idx] using the proportion of the
  /// match's character offset relative to the total plain-text length.
  void _scrollToMatchIndex(int idx) {
    if (_matchOffsets.isEmpty || idx < 0 || idx >= _matchOffsets.length) {
      return;
    }
    final totalLen = (_chapter?.contentText ?? '').length;
    if (totalLen == 0) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final maxExtent = _scrollController.position.maxScrollExtent;
      if (maxExtent <= 0) return;
      final ratio = _matchOffsets[idx] / totalLen;
      final target = (maxExtent * ratio).clamp(0.0, maxExtent);
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Chapter'),
          leading: const BackButton(),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 56, color: cs.outline),
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final chapter = _chapter!;

    return PopScope(
      // When search is open, intercept back to close the search bar first.
      canPop: !_showSearch,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _showSearch) _toggleSearch();
      },
      child: Scaffold(
        body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverAppBar(
            pinned: true,
            leading: BackButton(
              onPressed: () {
                if (_showSearch) {
                  _toggleSearch();
                } else {
                  context.pop();
                }
              },
            ),
            title: Text(chapter.title, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                icon: Icon(
                  _showSearch ? Icons.search_off : Icons.search,
                ),
                tooltip:
                    _showSearch ? 'Close search' : 'Search in passage',
                onPressed: _toggleSearch,
              ),
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
              IconButton(
                icon: const Icon(Icons.copy_outlined),
                tooltip: 'Copy text',
                onPressed: _copyText,
              ),
              IconButton(
                icon: const Icon(Icons.download_outlined),
                tooltip: 'Download current DOCX',
                onPressed: _downloadCurrentDocx,
              ),
              IconButton(
                icon: const Icon(Icons.text_decrease),
                tooltip: 'Decrease font',
                onPressed: () =>
                    setState(() => _fontSize = (_fontSize - 1).clamp(12, 28)),
              ),
              IconButton(
                icon: const Icon(Icons.text_increase),
                tooltip: 'Increase font',
                onPressed: () =>
                    setState(() => _fontSize = (_fontSize + 1).clamp(12, 28)),
              ),
            ],
            bottom: _showSearch
                ? PreferredSize(
                    preferredSize: const Size.fromHeight(56),
                    child: _SearchBar(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      matchCount: _matchOffsets.length,
                      currentMatchIdx: _currentMatchIdx,
                      lang: widget.lang,
                      onChanged: _onSearchChanged,
                      onClear: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                      onNext: _goToNextMatch,
                      onPrevious: _goToPreviousMatch,
                      onSubmitted: (_) => _goToNextMatch(),
                    ),
                  )
                : null,
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              child: _HtmlContent(
                html: chapter.contentHtml ?? '<p>${chapter.title}</p>',
                fontSize: _fontSize,
                lang: widget.lang,
                highlightQuery: _searchQuery,
                activeMatchIdx: _currentMatchIdx,
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

// ── Search bar widget ─────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.matchCount,
    required this.currentMatchIdx,
    required this.lang,
    required this.onChanged,
    required this.onClear,
    required this.onNext,
    required this.onPrevious,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int matchCount;
  final int currentMatchIdx;
  final String lang;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasQuery = controller.text.trim().isNotEmpty;
    final hasMatches = matchCount > 0;

    final counterText = hasQuery
        ? (hasMatches
            ? '${currentMatchIdx + 1} / $matchCount'
            : '0 matches')
        : '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              textInputAction: TextInputAction.search,
              // Prevent default submit behaviour from stealing focus.
              onEditingComplete: () {},
              decoration: InputDecoration(
                hintText: lang == 'ta'
                    ? 'இங்கே தேடுங்கள்...'
                    : 'Search in passage...',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: hasQuery
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: onClear,
                      )
                    : null,
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 12,
                ),
                filled: true,
                fillColor: cs.surfaceContainerLow,
              ),
              onChanged: onChanged,
              onSubmitted: onSubmitted,
            ),
          ),
          if (hasQuery) ...[
            const SizedBox(width: 6),
            Text(
              counterText,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: hasMatches ? cs.primary : cs.outline,
              ),
            ),
            // ↑ Previous
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up),
              iconSize: 22,
              tooltip: 'Previous match',
              onPressed: hasMatches ? onPrevious : null,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            // ↓ Next
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down),
              iconSize: 22,
              tooltip: 'Next match',
              onPressed: hasMatches ? onNext : null,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ],
      ),
    );
  }
}

// ── HTML content renderer ─────────────────────────────────────────────────────

class _HtmlContent extends StatelessWidget {
  const _HtmlContent({
    required this.html,
    required this.fontSize,
    required this.lang,
    this.highlightQuery = '',
    this.activeMatchIdx = -1,
  });

  final String html;
  final double fontSize;
  final String lang;
  final String highlightQuery;
  /// Index of the currently active match (shown in bright yellow).
  /// All other matches are shown in pale yellow.
  final int activeMatchIdx;

  static const _markCss =
      '<style>'
      'mark{background-color:#FFF9C4!important;color:#1a1a1a!important;'
      'border-radius:2px;padding:0 2px;}'
      'mark.active{background-color:#FFD600!important;color:#000!important;'
      'outline:2px solid #F57F17;border-radius:2px;padding:0 2px;}'
      '</style>';

  String _applyHighlight(String source, String query, int activeIdx) {
    if (query.isEmpty) return source;
    int matchCount = 0;
    final highlighted = source.replaceAllMapped(
      RegExp(RegExp.escape(query), caseSensitive: false),
      (m) {
        final isActive = matchCount == activeIdx;
        matchCount++;
        final cls = isActive ? ' class="active"' : '';
        return '<mark$cls>${m.group(0)}</mark>';
      },
    );
    return '$_markCss$highlighted';
  }

  List<String> _chunkHtml(String source) {
    if (source.length < 120000) return [source];
    final parts = <String>[];
    final tokens = source.split(
      RegExp(
        r'</p>|</h1>|</h2>|</h3>|</h4>|<br\s*/?>',
        caseSensitive: false,
      ),
    );
    final buffer = StringBuffer();
    for (final token in tokens) {
      if (token.trim().isEmpty) continue;
      if (buffer.length + token.length > 40000 && buffer.isNotEmpty) {
        parts.add(buffer.toString());
        buffer.clear();
      }
      buffer.write(token);
      buffer.write('<br/>');
    }
    if (buffer.isNotEmpty) parts.add(buffer.toString());
    return parts.isEmpty ? [source] : parts;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isTamil = lang == 'ta';

    final processedHtml = _applyHighlight(html, highlightQuery, activeMatchIdx);
    final chunks = _chunkHtml(processedHtml);

    Widget buildWidget(String chunk) => HtmlWidget(
          chunk,
          textStyle: TextStyle(
            fontSize: fontSize,
            height: 1.75,
            color: cs.onSurface,
            fontFamily: isTamil ? 'NotoSerifTamil' : null,
          ),
          customStylesBuilder: (element) {
            switch (element.localName) {
              case 'h1':
              case 'h2':
              case 'h3':
              case 'h4':
                return {
                  'color': _colorHex(cs.primary),
                  'font-weight': 'bold',
                  'margin-top': '20px',
                  'margin-bottom': '8px',
                  'line-height': '1.4',
                };
              case 'p':
                return {
                  'margin-bottom': '12px',
                  'line-height': '1.75',
                };
              case 'blockquote':
                return {
                  'border-left': '4px solid ${_colorHex(cs.primary)}',
                  'padding-left': '16px',
                  'margin': '12px 0',
                  'color': _colorHex(cs.onSurfaceVariant),
                  'font-style': 'italic',
                };
              case 'img':
                return {
                  'max-width': '100%',
                  'display': 'block',
                  'margin': '16px auto',
                  'border-radius': '8px',
                };
              case 'strong':
              case 'b':
                return {'font-weight': 'bold'};
              case 'a':
                return {'color': _colorHex(cs.primary)};
              default:
                return null;
            }
          },
          onTapImage: (imageMetadata) {
            final src = imageMetadata.sources.firstOrNull?.url ?? '';
            if (src.isNotEmpty) {
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(
                  builder: (_) => ImageViewerWidget(imageUrl: src),
                  fullscreenDialog: true,
                ),
              );
            }
          },
        );

    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final chunk in chunks) buildWidget(chunk)],
      ),
    );
  }
}

String _colorHex(Color c) {
  final r = (c.r * 255).round().toRadixString(16).padLeft(2, '0');
  final g = (c.g * 255).round().toRadixString(16).padLeft(2, '0');
  final b = (c.b * 255).round().toRadixString(16).padLeft(2, '0');
  return '#$r$g$b';
}

const String _contentTypesXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>
''';

const String _relsXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>
''';
