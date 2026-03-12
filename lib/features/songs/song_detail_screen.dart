import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/database/models/hymn_models.dart';
import 'providers/song_detail_provider.dart';

class SongDetailScreen extends StatelessWidget {
  const SongDetailScreen({
    super.key,
    required this.hymnNo,
  });

  final int hymnNo;

  @override
  Widget build(BuildContext context) {
    return _SongDetailReader(hymnNo: hymnNo);
  }
}

class _SongDetailReader extends ConsumerStatefulWidget {
  const _SongDetailReader({required this.hymnNo});

  final int hymnNo;

  @override
  ConsumerState<_SongDetailReader> createState() => _SongDetailReaderState();
}

class _SongDetailReaderState extends ConsumerState<_SongDetailReader> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(songDetailProvider.notifier).loadFor(widget.hymnNo);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final SongDetailUiState state = ref.watch(songDetailProvider);
    final SongDetailNotifier notifier = ref.read(songDetailProvider.notifier);

    final palette = _ReaderPalette.from(theme, state.theme);

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        foregroundColor: palette.onBackground,
        title: Text(
          state is SongDetailContent
              ? 'Hymn ${state.hymn.hymnNo}: ${state.hymn.title}'
              : 'Song',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (state case SongDetailContent(:final hymn, :final lyricsLines)) ...[
            IconButton(
              tooltip: hymn.isFavorite ? 'Unfavorite' : 'Favorite',
              icon: Icon(
                hymn.isFavorite ? Icons.favorite : Icons.favorite_border,
                color: hymn.isFavorite ? Colors.redAccent : null,
              ),
              onPressed: notifier.toggleFavorite,
            ),
            IconButton(
              tooltip: 'Copy',
              icon: const Icon(Icons.copy),
              onPressed: () async {
                final text = _shareTextFor(hymn);
                await Clipboard.setData(ClipboardData(text: text));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied')),
                );
              },
            ),
            IconButton(
              tooltip: 'Share',
              icon: const Icon(Icons.share),
              onPressed: () {
                SharePlus.instance.share(
                  ShareParams(text: _shareTextFor(hymn)),
                );
              },
            ),
            IconButton(
              tooltip: 'Print',
              icon: const Icon(Icons.print),
              onPressed: () async {
                final doc = await _buildHymnPdf(hymn, lyricsLines);
                await Printing.layoutPdf(
                  onLayout: (_) => doc.save(),
                  name: 'Hymn ${hymn.hymnNo} – ${hymn.title}',
                );
              },
            ),
          ],
          IconButton(
            tooltip: 'Reader settings',
            icon: const Icon(Icons.text_fields),
            onPressed: () => _openReaderSettings(
              context,
              notifier: notifier,
              palette: palette,
            ),
          ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (details) {
          final vx = details.velocity.pixelsPerSecond.dx;
          if (vx <= -350) {
            notifier.navigateToNext();
          } else if (vx >= 350) {
            notifier.navigateToPrevious();
          }
        },
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: switch (state) {
              SongDetailLoading() => const Center(
                  child: CircularProgressIndicator(),
                ),
              SongDetailError(:final message) => _ErrorView(
                  message: message,
                  palette: palette,
                ),
              SongDetailContent() => _ContentView(
                  state: state,
                  palette: palette,
                  onPrev: notifier.navigateToPrevious,
                  onNext: notifier.navigateToNext,
                ),
            },
          ),
        ),
      ),
    );
  }

  static String _shareTextFor(Hymn hymn) {
    return '${hymn.title}\n\n${hymn.lyrics}\n\n\u2014 Only Believe Songs';
  }

  static Future<void> _openReaderSettings(
    BuildContext context, {
    required SongDetailNotifier notifier,
    required _ReaderPalette palette,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: palette.sheetBackground,
      isScrollControlled: true,
      builder: (ctx) {
        return Consumer(
          builder: (ctx, ref, _) {
            final s = ref.watch(songDetailProvider);
            return _ReaderSettingsSheet(
              fontSize: s.fontSize,
              lineHeight: s.lineHeight,
              theme: s.theme,
              onFontSizeChange: notifier.setFontSize,
              onFontSizeIncrease: notifier.increaseFontSize,
              onFontSizeDecrease: notifier.decreaseFontSize,
              onLineHeightChange: notifier.setLineHeight,
              onThemeChange: notifier.setTheme,
              palette: palette,
            );
          },
        );
      },
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.palette,
  });

  final String message;
  final _ReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: palette.error,
        ),
      ),
    );
  }
}

