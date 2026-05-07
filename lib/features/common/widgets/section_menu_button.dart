import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../reader/providers/reader_provider.dart';
import '../../sermons/providers/sermon_provider.dart';

enum _SectionDest {
  bible,
  sermon,
  search,
  songs,
  cod,
  seals,
  tracts,
  stories,
  churchAges,
  prayerQuotes,
  quotes,
}

class _SectionItem {
  final _SectionDest dest;
  final String title;
  final String subtitle;
  final IconData icon;
  final String group;
  final String? lang;

  const _SectionItem({
    required this.dest,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.group,
    this.lang,
  });
}

const List<_SectionItem> _sectionItems = [
  _SectionItem(
    dest: _SectionDest.bible,
    title: 'Bible',
    subtitle: 'English / Tamil',
    icon: Icons.menu_book_outlined,
    group: 'Bible',
  ),
  _SectionItem(
    dest: _SectionDest.sermon,
    title: 'Sermons',
    subtitle: 'English / Tamil sermons',
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
    subtitle: 'English / Tamil Songs',
    icon: Icons.music_note_outlined,
    group: 'Other',
  ),
  _SectionItem(
    dest: _SectionDest.cod,
    title: 'COD',
    subtitle: 'Question and Answers',
    icon: Icons.article_outlined,
    group: 'Other',
  ),
  _SectionItem(
    dest: _SectionDest.seals,
    title: '7 Seals',
    subtitle: 'Seven Seals',
    icon: Icons.layers_outlined,
    group: 'Other',
  ),
  _SectionItem(
    dest: _SectionDest.tracts,
    title: 'Tracts',
    subtitle: 'English / Tamil Tracts',
    icon: Icons.article,
    group: 'Tracts & Stories',
  ),
  _SectionItem(
    dest: _SectionDest.stories,
    title: 'Stories',
    subtitle: 'English / Tamil Stories',
    icon: Icons.auto_stories_outlined,
    group: 'Tracts & Stories',
  ),
  _SectionItem(
    dest: _SectionDest.churchAges,
    title: 'Church Ages',
    subtitle: 'The 7 Church Ages',
    icon: Icons.church_outlined,
    group: 'Other',
  ),
  _SectionItem(
    dest: _SectionDest.prayerQuotes,
    title: 'Prayer Quotes',
    subtitle: 'Inspirational Prayers',
    icon: Icons.format_quote_rounded,
    group: 'Other',
  ),
  _SectionItem(
    dest: _SectionDest.quotes,
    title: 'English Quotes',
    subtitle: 'A-Z · Topics · VGR',
    icon: Icons.format_quote_outlined,
    group: 'Other',
    lang: 'en',
  ),
];

/// Opens the homepage-style section picker (same as ⋮ Sections elsewhere).
Future<void> openAppSectionsDialog(BuildContext context, WidgetRef ref) async {
  final selectedLang = ref.read(selectedSermonLangProvider);
  final selection = await showDialog<({String lang, _SectionDest dest})>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) =>
        _SectionsDialog(items: _sectionItems, initialLang: selectedLang),
  );
  if (!context.mounted || selection == null) return;
  _applyAppSectionDestination(context, ref, selection.dest, selection.lang);
}

void _applyAppSectionDestination(
  BuildContext context,
  WidgetRef ref,
  _SectionDest dest,
  String selectedLang,
) {
  switch (dest) {
    case _SectionDest.bible:
      ref.read(selectedBibleLangProvider.notifier).setLang(selectedLang);
      if (GoRouterState.of(context).matchedLocation != '/reader') {
        context.push('/reader');
      }
      return;
    case _SectionDest.sermon:
      ref.read(selectedSermonLangProvider.notifier).setLang(selectedLang);
      context.push(selectedLang == 'en' ? '/sermons?resume=1' : '/sermons');
      return;
    case _SectionDest.search:
      context.push('/search?fresh=1');
      return;
    case _SectionDest.songs:
      context.push(selectedLang == 'ta' ? '/songs/tamil' : '/songs');
      return;
    case _SectionDest.cod:
      context.push('/cod?lang=$selectedLang');
      return;
    case _SectionDest.seals:
      ref.read(selectedSermonLangProvider.notifier).setLang(selectedLang);
      context.push(
        Uri(
          path: '/sermons',
          queryParameters: {
            'mode': 'sevenSeals',
            'title': selectedLang == 'ta' ? 'ஏழு முத்திரைகள்' : '7 Seals',
            'lang': selectedLang,
          },
        ).toString(),
      );
      return;
    case _SectionDest.tracts:
      context.push('/tracts?lang=$selectedLang');
      return;
    case _SectionDest.stories:
      context.push('/stories?lang=$selectedLang');
      return;
    case _SectionDest.churchAges:
      context.push('/church-ages?lang=$selectedLang');
      return;
    case _SectionDest.prayerQuotes:
      context.push('/prayer-quotes');
      return;
    case _SectionDest.quotes:
      context.push('/quotes');
      return;
  }
}

class SectionMenuButton extends ConsumerWidget {
  const SectionMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: 'Sections',
      icon: const Icon(Icons.more_vert),
      onPressed: () => openAppSectionsDialog(context, ref),
    );
  }
}

class _SectionsDialog extends ConsumerStatefulWidget {
  final List<_SectionItem> items;
  final String initialLang;

  const _SectionsDialog({required this.items, required this.initialLang});

  @override
  ConsumerState<_SectionsDialog> createState() => _SectionsDialogState();
}

class _SectionsDialogState extends ConsumerState<_SectionsDialog> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';
  late String _selectedLang;

  @override
  void initState() {
    super.initState();
    _selectedLang = widget.initialLang == 'ta' ? 'ta' : 'en';
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
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final padding = MediaQuery.paddingOf(context);
    // Dialog.insetPadding is 16 on all sides → 32px vertical; keep bottom from clipping.
    const dialogVerticalInset = 32.0;
    final maxDialogHeight = (size.height -
            viewInsets.bottom -
            padding.top -
            padding.bottom -
            dialogVerticalInset)
        .clamp(200.0, size.height);
    final dialogWidth = (size.width - 48).clamp(320.0, 460.0);
    final proposedHeight = size.height * 0.82;
    final dialogHeight = (proposedHeight < maxDialogHeight
            ? proposedHeight
            : maxDialogHeight)
        .clamp(200.0, maxDialogHeight);

    final q = _query.trim().toLowerCase();
    final langFiltered = widget.items
        .where((it) => it.lang == null || it.lang == _selectedLang)
        .toList(growable: false);
    final filtered = q.isEmpty
        ? langFiltered
        : langFiltered
              .where((it) {
                final hay = '${it.title}\n${it.subtitle}'.toLowerCase();
                return hay.contains(q);
              })
              .toList(growable: false);

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
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
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment<String>(
                        value: 'en',
                        label: Text(
                          'EN',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      ButtonSegment<String>(
                        value: 'ta',
                        label: Text(
                          'TA',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                    selected: {_selectedLang},
                    onSelectionChanged: (selection) {
                      setState(() => _selectedLang = selection.first);
                    },
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 4),
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
                clipBehavior: Clip.hardEdge,
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
        padding: const EdgeInsets.only(bottom: 20),
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
      padding: const EdgeInsets.only(bottom: 20),
      children: children,
    );
  }

  Widget _buildTile(BuildContext context, _SectionItem item) {
    return ListTile(
      dense: true,
      leading: Icon(item.icon),
      title: Text(item.title),
      subtitle: Text(item.subtitle),
      onTap: () =>
          Navigator.of(context).pop((lang: _selectedLang, dest: item.dest)),
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
