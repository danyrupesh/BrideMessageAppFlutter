import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/services/pdf_export_service.dart';
import '../../core/utils/desktop_file_saver.dart';
import '../../core/utils/tamil_normalizer.dart';
import '../help/widgets/help_sheet.dart';
import '../reader/providers/typography_provider.dart';
import '../settings/widgets/theme_picker_sheet.dart';
import 'models/tract_model.dart';
import 'providers/tracts_provider.dart';

class TractReaderScreen extends ConsumerStatefulWidget {
  final String id;
  final String? searchQuery;

  const TractReaderScreen({super.key, required this.id, this.searchQuery});

  @override
  ConsumerState<TractReaderScreen> createState() => _TractReaderScreenState();
}

class _TractReaderScreenState extends ConsumerState<TractReaderScreen> {
  static final PdfExportService _pdfExportService = PdfExportService();

  final ScrollController _scrollController = ScrollController();
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;

  bool _isSearching = false;
  List<String> _paragraphs = const [];
  List<int> _matchParagraphIndices = const [];
  int _currentMatchIndex = 0;
  final Map<int, GlobalKey> _paragraphKeys = <int, GlobalKey>{};
  String _lastSyncSignature = '';

  @override
  void initState() {
    super.initState();
    final q = widget.searchQuery?.trim();
    _searchController = TextEditingController(text: q ?? '');
    _searchFocusNode = FocusNode();
    _isSearching = q != null && q.isNotEmpty;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  String? get _activeQuery {
    final q = _searchController.text.trim();
    if (q.isEmpty) return null;
    return q;
  }

  int get _totalMatches => _matchParagraphIndices.length;

  GlobalKey _keyForParagraph(int paragraphIndex) {
    return _paragraphKeys.putIfAbsent(paragraphIndex, GlobalKey.new);
  }

  void _closeSearch() {
    setState(() {
      _isSearching = false;
      _searchController.clear();
      _matchParagraphIndices = const [];
      _currentMatchIndex = 0;
      _lastSyncSignature = '';
    });
  }

  List<String> _splitParagraphs(String content) {
    final normalized = content.replaceAll('\r\n', '\n');
    return normalized
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList(growable: false);
  }

  void _syncDocument(String content) {
    final query = _activeQuery;
    final sig = '${content.hashCode}|$query';
    if (sig == _lastSyncSignature) return;
    _lastSyncSignature = sig;

    final paragraphs = _splitParagraphs(content);

    final matches = <int>[];
    if (query != null) {
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

    if (matches.isNotEmpty) {
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
    final ctx = _keyForParagraph(paragraphIndex).currentContext;
    if (ctx == null) return;

    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOut,
      alignment: 0.2,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
  }

  int? _currentOccurrenceForParagraph(int paragraphIndex) {
    if (_matchParagraphIndices.isEmpty) return null;
    if (_currentMatchIndex < 0 ||
        _currentMatchIndex >= _matchParagraphIndices.length) {
      return null;
    }
    if (_matchParagraphIndices[_currentMatchIndex] != paragraphIndex) {
      return null;
    }

    var count = 0;
    for (var i = 0; i < _currentMatchIndex; i++) {
      if (_matchParagraphIndices[i] == paragraphIndex) count++;
    }
    return count;
  }

  void _adjustReaderFontSize(String langCode, double nextSize) {
    final next = nextSize.clamp(12.0, 56.0).toDouble();
    if (langCode == 'ta') {
      ref.read(taTypographyProvider.notifier).updateFontSize(next);
    } else {
      ref.read(enTypographyProvider.notifier).updateFontSize(next);
    }
  }

  List<InlineSpan> _buildHighlightedSpans({
    required String text,
    required TextStyle baseStyle,
    required Color passiveBg,
    required Color activeBg,
    required Color activeFg,
    required int? currentOccurrenceIndex,
  }) {
    final query = _activeQuery;
    if (query == null) {
      return [TextSpan(text: text, style: baseStyle)];
    }

    final pattern = RegExp(RegExp.escape(query), caseSensitive: false);
    final matches = pattern.allMatches(text).toList(growable: false);
    if (matches.isEmpty) {
      return [TextSpan(text: text, style: baseStyle)];
    }

    final spans = <InlineSpan>[];
    var start = 0;
    var occurrence = 0;

    for (final match in matches) {
      if (match.start > start) {
        spans.add(
          TextSpan(text: text.substring(start, match.start), style: baseStyle),
        );
      }

      final matched = text.substring(match.start, match.end);
      final isActive =
          currentOccurrenceIndex != null &&
          occurrence == currentOccurrenceIndex;
      spans.add(
        TextSpan(
          text: matched,
          style: baseStyle.copyWith(
            backgroundColor: isActive ? activeBg : passiveBg,
            color: isActive ? activeFg : baseStyle.color,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      start = match.end;
      occurrence++;
    }

    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: baseStyle));
    }
    return spans;
  }

  String _sanitizePdfName(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[<>:"/\\|?*]'), '-').trim();
    return cleaned.isEmpty ? 'Document' : cleaned;
  }

  String _resolvePdfTitle({
    required Tract tract,
    required String langCode,
  }) {
    final raw = tract.title.trim();
    if (langCode == 'ta') {
      return normalizeTamil(raw);
    }
    return raw;
  }

  String _normalizePdfText(String raw) {
    return raw
        .replaceAll(RegExp(r'[“”„‟″＂]'), '"')
        .replaceAll(RegExp(r"[‘’‚‛′＇]"), "'")
        .replaceAll('\u00A0', ' ');
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

  List<Map<String, dynamic>> _paragraphPayload() {
    return _paragraphs
        .asMap()
        .entries
        .map(
          (entry) => <String, dynamic>{
            'paragraphNumber': entry.key + 1,
            'text': entry.value,
          },
        )
        .toList(growable: false);
  }

  Future<Uint8List> _buildEnglishLocalPdfBytes(Tract tract) async {
    final doc = pw.Document();
    final title = _normalizePdfText(tract.title.trim());

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          final widgets = <pw.Widget>[
            pw.Text(
              title,
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 12),
          ];

          for (final para in _paragraphs) {
            widgets.add(
              pw.Paragraph(
                text: _normalizePdfText(para),
                style: const pw.TextStyle(fontSize: 12, lineSpacing: 2),
              ),
            );
            widgets.add(pw.SizedBox(height: 6));
          }
          return widgets;
        },
      ),
    );

    return doc.save();
  }

  Future<Uint8List> _buildTractPdfBytes({
    required Tract tract,
    required String langCode,
    required TypographySettings typography,
  }) async {
    if (langCode == 'ta') {
      final payload = <String, dynamic>{
        'type': 'tract',
        'lang': 'ta',
        'title': normalizeTamil(tract.title),
        'settings': <String, dynamic>{
          'fontSize': typography.fontSize,
          'lineHeight': typography.lineHeight,
          'titleFontSize': typography.titleFontSize,
          'fontFamily': typography.resolvedFontFamily ?? '',
        },
        'content': <String, dynamic>{'paragraphs': _paragraphPayload()},
      };
      return _pdfExportService.export(payload);
    }

    return _buildEnglishLocalPdfBytes(tract);
  }

  Future<void> _printPdf({
    required Tract tract,
    required String langCode,
    required TypographySettings typography,
  }) async {
    await _withPdfProgress(() async {
      late final Uint8List bytes;
      try {
        bytes = await _buildTractPdfBytes(
          tract: tract,
          langCode: langCode,
          typography: typography,
        );
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
      final safeTitle = _sanitizePdfName(
        _resolvePdfTitle(tract: tract, langCode: langCode),
      );
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: safeTitle);
    });
  }

  Future<void> _downloadPdf({
    required Tract tract,
    required String langCode,
    required TypographySettings typography,
  }) async {
    await _withPdfProgress(() async {
      late final Uint8List bytes;
      try {
        bytes = await _buildTractPdfBytes(
          tract: tract,
          langCode: langCode,
          typography: typography,
        );
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
      final filename =
          '${_sanitizePdfName(_resolvePdfTitle(tract: tract, langCode: langCode))}.pdf';

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
    });
  }

  @override
  Widget build(BuildContext context) {
    final uiState = ref.watch(tractsProvider);
    if (uiState is! TractsSuccess) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final tract = uiState.tracts.firstWhere(
      (t) => t.id == widget.id,
      orElse: () => uiState.tracts.first,
    );
    final langCode = tract.lang.toLowerCase() == 'ta' ? 'ta' : 'en';
    final typography = ref.watch(typographyProvider(langCode));
    final theme = Theme.of(context);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncDocument(tract.content);
    });

    final titleStyle = theme.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w800,
      fontSize: typography.titleFontSize,
      fontFamily: typography.resolvedFontFamily,
      height: 1.3,
    );

    final sermonLikeFontSize = typography.fontSize.clamp(12.0, 56.0).toDouble();
    final bodyStyle =
        theme.textTheme.bodyLarge?.copyWith(
          fontSize: sermonLikeFontSize,
          height: typography.lineHeight,
          color: theme.colorScheme.onSurface,
          fontFamily: typography.resolvedFontFamily,
        ) ??
        const TextStyle();

    final appBar = _isSearching
        ? AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: _closeSearch,
            ),
            title: TextField(
              focusNode: _searchFocusNode,
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search in tract...',
                border: InputBorder.none,
                isDense: true,
              ),
              onChanged: (_) => _syncDocument(tract.content),
              onSubmitted: (_) {
                if (_totalMatches > 0) _navigateToMatch(1);
              },
            ),
            actions: [
              if (_searchController.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _syncDocument(tract.content);
                  },
                ),
              if (_totalMatches > 0)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      '${_currentMatchIndex + 1}/$_totalMatches',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_up),
                onPressed: _totalMatches == 0
                    ? null
                    : () => _navigateToMatch(-1),
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down),
                onPressed: _totalMatches == 0
                    ? null
                    : () => _navigateToMatch(1),
              ),
            ],
          )
        : AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/tracts?lang=$langCode'),
            ),
            toolbarHeight: 72,
            title: Text(
              tract.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            actions: [
              IconButton(
                tooltip: 'Decrease font size',
                icon: const Text(
                  'A-',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                onPressed: () =>
                    _adjustReaderFontSize(langCode, typography.fontSize - 1),
              ),
              IconButton(
                tooltip: 'Increase font size',
                icon: const Text(
                  'A+',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                onPressed: () =>
                    _adjustReaderFontSize(langCode, typography.fontSize + 1),
              ),
              IconButton(
                icon: const Icon(Icons.search),
                tooltip: 'Search in tract',
                onPressed: () {
                  setState(() => _isSearching = true);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _searchFocusNode.requestFocus();
                  });
                },
              ),
              IconButton(
                icon: const Icon(Icons.color_lens),
                onPressed: () => ThemePickerSheet.show(context),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: TextButton.icon(
                  onPressed: () => HelpSheet.show(context, 'tracts'),
                  icon: const Icon(Icons.info_outline, size: 18),
                  label: const Text('Info'),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.onSurfaceVariant,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'More actions',
                itemBuilder: (ctx) => const [
                  PopupMenuItem(
                    value: 'download_pdf',
                    child: ListTile(
                      leading: Icon(Icons.download_rounded),
                      title: Text('Download PDF'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'print_pdf',
                    child: ListTile(
                      leading: Icon(Icons.print_rounded),
                      title: Text('Print PDF'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
                onSelected: (value) {
                  if (value == 'download_pdf') {
                    _downloadPdf(
                      tract: tract,
                      langCode: langCode,
                      typography: typography,
                    );
                  }
                  if (value == 'print_pdf') {
                    _printPdf(
                      tract: tract,
                      langCode: langCode,
                      typography: typography,
                    );
                  }
                },
              ),
            ],
          );

    return Scaffold(
      appBar: appBar,
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withAlpha(90),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withAlpha(160),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tract.title, style: titleStyle),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(
                          Icons.menu_book_rounded,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          langCode == 'ta'
                              ? 'தமிழ் பிரசுரம்'
                              : 'English Tract',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_activeQuery != null) ...[
                          const SizedBox(width: 12),
                          Icon(
                            Icons.search,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _totalMatches == 0
                                ? '0 matches'
                                : '${_currentMatchIndex + 1}/$_totalMatches matches',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Material(
                elevation: 0.5,
                borderRadius: BorderRadius.circular(18),
                color: theme.colorScheme.surface,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 20,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withAlpha(
                        140,
                      ),
                    ),
                  ),
                  child: SelectionArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < _paragraphs.length; i++)
                          Padding(
                            key: _keyForParagraph(i),
                            padding: EdgeInsets.only(
                              bottom: i == _paragraphs.length - 1 ? 0 : 14,
                            ),
                            child: SelectableText.rich(
                              TextSpan(
                                children: _buildHighlightedSpans(
                                  text: _paragraphs[i],
                                  baseStyle: bodyStyle,
                                  passiveBg: theme
                                      .colorScheme
                                      .secondaryContainer
                                      .withAlpha(150),
                                  activeBg:
                                      theme.colorScheme.primaryContainer,
                                  activeFg:
                                      theme.colorScheme.onPrimaryContainer,
                                  currentOccurrenceIndex:
                                      _currentOccurrenceForParagraph(i),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}