class _ContentView extends StatelessWidget {
  const _ContentView({
    required this.state,
    required this.palette,
    required this.onPrev,
    required this.onNext,
  });

  final SongDetailContent state;
  final _ReaderPalette palette;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final hymn = state.hymn;
    String? _prevName;
    String? _nextName;

    if (state.prevTitle != null) {
      _prevName = _truncateTitle(state.prevTitle!);
    }
    if (state.nextTitle != null) {
      _nextName = _truncateTitle(state.nextTitle!);
    }

    return Column(
      children: [
        const SizedBox(height: 8),
        _SongNavigationBar(
          current: hymn.hymnNo,
          currentTitle: '${hymn.hymnNo}. ${hymn.title}',
          prevTitle: _prevName,
          nextTitle: _nextName,
          prev: state.prevHymnNo,
          next: state.nextHymnNo,
          onPrev: state.prevHymnNo == null ? null : onPrev,
          onNext: state.nextHymnNo == null ? null : onNext,
          palette: palette,
        ),
        Divider(color: palette.divider),
        _SongHeader(
          hymnNo: hymn.hymnNo,
          title: hymn.title,
          chord: hymn.chord,
          palette: palette,
        ),
        const SizedBox(height: 10),
        Expanded(
          child: SelectionArea(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 12),
              itemCount: state.lyricsLines.length,
              itemBuilder: (context, index) {
                final line = state.lyricsLines[index];
                return _LyricsLineView(
                  line: line,
                  fontSize: state.fontSize,
                  lineHeight: state.lineHeight,
                  palette: palette,
                );
              },
            ),
          ),
        ),
        Divider(color: palette.divider),
        _SongNavigationBar(
          current: hymn.hymnNo,
          currentTitle: '${hymn.hymnNo}. ${hymn.title}',
          prevTitle: _prevName,
          nextTitle: _nextName,
          prev: state.prevHymnNo,
          next: state.nextHymnNo,
          onPrev: state.prevHymnNo == null ? null : onPrev,
          onNext: state.nextHymnNo == null ? null : onNext,
          palette: palette,
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}

class _SongNavigationBar extends StatelessWidget {
  const _SongNavigationBar({
    required this.current,
    required this.currentTitle,
    required this.prevTitle,
    required this.nextTitle,
    required this.prev,
    required this.next,
    required this.onPrev,
    required this.onNext,
    required this.palette,
  });

