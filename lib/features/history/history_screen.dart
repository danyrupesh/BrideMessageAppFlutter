import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Placeholder static items; later wire to a repository.
    final sermonItems = [
      (
        title: 'Faith Is The Substance',
        subtitle: '47-0412 • Sermon',
        when: '8 minutes ago',
        language: 'English',
      ),
      (
        title: 'The Angel Of The Lord',
        subtitle: '47-0514 • Sermon',
        when: 'Yesterday',
        language: 'English',
      ),
    ];

    final bibleItems = [
      (
        title: 'Genesis 11',
        subtitle: 'Bible',
        when: 'Today',
        language: 'English',
      ),
      (
        title: 'John 3',
        subtitle: 'Bible',
        when: 'Last week',
        language: 'English',
      ),
    ];

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
          title: const Text('Reading History'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Sermons'),
              Tab(text: 'Bible'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _HistoryList(
              items: sermonItems,
              theme: theme,
            ),
            _HistoryList(
              items: bibleItems,
              theme: theme,
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  final List<({
    String title,
    String subtitle,
    String when,
    String language,
  })> items;
  final ThemeData theme;

  const _HistoryList({
    required this.items,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          leading: const Icon(Icons.history),
          title: Text(item.title),
          subtitle: Text('${item.subtitle} • ${item.when}'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  item.language,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () {
                  // TODO: Implement delete single history item.
                },
              ),
            ],
          ),
          onTap: () {
            // TODO: Navigate to the corresponding sermon or Bible reference.
          },
        );
      },
    );
  }
}

