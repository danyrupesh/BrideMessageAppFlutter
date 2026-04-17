import 'package:flutter/material.dart';

import '../models/reader_tab.dart';

class PaneHeader extends StatelessWidget {
  final VoidCallback? onDisableSplitView;
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
  final bool showSourcePicker;

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
    this.showSourcePicker = true,
    this.onDisableSplitView,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    final navLabelSize = isWide ? 14.5 : 12.0;
    final navLabelStyle = theme.textTheme.labelSmall?.copyWith(
      fontSize: navLabelSize,
      fontWeight: FontWeight.w700,
    );
    final sourceLabel = _sourceLabel(tab);
    final pickerLabel = tab.type == ReaderContentType.bible
        ? 'All Books'
        : 'All Sermons';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      constraints: BoxConstraints(minHeight: isWide ? 64 : 56),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withAlpha(90)),
          bottom: BorderSide(color: cs.outlineVariant.withAlpha(120)),
        ),
      ),
      child: Row(
        children: [
          if (showSourcePicker) ...[
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
                  child: Text('Tamil Sermons'),
                ),
                PopupMenuItem(
                  value: 'sermon_en',
                  child: Text('English Sermons'),
                ),
              ],
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isWide ? 14 : 10,
                  vertical: isWide ? 8 : 6,
                ),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: isWide ? 10 : 8,
                      height: isWide ? 10 : 8,
                      decoration: BoxDecoration(
                        color: _sourceColor(tab),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      sourceLabel,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: isWide ? 15 : 13,
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down, size: 20),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          TextButton.icon(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            onPressed: onOpenPicker,
            icon: Icon(Icons.menu_book_outlined, size: isWide ? 20 : 16),
            label: Text(
              pickerLabel,
              style: TextStyle(
                fontSize: isWide ? 15 : 13,
                fontWeight: FontWeight.w600,
              ),
            ),
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
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: onPrev,
                        icon: Icon(Icons.chevron_left, size: isWide ? 22 : 18),
                        label: Text(
                          'Previous',
                          style: navLabelStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                        ),
                      ),
                      const SizedBox(width: 12),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: onNext,
                        iconAlignment: IconAlignment.end,
                        icon: Icon(Icons.chevron_right, size: isWide ? 22 : 18),
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
            icon: Text(
              'A-',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: isWide ? 16 : 14,
              ),
            ),
            onPressed: onDecreaseFont,
          ),
          Text(
            displayFontSize.toStringAsFixed(0),
            style: theme.textTheme.labelMedium?.copyWith(
              fontSize: isWide ? 15 : 13,
            ),
          ),
          IconButton(
            tooltip: 'Increase text size',
            visualDensity: VisualDensity.compact,
            icon: Text(
              'A+',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: isWide ? 16 : 14,
              ),
            ),
            onPressed: onIncreaseFont,
          ),
          IconButton(
            tooltip: isSearchActive ? 'Close mini search' : 'Open mini search',
            visualDensity: VisualDensity.compact,
            onPressed: onToggleSearch,
            icon: Icon(
              isSearchActive ? Icons.search_off : Icons.search,
              size: isWide ? 24 : 20,
            ),
          ),
          if (showClose)
            IconButton(
              tooltip: 'Close pane',
              visualDensity: VisualDensity.compact,
              onPressed: onClose,
              icon: Icon(Icons.close, size: isWide ? 24 : 20),
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

}
