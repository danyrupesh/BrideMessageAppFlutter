import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../reader/providers/reader_provider.dart';
import '../../sermons/providers/sermon_provider.dart';

enum _SectionDest {
  bibleEn,
  bibleTa,
  sermonEn,
  sermonTa,
  search,
  songs,
  codEn,
  codTa,
  sealsEn,
  sealsTa,
  tractsEn,
  tractsTa,
  storiesEn,
  storiesTa,
}

class _SectionItem {
  final _SectionDest dest;
  final String title;
  final String subtitle;
  final IconData icon;
  final String group;

  const _SectionItem({
    required this.dest,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.group,
  });
}

const List<_SectionItem> _sectionItems = [
  _SectionItem(
    dest: _SectionDest.bibleEn,
    title: 'Bible EN',
    subtitle: 'English Bible (KJV)',
    icon: Icons.menu_book_outlined,
    group: 'Bible',
  ),
  _SectionItem(
    dest: _SectionDest.bibleTa,
    title: 'Bible TA',
    subtitle: 'Tamil Bible (BSI)',
    icon: Icons.menu_book_outlined,
    group: 'Bible',
  ),
  _SectionItem(
    dest: _SectionDest.sermonEn,
    title: 'Sermon EN',
    subtitle: 'English sermons (Resume)',
    icon: Icons.headphones_outlined,
    group: 'Sermons',
  ),
  _SectionItem(
    dest: _SectionDest.sermonTa,
    title: 'Sermon TA',
    subtitle: 'Tamil sermons',
    icon: Icons.headphones_outlined,
    group: 'Sermons',
  ),
  _SectionItem(
    dest: _SectionDest.search,
    title: 'Search',
    subtitle: 'Bible & Sermons',
    icon: Icons.search,
    group: 'Other',
  ),
  _SectionItem(
    dest: _SectionDest.songs,
    title: 'Songs',
    subtitle: 'Only Believe Songs',
    icon: Icons.music_note_outlined,
    group: 'Other',
  ),
  _SectionItem(
    dest: _SectionDest.codEn,
    title: 'COD EN',
    subtitle: 'Question and Answers (English)',
    icon: Icons.article_outlined,
    group: 'Other',
  ),
  _SectionItem(
    dest: _SectionDest.codTa,
    title: 'COD TA',
    subtitle: 'Question and Answers (Tamil)',
    icon: Icons.article_outlined,
    group: 'Other',
  ),
  _SectionItem(
    dest: _SectionDest.sealsEn,
    title: '7 Seals EN',
    subtitle: 'Seven Seals (English)',
    icon: Icons.layers_outlined,
    group: 'Other',
  ),
  _SectionItem(
    dest: _SectionDest.sealsTa,
    title: '7 Seals TA',
    subtitle: 'Seven Seals (Tamil)',
    icon: Icons.layers_outlined,
    group: 'Other',
  ),
  _SectionItem(
    dest: _SectionDest.tractsEn,
    title: 'Tracts EN',
    subtitle: 'English Tracts',
    icon: Icons.article,
    group: 'Tracts & Stories',
  ),
  _SectionItem(
    dest: _SectionDest.tractsTa,
    title: 'Tracts TA',
    subtitle: 'Tamil Tracts',
    icon: Icons.article,
    group: 'Tracts & Stories',
  ),
  _SectionItem(
    dest: _SectionDest.storiesEn,
    title: 'Stories EN',
    subtitle: 'Stories (English)',
    icon: Icons.auto_stories_outlined,
    group: 'Tracts & Stories',
  ),
  _SectionItem(
    dest: _SectionDest.storiesTa,
    title: 'Stories TA',
    subtitle: 'Stories (Tamil)',
    icon: Icons.auto_stories_outlined,
    group: 'Tracts & Stories',
  ),
];