  final int current;
  final String currentTitle;
  final String? prevTitle;
  final String? nextTitle;
  final int? prev;
  final int? next;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final _ReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget sideButton({
      required IconData icon,
      required int? hymnNo,
      required String? title,
      required VoidCallback? onTap,
      required Alignment alignment,
    }) {
      final enabled = hymnNo != null && onTap != null;
       final label = !enabled || title == null ? '' : title;
      return Expanded(
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Align(
              alignment: alignment,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (alignment == Alignment.centerLeft)
                    Icon(
                      icon,
                      color:
                          enabled ? palette.onBackground : palette.onBackgroundMuted,
                    ),
                  if (alignment == Alignment.centerLeft)
                    const SizedBox(width: 6),
                  Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: enabled
                          ? palette.onBackground
                          : palette.onBackgroundMuted,
                    ),
                  ),
                  if (alignment == Alignment.centerRight)
                    const SizedBox(width: 6),
                  if (alignment == Alignment.centerRight)
                    Icon(
                      icon,
                      color:
                          enabled ? palette.onBackground : palette.onBackgroundMuted,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Material(
      color: palette.navBackground,
      borderRadius: BorderRadius.circular(14),
      child: Row(
        children: [
          sideButton(
            icon: Icons.chevron_left,
            hymnNo: prev,
            title: prevTitle,
            onTap: onPrev,
            alignment: Alignment.centerLeft,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              currentTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                color: palette.onBackground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          sideButton(
            icon: Icons.chevron_right,
            hymnNo: next,
            title: nextTitle,
            onTap: onNext,
            alignment: Alignment.centerRight,
          ),
        ],
      ),
    );
  }
}

class _SongHeader extends StatelessWidget {
  const _SongHeader({
    required this.hymnNo,
    required this.title,
    required this.chord,
    required this.palette,
  });

  final int hymnNo;
  final String title;
  final String chord;
  final _ReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Column(
        children: [
          Text(
            'Hymn $hymnNo',
            style: theme.textTheme.labelLarge?.copyWith(
              color: palette.accent,
              letterSpacing: 0.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: palette.onBackground,
              height: 1.1,
            ),
            textAlign: TextAlign.center,
          ),
          if (chord.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: palette.pillBackground,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: palette.pillBorder),
              ),
              child: Text(
                'Key of ${chord.trim()}',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: palette.onBackground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LyricsLineView extends StatelessWidget {
  const _LyricsLineView({
    required this.line,
    required this.fontSize,
    required this.lineHeight,
    required this.palette,
  });

  final LyricsLine line;
  final double fontSize;
  final double lineHeight;
  final _ReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.bodyLarge?.copyWith(
      fontSize: fontSize,
      height: lineHeight,
      color: palette.onBackground,
    );

    return switch (line) {
      LyricsSpacer() => const SizedBox(height: 14),
      LyricsSectionHeader(:final text) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: palette.accent,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                text.toUpperCase(),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: palette.accent,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
        ),
      LyricsChorusLine(:final text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Card(
            color: palette.chorusBackground,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: palette.chorusBorder),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Text(
                text,
                style: baseStyle,
              ),
            ),
          ),
        ),
      LyricsVerseLine(:final text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text(
            text,
            style: baseStyle,
          ),
        ),
    };
  }
}

String _truncateTitle(String title, {int max = 15}) {
  if (title.length <= max) return title;
  return '${title.substring(0, max)}...';
}

Future<pw.Document> _buildHymnPdf(Hymn hymn, List<LyricsLine> lines) async {
  final doc = pw.Document();
  final boldStyle = pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12);
  final normalStyle = const pw.TextStyle(fontSize: 12);
  final italicStyle = pw.TextStyle(fontStyle: pw.FontStyle.italic, fontSize: 12);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 48, vertical: 56),
      build: (pw.Context ctx) {
        return [
          pw.Text(
            'Hymn ${hymn.hymnNo}',
            style: pw.TextStyle(fontSize: 11, color: PdfColors.grey600),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            hymn.title,
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          if (hymn.chord.trim().isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text(
              'Key of ${hymn.chord.trim()}',
              style: pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
            ),
          ],
          pw.SizedBox(height: 18),
          ...lines.map((line) {
            return switch (line) {
              LyricsSpacer() => pw.SizedBox(height: 10),
              LyricsSectionHeader(:final text) => pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 10, bottom: 2),
                  child: pw.Text(text.toUpperCase(), style: boldStyle),
                ),
              LyricsChorusLine(:final text) => pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 18, top: 2, bottom: 2),
                  child: pw.Text(text, style: italicStyle),
                ),
              LyricsVerseLine(:final text) => pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 2, bottom: 2),
                  child: pw.Text(text, style: normalStyle),
                ),
            };
          }),
          pw.SizedBox(height: 24),
          pw.Text(
            '— Only Believe Songs',
            style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic, color: PdfColors.grey600),
          ),
        ];
      },
    ),
  );
  return doc;
}

class _ReaderSettingsSheet extends StatelessWidget {
  const _ReaderSettingsSheet({
    required this.fontSize,
    required this.lineHeight,
    required this.theme,
    required this.onFontSizeChange,
    required this.onFontSizeIncrease,
    required this.onFontSizeDecrease,
    required this.onLineHeightChange,
    required this.onThemeChange,
    required this.palette,
  });

