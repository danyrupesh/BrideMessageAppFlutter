import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart' show SharePlus, ShareParams;

import '../../core/database/models/cod_models.dart';
import '../common/widgets/fts_highlight_text.dart';
import '../reader/providers/typography_provider.dart';
import '../reader/widgets/reader_settings_sheet.dart';
import '../sermons/providers/sermon_provider.dart';
import 'providers/cod_provider.dart';

class _AppBarChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _AppBarChip({
    required this.label,
    required this.icon,
    required this.onTap,
  });

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
            Icon(icon, size: 16, color: cs.primary),
            const SizedBox(width: 4),
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

class CodAnswerScreen extends ConsumerStatefulWidget {
  final String lang;
  final String id;

  /// When set (e.g. from Common Search), scrolls this [answers] row into view.
  final int? scrollToAnswerParagraphId;

  /// Plain-text substring to highlight inside each answer paragraph.
  final String? highlightQuery;

  const CodAnswerScreen({
    super.key,
    required this.lang,
    required this.id,
    this.scrollToAnswerParagraphId,
    this.highlightQuery,
  });

  @override
  ConsumerState<CodAnswerScreen> createState() => _CodAnswerScreenState();
}

class _CodAnswerScreenState extends ConsumerState<CodAnswerScreen> {
  final ScrollController _scrollController = ScrollController();
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;

  bool _isSearching = false;
  List<CodAnswerParagraph> _displayParas = [];
  final Map<int, GlobalKey> _paragraphKeys = {};

  /// Per-occurrence indices into [_displayParas] (same pattern as sermon reader).
  List<int> _matchDisplayIndices = [];
  int _currentMatchIndex = 0;

  String? _lastLoadedSig;

  GlobalKey _keyForParagraph(int paragraphId) {
    return _paragraphKeys.putIfAbsent(paragraphId, GlobalKey.new);
  }

  int get _totalMatches => _matchDisplayIndices.length;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();
    final hq = widget.highlightQuery?.trim();
    if (hq != null && hq.isNotEmpty) {
      _searchController.text = hq;
      _isSearching = true;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  void didUpdateWidget(CodAnswerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id ||
        oldWidget.scrollToAnswerParagraphId !=
            widget.scrollToAnswerParagraphId ||
        oldWidget.highlightQuery != widget.highlightQuery) {
      _lastLoadedSig = null;
      _paragraphKeys.clear();
    }
  }

  String _lineForPara(CodAnswerParagraph para) {
    final label = para.label?.trim();
    final body = para.plainText.trim();
    if (label != null && label.isNotEmpty) {
      return '$label $body';
    }
    return body;
  }

  String? get _activeHighlightQuery {
    if (_isSearching) {
      final t = _searchController.text.trim();
      return t.isEmpty ? null : t;
    }
    return null;
  }

  double _toolbarTopInset() {
    final typography = ref.read(typographyProvider(widget.lang));
    final media = MediaQuery.of(context);
    if (typography.isFullscreen) {
      return media.padding.top + 8;
    }
    return media.padding.top + kToolbarHeight;
  }

  double _estimatedOffsetForDisplayIndex(int displayIdx) {
    if (!_scrollController.hasClients || _displayParas.isEmpty) return 0;
    final max = _scrollController.position.maxScrollExtent;
    final n = _displayParas.length;
    final frac = n <= 1 ? 0.0 : displayIdx / (n - 1);
    return (max * frac).clamp(0.0, max).toDouble();
  }

  void _jumpAlignParagraphUnderAppBar(int paragraphId) {
    if (!_scrollController.hasClients) return;
    if (!mounted) return;
    final ctx = _keyForParagraph(paragraphId).currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;

    final targetScreenY = _toolbarTopInset();
    final topOffset = box.localToGlobal(Offset.zero).dy;
    final delta = topOffset - targetScreenY;
    if (delta.abs() < 2) return;

    final nextOffset = (_scrollController.offset + delta).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.jumpTo(nextOffset.toDouble());
  }

