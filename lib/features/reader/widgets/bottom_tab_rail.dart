import 'package:flutter/material.dart';

import '../models/reader_tab.dart';

class BottomTabRail extends StatelessWidget {
  final List<ReaderTab> tabs;
  final int activeIndex;
  final ValueChanged<int> onTapTab;
  final ValueChanged<int> onCloseTab;
  final VoidCallback onOpenNew;

  const BottomTabRail({
    super.key,
    required this.tabs,
    required this.activeIndex,
    required this.onTapTab,
    required this.onCloseTab,
    required this.onOpenNew,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 0,
      color: theme.colorScheme.surface,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: theme.colorScheme.outlineVariant.withAlpha(80),
            ),
          ),
        ),
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              Expanded(
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: tabs.length,
                  itemBuilder: (context, index) {
                    final tab = tabs[index];
                    final isActive = index == activeIndex;
                    final label = tab.type == ReaderContentType.bible
                        ? '${tab.book ?? ''} ${tab.chapter ?? ''}'.trim()
                        : tab.title;
                    return GestureDetector(
                      onTap: () => onTapTab(index),
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 6,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: isActive
                              ? theme.colorScheme.primaryContainer
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isActive
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outline.withAlpha(80),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _dotColor(tab),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _short(label),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isActive
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isActive
                                    ? theme.colorScheme.onPrimaryContainer
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () => onCloseTab(index),
                              child: Icon(
                                Icons.close,
                                size: 16,
                                color: isActive
                                    ? theme.colorScheme.onPrimaryContainer
                                    : theme.colorScheme.onSurface.withAlpha(150),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: IconButton(
                  onPressed: onOpenNew,
                  icon: const Icon(Icons.add, size: 20),
                  tooltip: 'Open new tab',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _short(String value) {
    if (value.length > 18) return '${value.substring(0, 15)}...';
    return value;
  }

  Color _dotColor(ReaderTab tab) {
    if (tab.type == ReaderContentType.bible) {
      return (tab.bibleLang ?? 'en') == 'ta' ? Colors.green : Colors.blue;
    }
    return (tab.sermonLang ?? 'en') == 'ta' ? Colors.deepPurple : Colors.orange;
  }
}