  final double fontSize;
  final double lineHeight;
  final SongReaderTheme theme;
  final ValueChanged<double> onFontSizeChange;
  final VoidCallback onFontSizeIncrease;
  final VoidCallback onFontSizeDecrease;
  final ValueChanged<double> onLineHeightChange;
  final ValueChanged<SongReaderTheme> onThemeChange;
  final _ReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 4,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reader Settings',
            style: t.textTheme.titleLarge?.copyWith(
              color: palette.onSheetBackground,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 18),
          _SettingsRowHeader(
            label: 'Font size',
            value: '${fontSize.toStringAsFixed(0)} sp',
            palette: palette,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _TextSizeButton(
                label: 'A',
                onPressed: onFontSizeDecrease,
                palette: palette,
                isLarge: false,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Slider(
                  value: fontSize,
                  min: 12,
                  max: 32,
                  divisions: 20,
                  onChanged: onFontSizeChange,
                ),
              ),
              const SizedBox(width: 10),
              _TextSizeButton(
                label: 'A',
                onPressed: onFontSizeIncrease,
                palette: palette,
                isLarge: true,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _SettingsRowHeader(
            label: 'Line spacing',
            value: lineHeight.toStringAsFixed(2),
            palette: palette,
          ),
          const SizedBox(height: 8),
          Slider(
            value: lineHeight,
            min: 1.2,
            max: 2.0,
            divisions: 16,
            onChanged: onLineHeightChange,
          ),
          const SizedBox(height: 18),
          _SettingsRowHeader(
            label: 'Theme',
            value: _themeLabel(theme),
            palette: palette,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ThemeChip(
                label: 'Auto',
                isSelected: theme == SongReaderTheme.auto,
                onTap: () => onThemeChange(SongReaderTheme.auto),
                palette: palette,
              ),
              _ThemeChip(
                label: 'Light',
                isSelected: theme == SongReaderTheme.light,
                onTap: () => onThemeChange(SongReaderTheme.light),
                palette: palette,
              ),
              _ThemeChip(
                label: 'Dark',
                isSelected: theme == SongReaderTheme.dark,
                onTap: () => onThemeChange(SongReaderTheme.dark),
                palette: palette,
              ),
              _ThemeChip(
                label: 'Sepia',
                isSelected: theme == SongReaderTheme.sepia,
                onTap: () => onThemeChange(SongReaderTheme.sepia),
                palette: palette,
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  static String _themeLabel(SongReaderTheme theme) {
    return switch (theme) {
      SongReaderTheme.auto => 'Auto',
      SongReaderTheme.light => 'Light',
      SongReaderTheme.dark => 'Dark',
      SongReaderTheme.sepia => 'Sepia',
    };
  }
}

class _SettingsRowHeader extends StatelessWidget {
  const _SettingsRowHeader({
    required this.label,
    required this.value,
    required this.palette,
  });

  final String label;
  final String value;
  final _ReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: t.textTheme.titleMedium?.copyWith(
            color: palette.onSheetBackground,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          value,
          style: t.textTheme.labelLarge?.copyWith(
            color: palette.onSheetBackgroundMuted,
          ),
        ),
      ],
    );
  }
}

class _TextSizeButton extends StatelessWidget {
  const _TextSizeButton({
    required this.label,
    required this.onPressed,
    required this.palette,
    required this.isLarge,
  });

  final String label;
  final VoidCallback onPressed;
  final _ReaderPalette palette;
  final bool isLarge;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return IconButton(
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: palette.chipBackground,
        foregroundColor: palette.onSheetBackground,
      ),
      icon: Text(
        label,
        style: t.textTheme.titleMedium?.copyWith(
          fontSize: isLarge ? 22 : 16,
          fontWeight: FontWeight.w900,
          color: palette.onSheetBackground,
        ),
      ),
    );
  }
}