class SectionMenuButton extends ConsumerWidget {
  const SectionMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: 'Sections',
      icon: const Icon(Icons.more_vert),
      onPressed: () async {
        final dest = await showDialog<_SectionDest>(
          context: context,
          barrierDismissible: true,
          builder: (dialogContext) => _SectionsDialog(items: _sectionItems),
        );
        if (!context.mounted || dest == null) return;
        _handleSelected(context, ref, dest);
      },
    );
  }

  void _handleSelected(BuildContext context, WidgetRef ref, _SectionDest dest) {
    switch (dest) {
      case _SectionDest.bibleEn:
        ref.read(selectedBibleLangProvider.notifier).setLang('en');
        if (GoRouterState.of(context).matchedLocation != '/reader') {
          context.push('/reader');
        }
        return;
      case _SectionDest.bibleTa:
        ref.read(selectedBibleLangProvider.notifier).setLang('ta');
        if (GoRouterState.of(context).matchedLocation != '/reader') {
          context.push('/reader');
        }
        return;
      case _SectionDest.sermonEn:
        ref.read(selectedSermonLangProvider.notifier).setLang('en');
        context.push('/sermons?resume=1');
        return;
      case _SectionDest.sermonTa:
        ref.read(selectedSermonLangProvider.notifier).setLang('ta');
        context.push('/sermons');
        return;
      case _SectionDest.search:
        context.push('/search?fresh=1');
        return;
      case _SectionDest.songs:
        context.push('/songs');
        return;
      case _SectionDest.codEn:
        context.push('/cod?lang=en');
        return;
      case _SectionDest.codTa:
        context.push('/cod?lang=ta');
        return;
      case _SectionDest.sealsEn:
        ref.read(selectedSermonLangProvider.notifier).setLang('en');
        context.push(
          Uri(
            path: '/sermons',
            queryParameters: const {
              'mode': 'sevenSeals',
              'title': '7 Seals',
              'lang': 'en',
            },
          ).toString(),
        );
        return;
      case _SectionDest.sealsTa:
        ref.read(selectedSermonLangProvider.notifier).setLang('ta');
        context.push(
          Uri(
            path: '/sermons',
            queryParameters: const {
              'mode': 'sevenSeals',
              'title': 'ஏழு முத்திரைகள்',
              'lang': 'ta',
            },
          ).toString(),
        );
        return;
      case _SectionDest.tractsEn:
        context.push('/tracts?lang=en');
        return;
      case _SectionDest.tractsTa:
        context.push('/tracts?lang=ta');
        return;
      case _SectionDest.storiesEn:
        context.push('/stories?lang=en');
        return;
      case _SectionDest.storiesTa:
        context.push('/stories?lang=ta');
        return;
    }
  }
}

class _SectionsDialog extends StatefulWidget {
  final List<_SectionItem> items;

  const _SectionsDialog({required this.items});

  @override
  State<_SectionsDialog> createState() => _SectionsDialogState();
}

class _SectionsDialogState extends State<_SectionsDialog> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final next = _controller.text;
      if (next == _query) return;
      setState(() => _query = next);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final dialogWidth = (size.width - 64).clamp(280.0, 420.0);
    final dialogHeight = (size.height * 0.75).clamp(320.0, 640.0);

    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.items
        : widget.items
              .where((it) {
                final hay = '${it.title}\n${it.subtitle}'.toLowerCase();
                return hay.contains(q);
              })
              .toList(growable: false);

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: size.width >= 700,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Search sections',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _query.trim().isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear',
                                icon: const Icon(Icons.clear),
                                onPressed: () => _controller.clear(),
                              ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Material(
                color: theme.colorScheme.surface,
                child: _buildList(context, filtered, groupHeaders: q.isEmpty),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    List<_SectionItem> items, {
    required bool groupHeaders,
  }) {
    if (items.isEmpty) {
      return const Center(child: Text('No matches'));
    }

    if (!groupHeaders) {
      return ListView.separated(
        padding: const EdgeInsets.only(bottom: 8),
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) => _buildTile(context, items[index]),
      );
    }

    const groupsInOrder = ['Bible', 'Sermons', 'Other', 'Tracts & Stories'];
    final byGroup = <String, List<_SectionItem>>{};
    for (final it in items) {
      (byGroup[it.group] ??= []).add(it);
    }

    final children = <Widget>[];
    for (final group in groupsInOrder) {
      final groupItems = byGroup[group];
      if (groupItems == null || groupItems.isEmpty) continue;
      children.add(_GroupHeader(label: group));
      for (final it in groupItems) {
        children.add(_buildTile(context, it));
      }
      children.add(const Divider(height: 1));
    }

    // Remove trailing divider for a cleaner look.
    if (children.isNotEmpty && children.last is Divider) {
      children.removeLast();
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: children,
    );
  }

  Widget _buildTile(BuildContext context, _SectionItem item) {
    return ListTile(
      dense: true,
      leading: Icon(item.icon),
      title: Text(item.title),
      subtitle: Text(item.subtitle),
      onTap: () => Navigator.of(context).pop(item.dest),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String label;

  const _GroupHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}
