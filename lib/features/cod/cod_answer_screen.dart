import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart' show SharePlus, ShareParams;

import '../../core/database/models/cod_models.dart';
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

  const CodAnswerScreen({super.key, required this.lang, required this.id});

  @override
  ConsumerState<CodAnswerScreen> createState() => _CodAnswerScreenState();
}

class _CodAnswerScreenState extends ConsumerState<CodAnswerScreen> {
  String _buildFullAnswerText(List<CodAnswerParagraph> answers) {
    return answers
        .map((para) {
          final label = para.label?.trim();
          final text = para.plainText.trim();
          if (text.isEmpty) return '';
          if (label != null && label.isNotEmpty) {
            // Keep label and paragraph start on the same line.
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
        'prefix': isTamil ? 'கேள்வி' : 'Question',
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

    final typography = ref.watch(typographyProvider);
    final isFullscreen = typography.isFullscreen;
    final titleStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.bold,
      fontSize: typography.titleFontSize + 6,
      fontFamily: typography.resolvedFontFamily,
      height: 1.35,
    );
    final bodyStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
      fontSize: typography.fontSize < 20
          ? typography.fontSize + 2
          : typography.fontSize,
      height: typography.lineHeight,
      fontFamily: typography.resolvedFontFamily,
    );

    return Scaffold(
      appBar: isFullscreen
          ? null
          : AppBar(
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
                  onPressed: () => ReaderSettingsSheet.show(context),
                ),
              ],
            ),
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

              final fullAnswerText = _buildFullAnswerText(answers);

              return ListView(
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
                    SelectableText(
                      fullAnswerText,
                      textAlign: TextAlign.justify,
                      style: bodyStyle,
                    ),
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
          );
        },
      ),
    );
  }
}