  void _computeMatches(
    String query, {
    bool scrollToMatch = true,
    int? preferParagraphId,
  }) {
    if (query.trim().isEmpty) {
      setState(() {
        _matchDisplayIndices = [];
        _currentMatchIndex = 0;
      });
      return;
    }
    final pattern = RegExp(RegExp.escape(query.trim()), caseSensitive: false);
    final indices = <int>[];
    for (var pi = 0; pi < _displayParas.length; pi++) {
      final text = _lineForPara(_displayParas[pi]);
      final n = pattern.allMatches(text).length;
      for (var j = 0; j < n; j++) {
        indices.add(pi);
      }
    }
    var startIdx = 0;
    if (preferParagraphId != null && indices.isNotEmpty) {
      final pos = indices.indexWhere(
        (pi) => _displayParas[pi].id == preferParagraphId,
      );
      if (pos >= 0) startIdx = pos;
    }
    setState(() {
      _matchDisplayIndices = indices;
      _currentMatchIndex = indices.isEmpty ? 0 : startIdx;
    });
    if (scrollToMatch && indices.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToCurrentMatch();
      });
    }
  }

  void _navigateToMatch(int direction) {
    if (_matchDisplayIndices.isEmpty) return;
    setState(() {
      _currentMatchIndex =
          (_currentMatchIndex + direction) % _matchDisplayIndices.length;
      if (_currentMatchIndex < 0) {
        _currentMatchIndex = _matchDisplayIndices.length - 1;
      }
    });
    _scrollToCurrentMatch();
  }

  void _scrollToCurrentMatch({int retryCount = 0, bool instantScroll = false}) {
    if (_matchDisplayIndices.isEmpty) return;
    final displayIdx = _matchDisplayIndices[_currentMatchIndex];
    final para = _displayParas[displayIdx];
    final pid = para.id;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final ensureDuration = instantScroll
          ? Duration.zero
          : const Duration(milliseconds: 300);
      final ctx = _keyForParagraph(pid).currentContext;
      if (ctx != null) {
        await Scrollable.ensureVisible(
          ctx,
          duration: ensureDuration,
          curve: Curves.easeInOut,
          alignment: 0.12,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        );
        if (!mounted) return;
        _jumpAlignParagraphUnderAppBar(pid);
        return;
      }
      if (_scrollController.hasClients) {
        final estimated = _estimatedOffsetForDisplayIndex(displayIdx);
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
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!mounted) return;
      _scrollToCurrentMatch(
        retryCount: retryCount + 1,
        instantScroll: instantScroll,
      );
    });
  }

  void _closeSearch() {
    setState(() {
      _isSearching = false;
      _searchController.clear();
      _matchDisplayIndices = [];
      _currentMatchIndex = 0;
    });
  }

  void _handleAnswersLoaded(List<CodAnswerParagraph> answers) {
    final sig = '${widget.id}|${answers.map((a) => a.id).join(',')}';
    if (sig == _lastLoadedSig) return;
    _lastLoadedSig = sig;

    final displayParas = answers
        .where((p) => p.plainText.trim().isNotEmpty)
        .toList();
    setState(() => _displayParas = displayParas);

    final hq = widget.highlightQuery?.trim();
    if (hq != null && hq.isNotEmpty) {
      setState(() => _isSearching = true);
      if (_searchController.text != hq) {
        _searchController.value = TextEditingValue(
          text: hq,
          selection: TextSelection.collapsed(offset: hq.length),
        );
      }
      _computeMatches(
        hq,
        scrollToMatch: false,
        preferParagraphId: widget.scrollToAnswerParagraphId,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToCurrentMatch(instantScroll: true);
      });
    } else if (_isSearching && _searchController.text.trim().isNotEmpty) {
      _computeMatches(_searchController.text, scrollToMatch: false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _matchDisplayIndices.isNotEmpty) {
          _scrollToCurrentMatch(instantScroll: true);
        }
      });
    }
  }

  String _buildFullAnswerText(List<CodAnswerParagraph> answers) {
    return answers
        .map((para) {
          final label = para.label?.trim();
          final text = para.plainText.trim();
          if (text.isEmpty) return '';
          if (label != null && label.isNotEmpty) {
            return '$label $text';
          }
          return text;
        })
        .where((chunk) => chunk.isNotEmpty)
        .join('\n\n');
  }

  void _openCodSermons() {
    ref.read(selectedSermonLangProvider.notifier).setLang(widget.lang);
    final isTamil = widget.lang == 'ta';
    final uri = Uri(
      path: '/sermons',
      queryParameters: {
        'mode': 'cod',
        'title': isTamil
            ? 'COD - கேள்விகளும் பதில்களும்'
            : 'COD - Question and Answers',
        'lang': widget.lang,
      },
    );
    context.push(uri.toString());
  }

  void _openSermonList() {
    ref.read(selectedSermonLangProvider.notifier).setLang(widget.lang);
    context.push('/sermons');
  }

  Future<void> _copyAnswer(String text, bool isTamil) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isTamil ? 'பதில் நகலெடுக்கப்பட்டது' : 'Answer copied'),
      ),
    );
  }

  void _shareAnswer(String text) {
    SharePlus.instance.share(ShareParams(text: text));
  }

  void _adjustReaderFontSize(double delta) {
    final typography = ref.read(typographyProvider(widget.lang));
    final next = (typography.fontSize + delta).clamp(12.0, 56.0).toDouble();
    if (widget.lang == 'ta') {
      ref.read(taTypographyProvider.notifier).updateFontSize(next);
    } else {
      ref.read(enTypographyProvider.notifier).updateFontSize(next);
    }
  }

  PreferredSizeWidget? _buildAppBar({
    required bool isTamil,
    required bool canUseAnswerActions,
    required String shareTextForActions,
  }) {
    final typography = ref.watch(typographyProvider(widget.lang));
    if (typography.isFullscreen) return null;

    if (_isSearching) {
      return AppBar(
        toolbarHeight: kToolbarHeight,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _closeSearch,
        ),
        title: TextField(
          focusNode: _searchFocusNode,
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: isTamil ? 'பதிலில் தேடு…' : 'Search in answer…',
            border: InputBorder.none,
            filled: false,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
          ),
          onSubmitted: (_) {
            if (_totalMatches > 0) _navigateToMatch(1);
          },
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
          PopupMenuButton<String>(
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'copy',
                child: ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: Text(isTamil ? 'நகலெடு' : 'Copy'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'share',
                child: ListTile(
                  leading: const Icon(Icons.share_rounded),
                  title: Text(isTamil ? 'பகிர்' : 'Share'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'home',
                child: ListTile(
                  leading: const Icon(Icons.home),
                  title: const Text('Home'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  leading: const Icon(Icons.settings),
                  title: Text(isTamil ? 'அமைப்புகள்' : 'Settings'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
            onSelected: (v) {
              switch (v) {
                case 'copy':
                  if (canUseAnswerActions) {
                    _copyAnswer(shareTextForActions, isTamil);
                  }
                  break;
                case 'share':
                  if (canUseAnswerActions) {
                    _shareAnswer(shareTextForActions);
                  }
                  break;
                case 'home':
                  context.go('/');
                  break;
                case 'settings':
                  ReaderSettingsSheet.show(context, lang: widget.lang);
                  break;
              }
            },
          ),
        ],
      );
    }

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.pop(),
      ),
      titleSpacing: 0,
      title: LayoutBuilder(
        builder: (context, constraints) {
          final chips = Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _AppBarChip(
                label: isTamil ? 'COD செய்திகள்' : 'COD Sermons',
                icon: Icons.article_outlined,
                onTap: _openCodSermons,
              ),
              _AppBarChip(
                label: isTamil ? 'செய்திகள் பட்டியல்' : 'Sermon List',
                icon: Icons.menu_book_outlined,
                onTap: _openSermonList,
              ),
            ],
          );
          return constraints.maxWidth >= 700
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [chips],
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: chips,
                );
        },
      ),
      actions: [
        IconButton(
          icon: const Text('A-', style: TextStyle(fontWeight: FontWeight.w700)),
          tooltip: isTamil ? 'எழுத்தளவை குறை' : 'Decrease font size',
          onPressed: () => _adjustReaderFontSize(-1),
        ),
        IconButton(
          icon: const Text('A+', style: TextStyle(fontWeight: FontWeight.w700)),
          tooltip: isTamil ? 'எழுத்தளவை அதிகரி' : 'Increase font size',
          onPressed: () => _adjustReaderFontSize(1),
        ),
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: isTamil ? 'பதிலில் தேடு' : 'Search in answer',
          onPressed: () {
            setState(() => _isSearching = true);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _searchFocusNode.requestFocus();
            });
          },
        ),
        IconButton(
          icon: const Icon(Icons.copy_rounded),
          tooltip: isTamil ? 'முழு பதிலை நகலெடு' : 'Copy Full Answer',
          onPressed: canUseAnswerActions
              ? () => _copyAnswer(shareTextForActions, isTamil)
              : null,
        ),
        IconButton(
          icon: const Icon(Icons.share_rounded),
          tooltip: isTamil ? 'முழு பதிலை பகிர்' : 'Share Full Answer',
          onPressed: canUseAnswerActions
              ? () => _shareAnswer(shareTextForActions)
              : null,
        ),
        IconButton(
          icon: const Icon(Icons.home),
          tooltip: 'Home',
          onPressed: () => context.go('/'),
        ),
        IconButton(
          icon: const Icon(Icons.settings),
          tooltip: 'Reader Settings',
          onPressed: () => ReaderSettingsSheet.show(context, lang: widget.lang),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final asyncData = ref.watch(
      codQuestionDetailProvider((lang: widget.lang, id: widget.id)),
    );
    final isTamil = widget.lang == 'ta';
    final tupleForActions = asyncData.asData?.value;
    final questionForActions = tupleForActions?.$1;
    final answersForActions =
        tupleForActions?.$2 ?? const <CodAnswerParagraph>[];
    final fullAnswerForActions = _buildFullAnswerText(answersForActions);
    final shareTextForActions = <String>[
      if (questionForActions != null) questionForActions.title,
      fullAnswerForActions,
    ].where((part) => part.trim().isNotEmpty).join('\n\n');
    final canUseAnswerActions = shareTextForActions.trim().isNotEmpty;

    final typography = ref.watch(typographyProvider(widget.lang));
    final isFullscreen = typography.isFullscreen;
    final titleStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.bold,
      fontSize: typography.titleFontSize + 6,
      fontFamily: typography.resolvedFontFamily,
      height: 1.35,
    );
    final bodyStyle = Theme.of(context).textTheme.bodyLarge!.copyWith(
      fontSize: typography.fontSize < 20
          ? typography.fontSize + 2
          : typography.fontSize,
      height: typography.lineHeight,
      fontFamily: typography.resolvedFontFamily,
    );

    final appBar = _buildAppBar(
      isTamil: isTamil,
      canUseAnswerActions: canUseAnswerActions,
      shareTextForActions: shareTextForActions,
    );

    return Scaffold(
      appBar: appBar,
      body: Builder(
        builder: (context) {
          final content = asyncData.when(
            data: (tuple) {
              final question = tuple.$1;
              final answers = tuple.$2;
              if (question == null) {
                return Center(
                  child: Text(
                    isTamil ? 'கேள்வி கிடைக்கவில்லை.' : 'Question not found.',
                  ),
                );
              }

              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _handleAnswersLoaded(answers);
              });

              final fullAnswerText = _buildFullAnswerText(answers);
              final highlightQ = _activeHighlightQuery;

              return ListView(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                children: [
                  Text(question.title, style: titleStyle),
                  const SizedBox(height: 8),
                  if (question.series != null || question.pageRef != null)
                    Text(
                      [
                        if (question.series != null) question.series!,
                        if (question.pageRef != null) question.pageRef!,
                      ].join(' • '),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontFamily: typography.resolvedFontFamily,
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (fullAnswerText.isEmpty)
                    Text(
                      isTamil
                          ? 'பதில் கிடைக்கவில்லை.'
                          : 'No answer text available.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    )
                  else
                    ...answers.expand((para) {
                      final label = para.label?.trim();
                      final body = para.plainText.trim();
                      if (body.isEmpty) return const Iterable<Widget>.empty();
                      final line = (label != null && label.isNotEmpty)
                          ? '$label $body'
                          : body;
                      return [
                        Padding(
                          key: _keyForParagraph(para.id),
                          padding: const EdgeInsets.only(bottom: 14),
                          child: SelectableText.rich(
                            TextSpan(
                              children:
                                  PlainQueryHighlightText.buildHighlightSpans(
                                    line,
                                    highlightQ,
                                    baseStyle: bodyStyle,
                                  ),
                            ),
                            textAlign: TextAlign.justify,
                          ),
                        ),
                      ];
                    }),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Failed to load answer: $err',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );

          if (!isFullscreen) {
            return content;
          }

          return Stack(
            children: [
              content,
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
                          .read(typographyGlobalProvider.notifier)
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
          );
        },
      ),
    );
  }
}
