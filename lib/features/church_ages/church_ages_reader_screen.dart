import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:messageapp/features/settings/widgets/theme_picker_sheet.dart';
import 'package:messageapp/core/database/models/church_ages_models.dart';
import 'package:messageapp/features/church_ages/providers/church_ages_reader_provider.dart';
import 'package:messageapp/features/church_ages/providers/church_ages_provider.dart';
import 'package:messageapp/features/common/widgets/fts_highlight_text.dart';
import 'package:messageapp/features/reader/providers/typography_provider.dart';
import 'package:messageapp/features/help/widgets/help_sheet.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:convert';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/utils/desktop_file_saver.dart';
import '../../core/services/pdf_export_service.dart';
import '../../core/utils/tamil_normalizer.dart';

class ChurchAgesReaderScreen extends ConsumerStatefulWidget {
  final String? id;
  final String? searchQuery;

  const ChurchAgesReaderScreen({
    super.key,
    this.id,
    this.searchQuery,
  });

  @override
  ConsumerState<ChurchAgesReaderScreen> createState() => _ChurchAgesReaderScreenState();
}

class _ChurchAgesReaderScreenState extends ConsumerState<ChurchAgesReaderScreen> {
  static final PdfExportService _pdfExportService = PdfExportService();
  final ScrollController _contentScrollController = ScrollController();
  final TextEditingController _navSearchController = TextEditingController();
  late final TextEditingController _contentSearchController;
  late final FocusNode _contentSearchFocusNode;

  bool _isSearchingContent = false;
  List<String> _paragraphs = const [];
  List<int> _matchParagraphIndices = const [];
  int _currentMatchIndex = 0;
  final Map<int, GlobalKey> _paragraphKeys = <int, GlobalKey>{};
  String _lastSyncSignature = '';

  @override
  void initState() {
    super.initState();
    _contentSearchController = TextEditingController(text: widget.searchQuery ?? '');
    _contentSearchFocusNode = FocusNode();
    _isSearchingContent = widget.searchQuery != null && widget.searchQuery!.isNotEmpty;
    _syncTopicId();
  }