class _ThemeChip extends StatelessWidget {
  const _ThemeChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.palette,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final _ReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ChoiceChip(
      label: Text(
        label,
        style: t.textTheme.labelLarge?.copyWith(
          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
          color: isSelected ? palette.onChipSelected : palette.onSheetBackground,
        ),
      ),
      selected: isSelected,
      onSelected: (_) => onTap(),
      selectedColor: palette.chipSelectedBackground,
      backgroundColor: palette.chipBackground,
      side: BorderSide(
        color: isSelected ? palette.chipSelectedBorder : palette.chipBorder,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _ReaderPalette {
  const _ReaderPalette({
    required this.background,
    required this.onBackground,
    required this.onBackgroundMuted,
    required this.navBackground,
    required this.pillBackground,
    required this.pillBorder,
    required this.chorusBackground,
    required this.chorusBorder,
    required this.divider,
    required this.accent,
    required this.error,
    required this.sheetBackground,
    required this.onSheetBackground,
    required this.onSheetBackgroundMuted,
    required this.chipBackground,
    required this.chipBorder,
    required this.chipSelectedBackground,
    required this.chipSelectedBorder,
    required this.onChipSelected,
  });

  final Color background;
  final Color onBackground;
  final Color onBackgroundMuted;
  final Color navBackground;
  final Color pillBackground;
  final Color pillBorder;
  final Color chorusBackground;
  final Color chorusBorder;
  final Color divider;
  final Color accent;
  final Color error;

  final Color sheetBackground;
  final Color onSheetBackground;
  final Color onSheetBackgroundMuted;
  final Color chipBackground;
  final Color chipBorder;
  final Color chipSelectedBackground;
  final Color chipSelectedBorder;
  final Color onChipSelected;

  static _ReaderPalette from(ThemeData theme, SongReaderTheme readerTheme) {
    final scheme = theme.colorScheme;

    switch (readerTheme) {
      case SongReaderTheme.auto:
        return _ReaderPalette(
          background: scheme.surface,
          onBackground: scheme.onSurface,
          onBackgroundMuted: scheme.onSurfaceVariant,
          navBackground: scheme.surfaceContainerHighest,
          pillBackground: scheme.surfaceContainerHighest,
          pillBorder: scheme.outlineVariant,
          chorusBackground: scheme.primaryContainer.withValues(alpha: 0.35),
          chorusBorder: scheme.primaryContainer.withValues(alpha: 0.75),
          divider: scheme.outlineVariant,
          accent: scheme.primary,
          error: scheme.error,
          sheetBackground: scheme.surface,
          onSheetBackground: scheme.onSurface,
          onSheetBackgroundMuted: scheme.onSurfaceVariant,
          chipBackground: scheme.surfaceContainerHighest,
          chipBorder: scheme.outlineVariant,
          chipSelectedBackground: scheme.primaryContainer,
          chipSelectedBorder: scheme.primary,
          onChipSelected: scheme.onPrimaryContainer,
        );
      case SongReaderTheme.light:
        const bg = Color(0xFFF9FAFB);
        const onBg = Color(0xFF0B0C0F);
        const muted = Color(0xFF505A66);
        return _ReaderPalette(
          background: bg,
          onBackground: onBg,
          onBackgroundMuted: muted,
          navBackground: const Color(0xFFEFF2F6),
          pillBackground: const Color(0xFFEFF2F6),
          pillBorder: const Color(0xFFD5DCE5),
          chorusBackground: const Color(0xFFE3EFFB),
          chorusBorder: const Color(0xFFBFD7F1),
          divider: const Color(0xFFD5DCE5),
          accent: const Color(0xFF1C6BC9),
          error: const Color(0xFFB3261E),
          sheetBackground: Colors.white,
          onSheetBackground: onBg,
          onSheetBackgroundMuted: muted,
          chipBackground: const Color(0xFFEFF2F6),
          chipBorder: const Color(0xFFD5DCE5),
          chipSelectedBackground: const Color(0xFF1C6BC9),
          chipSelectedBorder: const Color(0xFF15539B),
          onChipSelected: Colors.white,
        );
      case SongReaderTheme.dark:
        const bg = Color(0xFF0F1115);
        const onBg = Color(0xFFE9EDF4);
        const muted = Color(0xFF9AA5B1);
        return _ReaderPalette(
          background: bg,
          onBackground: onBg,
          onBackgroundMuted: muted,
          navBackground: const Color(0xFF171A21),
          pillBackground: const Color(0xFF171A21),
          pillBorder: const Color(0xFF2A3140),
          chorusBackground: const Color(0xFF1E2B3A),
          chorusBorder: const Color(0xFF2C4360),
          divider: const Color(0xFF2A3140),
          accent: const Color(0xFF7AB6FF),
          error: const Color(0xFFFFB4AB),
          sheetBackground: const Color(0xFF0F1115),
          onSheetBackground: onBg,
          onSheetBackgroundMuted: muted,
          chipBackground: const Color(0xFF171A21),
          chipBorder: const Color(0xFF2A3140),
          chipSelectedBackground: const Color(0xFF7AB6FF),
          chipSelectedBorder: const Color(0xFF5B9BE5),
          onChipSelected: const Color(0xFF081018),
        );
      case SongReaderTheme.sepia:
        const bg = Color(0xFFF4ECD8);
        const onBg = Color(0xFF2E241B);
        const muted = Color(0xFF6B5744);
        return _ReaderPalette(
          background: bg,
          onBackground: onBg,
          onBackgroundMuted: muted,
          navBackground: const Color(0xFFE9DDBF),
          pillBackground: const Color(0xFFE9DDBF),
          pillBorder: const Color(0xFFD6C7A3),
          chorusBackground: const Color(0xFFE3D1AE),
          chorusBorder: const Color(0xFFD1B98A),
          divider: const Color(0xFFD6C7A3),
          accent: const Color(0xFF8E5B2A),
          error: const Color(0xFF8B0000),
          sheetBackground: const Color(0xFFF4ECD8),
          onSheetBackground: onBg,
          onSheetBackgroundMuted: muted,
          chipBackground: const Color(0xFFE9DDBF),
          chipBorder: const Color(0xFFD6C7A3),
          chipSelectedBackground: const Color(0xFF8E5B2A),
          chipSelectedBorder: const Color(0xFF6F441C),
          onChipSelected: const Color(0xFFFFF6E7),
        );
    }
  }
}
