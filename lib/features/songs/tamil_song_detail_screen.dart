import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:go_router/go_router.dart';

import 'providers/tamil_songs_provider.dart';
import 'models/tamil_song_models.dart';
import '../../../core/database/tamil_song_repository.dart';
import '../../../core/utils/desktop_file_saver.dart';
import '../../../core/utils/tamil_normalizer.dart';
import '../../../core/services/pdf_export_service.dart';
import '../common/widgets/fts_highlight_text.dart';
import '../reader/providers/typography_provider.dart';
import '../settings/widgets/theme_picker_sheet.dart';
import '../help/widgets/help_sheet.dart';

class TamilSongDetailScreen extends ConsumerStatefulWidget {
  final int songId;
  final String? searchQuery;
  const TamilSongDetailScreen({super.key, required this.songId, this.searchQuery});

  @override
  ConsumerState<TamilSongDetailScreen> createState() => _TamilSongDetailScreenState();
}

class _TamilSongDetailScreenState extends ConsumerState<TamilSongDetailScreen> {
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
  late int _currentSongId;

  @override
  void initState() {
    super.initState();
    _currentSongId = widget.songId;
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

  void _adjustReaderFontSize(double nextSize) {
    final next = nextSize.clamp(12.0, 56.0).toDouble();
    ref.read(taTypographyProvider.notifier).updateFontSize(next);
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
    return cleaned.isEmpty ? 'Song' : cleaned;
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

  Future<Uint8List> _buildSongPdfBytes({
    required TamilSong song,
    required TypographySettings typography,
  }) async {
    // Ensure paragraphs are available even if they haven't been synced to the UI yet
    final paragraphs = _paragraphs.isNotEmpty ? _paragraphs : _splitParagraphs(song.fullLyrics ?? '');

    final payload = <String, dynamic>{
      'type': 'songs', // Using 'tract' type as workaround for server validation
      'lang': 'ta',
      'title': normalizeTamil(song.displayName),
      'settings': <String, dynamic>{
        'fontSize': typography.fontSize,
        'lineHeight': typography.lineHeight,
        'titleFontSize': typography.titleFontSize,
        'fontFamily': typography.resolvedFontFamily ?? '',
      },
      'content': <String, dynamic>{
        'paragraphs': paragraphs.asMap().entries.map((e) => {
          'paragraphNumber': e.key + 1, 
          'text': e.value
        }).toList()
      },
    };
    return _pdfExportService.export(payload);
  }

  Future<void> _printPdf(TamilSong song, TypographySettings typography) async {
    await _withPdfProgress(() async {
      try {
        final bytes = await _buildSongPdfBytes(song: song, typography: typography);
        final safeTitle = _sanitizePdfName(normalizeTamil(song.displayName));
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: safeTitle);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    });
  }

  Future<void> _downloadPdf(TamilSong song, TypographySettings typography) async {
    await _withPdfProgress(() async {
      try {
        final bytes = await _buildSongPdfBytes(song: song, typography: typography);
        final filename = '${_sanitizePdfName(normalizeTamil(song.displayName))}.pdf';

        if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
          final savedPath = await DesktopFileSaver.savePdf(suggestedName: filename, bytes: bytes);
          if (!mounted || savedPath == null) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to $savedPath')));
        } else {
          await Share.shareXFiles([XFile.fromData(bytes, name: filename, mimeType: 'application/pdf')]);
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final songAsync = ref.watch(tamilSongDetailProvider(_currentSongId));
    final typography = ref.watch(typographyProvider('ta'));
    final theme = Theme.of(context);

    return songAsync.when(
      data: (song) {
        if (song == null) return const Scaffold(body: Center(child: Text('Song not found')));
        
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _syncDocument(song.fullLyrics ?? '');
        });

        final appBar = _isSearching
            ? AppBar(
                leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _closeSearch),
                title: TextField(
                  focusNode: _searchFocusNode,
                  controller: _searchController,
                  autofocus: true,
                  decoration: const InputDecoration(hintText: 'Search in song...', border: InputBorder.none),
                  onChanged: (_) => _syncDocument(song.fullLyrics ?? ''),
                  onSubmitted: (_) { if (_totalMatches > 0) _navigateToMatch(1); },
                ),
                actions: [
                  if (_searchController.text.isNotEmpty)
                    IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchController.clear(); _syncDocument(song.fullLyrics ?? ''); }),
                  if (_totalMatches > 0)
                    Center(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text('${_currentMatchIndex + 1}/$_totalMatches', style: theme.textTheme.bodySmall))),
                  IconButton(icon: const Icon(Icons.keyboard_arrow_up), onPressed: _totalMatches == 0 ? null : () => _navigateToMatch(-1)),
                  IconButton(icon: const Icon(Icons.keyboard_arrow_down), onPressed: _totalMatches == 0 ? null : () => _navigateToMatch(1)),
                ],
              )
            : AppBar(
                title: Text(song.displayName, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                actions: [
                  IconButton(tooltip: 'Decrease font size', icon: const Text('A-', style: TextStyle(fontWeight: FontWeight.w700)), onPressed: () => _adjustReaderFontSize(typography.fontSize - 2)),
                  IconButton(tooltip: 'Increase font size', icon: const Text('A+', style: TextStyle(fontWeight: FontWeight.w700)), onPressed: () => _adjustReaderFontSize(typography.fontSize + 2)),
                  IconButton(icon: const Icon(Icons.search), tooltip: 'Search in song', onPressed: () { setState(() => _isSearching = true); WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _searchFocusNode.requestFocus(); }); }),
                  IconButton(icon: const Icon(Icons.color_lens), onPressed: () => ThemePickerSheet.show(context)),
                  IconButton(icon: const Icon(Icons.info_outline), tooltip: 'Info', onPressed: () => HelpSheet.show(context, 'tamil_songs')),
                  PopupMenuButton<String>(
                    onSelected: (val) {
                      switch (val) {
                        case 'copy': Clipboard.setData(ClipboardData(text: '${song.displayName}\n\n${song.fullLyrics ?? ''}')); break;
                        case 'share': Share.share('${song.displayName}\n\n${song.fullLyrics ?? ''}'); break;
                        case 'download_pdf': _downloadPdf(song, typography); break;
                        case 'print_pdf': _printPdf(song, typography); break;
                        case 'download_lyrics': _downloadLyrics(song); break;
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(value: 'copy', child: ListTile(leading: Icon(Icons.copy), title: Text('Copy'), contentPadding: EdgeInsets.zero)),
                      const PopupMenuItem(value: 'share', child: ListTile(leading: Icon(Icons.share), title: Text('Share'), contentPadding: EdgeInsets.zero)),
                      const PopupMenuItem(value: 'download_pdf', child: ListTile(leading: Icon(Icons.download), title: Text('Download PDF'), contentPadding: EdgeInsets.zero)),
                      const PopupMenuItem(value: 'print_pdf', child: ListTile(leading: Icon(Icons.print), title: Text('Print PDF'), contentPadding: EdgeInsets.zero)),
                      const PopupMenuItem(value: 'download_lyrics', child: ListTile(leading: Icon(Icons.text_snippet), title: Text('Download TXT'), contentPadding: EdgeInsets.zero)),
                    ],
                  ),
                ],
              );

        return Scaffold(
          appBar: appBar,
          body: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16.0),
                  child: SelectionArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(song.displayName, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, fontSize: typography.titleFontSize + 8, fontFamily: typography.resolvedFontFamily)),
                        if (song.artistName != null) Text(song.artistName!, style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary, fontFamily: typography.resolvedFontFamily)),
                        const Divider(height: 32),
                        for (var i = 0; i < _paragraphs.length; i++)
                          Padding(
                            key: _keyForParagraph(i),
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Text.rich(
                              TextSpan(
                                children: _buildHighlightedSpans(
                                  text: _paragraphs[i],
                                  baseStyle: TextStyle(fontSize: typography.fontSize, height: typography.lineHeight, color: theme.colorScheme.onSurface, fontFamily: typography.resolvedFontFamily),
                                  passiveBg: theme.colorScheme.secondaryContainer.withAlpha(150),
                                  activeBg: theme.colorScheme.primaryContainer,
                                  activeFg: theme.colorScheme.onPrimaryContainer,
                                  currentOccurrenceIndex: _currentOccurrenceForParagraph(i),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              _buildBottomNav(song),
            ],
          ),
        );
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, __) => Scaffold(body: Center(child: Text('Error: $err'))),
    );
  }

  Future<void> _downloadLyrics(TamilSong song) async {
    final lyrics = song.fullLyrics ?? '';
    if (lyrics.isEmpty) return;
    
    final content = '${song.displayName}\n\n$lyrics';
    
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      final path = await DesktopFileSaver.saveText(
        suggestedName: '${song.name.replaceAll(' ', '_')}_lyrics.txt', 
        bytes: utf8.encode(content),
      );
      if (path != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to $path')));
    } else {
      await Share.share(content);
    }
  }

  Widget _buildBottomNav(TamilSong song) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, -2))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildNavButton(isNext: false),
          _buildNavButton(isNext: true),
        ],
      ),
    );
  }

  Widget _buildNavButton({required bool isNext}) {
    return FutureBuilder<TamilSong?>(
      future: isNext 
        ? ref.read(tamilSongRepositoryProvider).getNextSong(_currentSongId, sortBy: TamilSongSort.songNo)
        : ref.read(tamilSongRepositoryProvider).getPreviousSong(_currentSongId, sortBy: TamilSongSort.songNo),
      builder: (context, snapshot) {
        final neighbor = snapshot.data;
        if (neighbor == null) return const SizedBox.shrink();
        return TextButton(
          onPressed: () { setState(() { _currentSongId = neighbor.id; _closeSearch(); }); },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isNext) const Icon(Icons.chevron_left),
              Column(
                crossAxisAlignment: isNext ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Text(isNext ? 'Next' : 'Previous', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  Text(neighbor.displayName.length > 15 ? '${neighbor.displayName.substring(0, 15)}...' : neighbor.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              if (isNext) const Icon(Icons.chevron_right),
            ],
          ),
        );
      },
    );
  }
}
