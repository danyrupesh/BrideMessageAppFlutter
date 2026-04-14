import 'package:flutter/material.dart';

import '../models/reader_tab.dart';

class PaneHeader extends StatelessWidget {
  final ReaderTab tab;
  final bool isPrimary;
  final bool showClose;
  final bool isSearchActive;
  final double displayFontSize;
  final VoidCallback? onOpenPicker;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback? onDecreaseFont;
  final VoidCallback? onIncreaseFont;
  final VoidCallback? onToggleSearch;
  final VoidCallback? onClose;
  final ValueChanged<String>? onSourceSelected;

  const PaneHeader({
    super.key,
    required this.tab,
    required this.isPrimary,
    this.showClose = false,
    this.isSearchActive = false,
    required this.displayFontSize,
    this.onOpenPicker,
    this.onPrev,
    this.onNext,
    this.onDecreaseFont,
    this.onIncreaseFont,
    this.onToggleSearch,
    this.onClose,
    this.onSourceSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final navLabelStyle = theme.textTheme.labelSmall?.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );
    final sourceLabel = _sourceLabel(tab);
    final paneTitle = _paneTitle(tab);
    final pickerLabel = tab.type == ReaderContentType.bible
        ? 'All Books'
        : 'All Sermons';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      constraints: const BoxConstraints(minHeight: 56),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withAlpha(90)),
          bottom: BorderSide(color: cs.outlineVariant.withAlpha(120)),
        ),
      ),
      child: Row(
        children: [
          PopupMenuButton<String>(
            tooltip: 'Choose source',
            onSelected: onSourceSelected,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'bible_ta',
                child: Text('Tamil Bible (BSI)'),
              ),
              PopupMenuItem(
                value: 'bible_en',
                child: Text('English Bible (KJV)'),
              ),
              PopupMenuItem(
                value: 'sermon_ta',
                child: Text('Tamil Sermon (COD Tamil)'),
              ),
              PopupMenuItem(
                value: 'sermon_en',
                child: Text('English Sermon (COD English)'),
              ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _sourceColor(tab),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(sourceLabel, style: theme.textTheme.labelMedium),
                  const Icon(Icons.arrow_drop_down, size: 18),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          TextButton.icon(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: onOpenPicker,
            icon: const Icon(Icons.menu_book_outlined, size: 16),
            label: Text(pickerLabel),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Align(
                alignment: Alignment.centerRight,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                        ),
                        onPressed: onPrev,
                        icon: const Icon(Icons.chevron_left, size: 18),
                        label: Text(
                          'Previous',
                          style: navLabelStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 170,
                        child: Text(
                          paneTitle,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                        ),
                        onPressed: onNext,
                        iconAlignment: IconAlignment.end,
                        icon: const Icon(Icons.chevron_right, size: 18),
                        label: Text(
                          'Next',
                          style: navLabelStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Decrease text size',
            visualDensity: VisualDensity.compact,
            icon: const Text(
              'A-',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            onPressed: onDecreaseFont,
          ),
          Text(
            displayFontSize.toStringAsFixed(0),
            style: theme.textTheme.labelMedium,
          ),
          IconButton(
            tooltip: 'Increase text size',
            visualDensity: VisualDensity.compact,
            icon: const Text(
              'A+',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            onPressed: onIncreaseFont,
          ),
          IconButton(
            tooltip: isSearchActive ? 'Close mini search' : 'Open mini search',
            visualDensity: VisualDensity.compact,
            onPressed: onToggleSearch,
            icon: Icon(isSearchActive ? Icons.search_off : Icons.search),
          ),
          if (showClose)
            IconButton(
              tooltip: 'Close pane',
              visualDensity: VisualDensity.compact,
              onPressed: onClose,
              icon: const Icon(Icons.close),
            ),
        ],
      ),
    );
  }

  Color _sourceColor(ReaderTab value) {
    if (value.type == ReaderContentType.bible) {
      return (value.bibleLang ?? 'en') == 'ta' ? Colors.green : Colors.blue;
    }
    return (value.sermonLang ?? 'en') == 'ta'
        ? Colors.deepPurple
        : Colors.orange;
  }

  String _sourceLabel(ReaderTab value) {
    if (value.type == ReaderContentType.bible) {
      return (value.bibleLang ?? 'en') == 'ta'
          ? 'Tamil Bible'
          : 'English Bible';
    }
    return (value.sermonLang ?? 'en') == 'ta'
        ? 'Tamil Sermon'
        : 'English Sermon';
  }

  String _paneTitle(ReaderTab value) {
    if (value.type == ReaderContentType.bible) {
      return '${value.book ?? ''} ${value.chapter ?? ''}'.trim();
    }
    return value.title;
  }
}