  @override
  void dispose() {
    _contentScrollController.dispose();
    _navSearchController.dispose();
    _contentSearchController.dispose();
    _contentSearchFocusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ChurchAgesReaderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      _syncTopicId();
    }
  }

  void _syncTopicId() {
    final topicId = int.tryParse(widget.id ?? '');
    if (topicId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final lang = ref.read(activeChurchAgesLangProvider);
        final selectedTopics = ref.read(selectedChurchAgesTopicsProvider);
        if (selectedTopics[lang] != topicId) {
          ref.read(selectedChurchAgesTopicsProvider.notifier).setTopic(lang, topicId);
        }
        // Also clear search when switching topics
        _closeContentSearch();
      });
    }
  }

  void _closeContentSearch() {
    setState(() {
      _isSearchingContent = false;
      _contentSearchController.clear();
      _matchParagraphIndices = const [];
      _currentMatchIndex = 0;
      _lastSyncSignature = '';
    });
  }

  void _syncDocument(String html) {
    final query = _contentSearchController.text.trim();
    final sig = '${html.hashCode}|$query';
    if (sig == _lastSyncSignature) return;
    _lastSyncSignature = sig;

    // Split HTML or plain text by paragraph tags, breaks, or single newlines
    final paragraphs = html
        .split(RegExp(r'<p[^>]*>|<br\s*/?>|</div>|\n', caseSensitive: false))
        .map((p) => p.replaceAll(RegExp(r'<[^>]*>'), '').trim()) // Strip any remaining tags
        .where((p) => p.isNotEmpty)
        .toList();

    final matches = <int>[];
    if (query.isNotEmpty) {
      final pattern = RegExp(RegExp.escape(query), caseSensitive: false);
      for (var i = 0; i < paragraphs.length; i++) {
        final count = pattern.allMatches(paragraphs[i]).length;
        for (var j = 0; j < count; j++) {
          matches.add(i);
        }
      }
    }

    setState(() {
      _paragraphs = paragraphs;
      _matchParagraphIndices = matches;
      _currentMatchIndex = matches.isEmpty
          ? 0
          : _currentMatchIndex.clamp(0, matches.length - 1);
    });

    if (matches.isNotEmpty && query.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToCurrentMatch();
      });
    }
  }

  void _navigateToMatch(int direction) {
    if (_matchParagraphIndices.isEmpty) return;
    setState(() {
      _currentMatchIndex =
          (_currentMatchIndex + direction) % _matchParagraphIndices.length;
      if (_currentMatchIndex < 0) {
        _currentMatchIndex = _matchParagraphIndices.length - 1;
      }
    });
    _scrollToCurrentMatch();
  }

  void _scrollToCurrentMatch() {
    if (_matchParagraphIndices.isEmpty) return;
    final paragraphIndex = _matchParagraphIndices[_currentMatchIndex];
    final ctx = _paragraphKeys[paragraphIndex]?.currentContext;
    if (ctx == null) return;

    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOut,
      alignment: 0.2,
    );
  }

  void _adjustFontSize(String lang, double delta) {
    final current = ref.read(typographyProvider(lang)).fontSize;
    final next = (current + delta).clamp(12.0, 48.0);
    if (lang == 'ta') {
      ref.read(taTypographyProvider.notifier).updateFontSize(next);
    } else {
      ref.read(enTypographyProvider.notifier).updateFontSize(next);
    }
  }

  String _sanitizeFilename(String title) {
    // Replace characters that are invalid on Windows and other OSs
    final cleaned = title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '-').trim();
    return cleaned.isEmpty ? 'Church_Ages' : cleaned;
  }

  Future<void> _downloadTxt(String title, String html) async {
    final text = html.replaceAll(RegExp(r'<[^>]*>'), '');
    final content = '$title\n\n$text';
    final filename = '${_sanitizeFilename(title)}.txt';

    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      final path = await DesktopFileSaver.saveText(
        suggestedName: filename,
        bytes: utf8.encode(content),
      );
      if (path != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to $path')));
      }
    } else {
      await Share.share(content);
    }
  }

  Future<void> _downloadPdf(String title, String html, String lang, TypographySettings typography) async {
    final text = html.replaceAll(RegExp(r'<[^>]*>'), '');
    final payload = <String, dynamic>{
      'type': 'sermon',
      'lang': lang,
      'title': lang == 'ta' ? normalizeTamil(title) : title,
      'settings': <String, dynamic>{
        'fontSize': typography.fontSize,
        'lineHeight': typography.lineHeight,
        'titleFontSize': typography.titleFontSize,
        'fontFamily': typography.resolvedFontFamily ?? '',
      },
      'content': <String, dynamic>{
        'paragraphs': (_paragraphs.isNotEmpty ? _paragraphs : text.split('\n').where((s) => s.trim().isNotEmpty))
            .toList().asMap().entries.map((e) => {
          'paragraphNumber': e.key + 1,
          'text': e.value
        }).toList()
      },
    };
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final bytes = await _pdfExportService.export(payload);
      if (mounted) Navigator.of(context).pop(); // Dismiss loading
      
      final filename = '${_sanitizeFilename(title)}.pdf';
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        final savedPath = await DesktopFileSaver.savePdf(suggestedName: filename, bytes: bytes);
        if (savedPath != null && mounted) {
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
      } else {
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
                  await OpenFilex.open(filePath);
                },
                child: const Text('Open'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Dismiss loading
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(activeChurchAgesLangProvider);
    final asyncData = ref.watch(churchAgesReaderProvider(lang));
    final typography = ref.watch(typographyProvider(lang));
    final isWide = MediaQuery.sizeOf(context).width >= 800;

    // Sync paragraphs whenever the content changes
    ref.listen(churchAgesReaderProvider(lang), (prev, next) {
      if (next.hasValue && next.value?.currentContent != null) {
        _syncDocument(next.value!.currentContent!.contentText);
      }
    });

    final appBar = _isSearchingContent
        ? AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: _closeContentSearch,
            ),
            title: TextField(
              focusNode: _contentSearchFocusNode,
              controller: _contentSearchController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search in page...',
                border: InputBorder.none,
              ),
              onChanged: (_) {
                if (asyncData.hasValue) {
                  _syncDocument(asyncData.value!.currentContent?.contentHtml ?? '');
                }
              },
              onSubmitted: (_) {
                if (_matchParagraphIndices.isNotEmpty) _navigateToMatch(1);
              },
            ),
            actions: [
              if (_contentSearchController.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _contentSearchController.clear();
                    if (asyncData.hasValue) {
                      _syncDocument(asyncData.value!.currentContent?.contentHtml ?? '');
                    }
                  },
                ),
              if (_matchParagraphIndices.isNotEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      '${_currentMatchIndex + 1}/${_matchParagraphIndices.length}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_up),
                onPressed: _matchParagraphIndices.isEmpty ? null : () => _navigateToMatch(-1),
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down),
                onPressed: _matchParagraphIndices.isEmpty ? null : () => _navigateToMatch(1),
              ),
            ],
          )
        : AppBar(
            title: Text(
              asyncData.when(
                data: (data) => data.parentTopicName != null 
                    ? 'Church Ages - ${data.parentTopicName}'
                    : (lang == 'ta' ? 'சபை காலங்கள்' : 'Church Ages'),
                loading: () => lang == 'ta' ? 'சபை காலங்கள்' : 'Church Ages',
                error: (_, __) => lang == 'ta' ? 'சபை காலங்கள்' : 'Church Ages',
              ),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 1.1,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              IconButton(
                tooltip: 'Decrease font size',
                icon: const Text('A-', style: TextStyle(fontWeight: FontWeight.w700)),
                onPressed: () => _adjustFontSize(lang, -1),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Center(
                  child: Text(
                    typography.fontSize.toInt().toString(),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Increase font size',
                icon: const Text('A+', style: TextStyle(fontWeight: FontWeight.w700)),
                onPressed: () => _adjustFontSize(lang, 1),
              ),
              IconButton(
                tooltip: 'Search in page',
                icon: const Icon(Icons.search),
                onPressed: () {
                  setState(() => _isSearchingContent = true);
                  _contentSearchFocusNode.requestFocus();
                  if (asyncData.hasValue) {
                    _syncDocument(asyncData.value!.currentContent?.contentHtml ?? '');
                  }
                },
              ),
              IconButton(
                tooltip: 'Theme',
                icon: const Icon(Icons.palette),
                onPressed: () => ThemePickerSheet.show(context),
              ),
              IconButton(
                tooltip: 'Info',
                icon: const Icon(Icons.info_outline),
                onPressed: () => HelpSheet.show(context, 'church_ages'),
              ),
              PopupMenuButton<String>(
                onSelected: (val) {
                  if (!asyncData.hasValue) return;
                  final data = asyncData.value!;
                  final title = data.activeTopicTitle ?? 'Church Ages';
                  final html = data.currentContent?.contentHtml ?? '';
                  
                  switch (val) {
                    case 'copy':
                      Clipboard.setData(ClipboardData(text: '$title\n\n${html.replaceAll(RegExp(r'<[^>]*>'), '')}'));
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
                      break;
                    case 'download_pdf':
                      _downloadPdf(title, html, lang, typography);
                      break;
                    case 'download_txt':
                      _downloadTxt(title, html);
                      break;
                    case 'share':
                      Share.share('$title\n\n${html.replaceAll(RegExp(r'<[^>]*>'), '')}');
                      break;
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'copy',
                    child: ListTile(
                      leading: Icon(Icons.copy),
                      title: Text('Copy to Clipboard'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'download_pdf',
                    child: ListTile(
                      leading: Icon(Icons.picture_as_pdf),
                      title: Text('Download PDF'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'download_txt',
                    child: ListTile(
                      leading: Icon(Icons.text_snippet),
                      title: Text('Download TXT'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'share',
                    child: ListTile(
                      leading: Icon(Icons.share),
                      title: Text('Share'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          );

    return Scaffold(
      appBar: appBar,
      endDrawer: isWide ? null : Drawer(
        child: SafeArea(
          child: _buildTopicList(lang, asyncData),
        ),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isWide)
            SizedBox(
              width: 300,
              child: Material(
                elevation: 2,
                child: _buildTopicList(lang, asyncData),
              ),
            ),
          if (isWide) const VerticalDivider(width: 1),
          Expanded(
            child: _buildContent(asyncData),
          ),
        ],
      ),
    );
  }

  Widget _buildTopicList(String lang, AsyncValue<ChurchAgesReaderData> asyncData) {
    return asyncData.when(
      data: (data) {
        final query = _navSearchController.text.toLowerCase().trim();
        final filteredTopics = query.isEmpty 
            ? data.hierarchicalTopics 
            : _filterTopics(data.hierarchicalTopics, query);

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                controller: _navSearchController,
                decoration: InputDecoration(
                  hintText: 'Search Topic...',
                  prefixIcon: const Icon(Icons.filter_list, size: 20),
                  suffixIcon: _navSearchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            setState(() {
                              _navSearchController.clear();
                            });
                          },
                        )
                      : null,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onChanged: (val) => setState(() {}),
              ),
            ),
            Expanded(
              child: ListView.builder(
                key: ValueKey(query), // Force rebuild to apply expansion logic
                itemCount: filteredTopics.length,
                itemBuilder: (context, index) {
                  return _buildTopicNode(lang, data, filteredTopics[index], query, 0);
                },
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text(err.toString())),
    );
  }

  List<ChurchAgesTopic> _filterTopics(List<ChurchAgesTopic> topics, String query) {
    final List<ChurchAgesTopic> filtered = [];
    for (var topic in topics) {
      final matchesSelf = topic.title.toLowerCase().contains(query);
      final filteredChildren = _filterTopics(topic.children, query);
      
      if (matchesSelf || filteredChildren.isNotEmpty) {
        filtered.add(topic.copyWith(children: filteredChildren));
      }
    }
    return filtered;
  }

  Widget _buildTopicNode(String lang, ChurchAgesReaderData data, ChurchAgesTopic topic, String query, int depth) {
    final isActive = data.activeTopicId == topic.id;
    final theme = Theme.of(context);
    final isChapter = depth == 0;
    
    final baseStyle = TextStyle(
      color: isActive 
          ? theme.colorScheme.primary 
          : (isChapter ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant),
      fontWeight: isChapter ? FontWeight.bold : (isActive ? FontWeight.bold : FontWeight.normal),
      fontSize: isChapter ? 15 : 14,
      letterSpacing: isChapter ? 0.2 : null,
    );

    final title = Text.rich(
      TextSpan(
        children: PlainQueryHighlightText.buildHighlightSpans(
          topic.title,
          query.isNotEmpty ? query : null,
          baseStyle: baseStyle,
          highlightBackground: theme.colorScheme.primaryContainer,
        ),
      ),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );

    if (topic.children.isEmpty) {
      return ListTile(
        contentPadding: EdgeInsets.only(left: 16.0 + (depth * 12.0), right: 16.0),
        dense: !isChapter,
        title: title,
        selected: isActive,
        selectedTileColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
        onTap: () {
          ref.read(selectedChurchAgesTopicsProvider.notifier).setTopic(lang, topic.id);
          if (Scaffold.maybeOf(context)?.isEndDrawerOpen == true) {
            Navigator.of(context).pop();
          }
        },
      );
    }

    bool isExpanded = query.isNotEmpty || _hasActiveChild(topic, data.activeTopicId);

    return ExpansionTile(
      tilePadding: EdgeInsets.only(left: 16.0 + (depth * 12.0), right: 16.0),
      title: title,
      initiallyExpanded: isExpanded,
      children: topic.children.map((c) => _buildTopicNode(lang, data, c, query, depth + 1)).toList(),
    );
  }

  bool _hasActiveChild(ChurchAgesTopic topic, int? activeId) {
    if (activeId == null) return false;
    if (topic.id == activeId) return true;
    for (var child in topic.children) {
      if (_hasActiveChild(child, activeId)) return true;
    }
    return false;
  }

  Widget _buildContent(AsyncValue<ChurchAgesReaderData> asyncData) {
    final theme = Theme.of(context);
    final typography = ref.watch(typographyProvider(ref.watch(activeChurchAgesLangProvider)));

    return asyncData.when(
      data: (data) {
        final content = data.currentContent;
        if (content == null) {
          return const Center(child: Text('Select a topic to read.'));
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _syncDocument(content.contentHtml);
          }
        });

        return Column(
          children: [
            if (data.activeTopicTitle != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 24.0),
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor,
                  border: Border(
                    bottom: BorderSide(
                      color: theme.dividerColor.withValues(alpha: 0.1),
                    ),
                  ),
                ),
                child: Text(
                  data.activeTopicTitle!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                controller: _contentScrollController,
                padding: const EdgeInsets.all(24.0),
                child: SelectionArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < _paragraphs.length; i++)
                        Padding(
                          key: _paragraphKeys.putIfAbsent(i, GlobalKey.new),
                          padding: const EdgeInsets.only(bottom: 24),
                          child: Text.rich(
                            TextSpan(
                              children: _buildRichSpans(
                                text: _paragraphs[i],
                                baseStyle: theme.textTheme.bodyLarge?.copyWith(
                                      height: _isHeading(_paragraphs[i]) ? 1.3 : 1.7,
                                      fontSize: typography.fontSize,
                                      color: theme.colorScheme.onSurface,
                                    ) ??
                                    const TextStyle(),
                                query: _contentSearchController.text.trim(),
                                isActiveMatch: _matchParagraphIndices.isNotEmpty &&
                                    _matchParagraphIndices[_currentMatchIndex] == i,
                                theme: theme,
                                isHeading: _isHeading(_paragraphs[i]),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text(err.toString())),
    );
  }

  bool _isHeading(String text) {
    if (text.length < 3) return false;
    // Check if it's all caps (ignoring numbers and symbols)
    final letters = text.replaceAll(RegExp(r'[^a-zA-Z\u0B80-\u0BFF]'), '').trim();
    if (letters.isEmpty) return false;
    // If it's mostly uppercase or looks like a header (short and uppercase)
    if (text.length < 100 && text == text.toUpperCase()) return true;
    return false;
  }

  List<InlineSpan> _buildRichSpans({
    required String text,
    required TextStyle baseStyle,
    required String query,
    required bool isActiveMatch,
    required ThemeData theme,
    required bool isHeading,
  }) {
    final style = isHeading ? baseStyle.copyWith(fontWeight: FontWeight.bold) : baseStyle;
    
    // We combine Search Query and Quotes into one regex to handle them in order
    final patterns = <String>[];
    if (query.isNotEmpty) {
      patterns.add('(${RegExp.escape(query)})');
    }
    // Match anything in double quotes (regular and smart quotes)
    patterns.add('("[^"]+")');
    patterns.add('(“[^”]+”)');
    
    if (patterns.isEmpty) return [TextSpan(text: text, style: style)];
    
    final combinedPattern = RegExp(patterns.join('|'), caseSensitive: false);
    final matches = combinedPattern.allMatches(text).toList();
    if (matches.isEmpty) return [TextSpan(text: text, style: style)];

    final spans = <InlineSpan>[];
    int start = 0;
    
    for (final match in matches) {
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start), style: style));
      }
      
      final matchText = text.substring(match.start, match.end);
      
      // Check which pattern matched
      bool isQuery = query.isNotEmpty && matchText.toLowerCase() == query.toLowerCase();
      bool isQuote = matchText.startsWith('"') || matchText.startsWith('“');

      TextStyle spanStyle = style;
      if (isQuote) {
        spanStyle = spanStyle.copyWith(fontWeight: FontWeight.bold);
      }
      
      if (isQuery) {
        spanStyle = spanStyle.copyWith(
          backgroundColor: isActiveMatch 
              ? theme.colorScheme.primaryContainer 
              : theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
          fontWeight: FontWeight.bold,
        );
      }

      spans.add(TextSpan(text: matchText, style: spanStyle));
      start = match.end;
    }
    
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: style));
    }
    return spans;
  }

  List<InlineSpan> _buildSearchSpans({
    required String text,
    required TextStyle baseStyle,
    required String query,
    required bool isActiveMatch,
    required ThemeData theme,
  }) {
    return _buildRichSpans(
      text: text,
      baseStyle: baseStyle,
      query: query,
      isActiveMatch: isActiveMatch,
      theme: theme,
      isHeading: false,
    );
  }
}
