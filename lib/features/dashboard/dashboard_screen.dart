import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../settings/widgets/theme_picker_sheet.dart';
import '../help/widgets/help_button.dart';
import '../reader/providers/reader_provider.dart';
import '../reader/models/reader_tab.dart';
import '../sermons/providers/sermon_flow_provider.dart';
import '../sermons/providers/sermon_provider.dart';
import '../reading_state/providers/reading_state_provider.dart';
import '../reading_state/models/reading_flow_models.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 80,
            title: const Text(
              'Bride Message App',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            actions: [
              IconButton(
                tooltip: 'Recent viewed',
                icon: const Icon(Icons.history),
                onPressed: () => _showRecentReadsSheet(context, ref),
              ),
              IconButton(
                icon: const Icon(Icons.color_lens),
                onPressed: () => ThemePickerSheet.show(context),
              ),
              const HelpButton(topicId: 'dashboard'),
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () => context.push('/settings'),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.8, -0.6),
                    radius: 1.5,
                    colors: [
                      theme.colorScheme.primaryContainer.withValues(
                        alpha: isDark ? 0.3 : 0.8,
                      ),
                      theme.colorScheme.surface,
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16.0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const Text(
                  'Modules',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                // const SizedBox(height: 16),
                _buildModulesGrid(context, ref),
                const SizedBox(height: 32),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildContinueReadingSection(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<RecentReadItem>> recentReadsAsync,
  ) {
    return recentReadsAsync.when(
      data: (items) {
        final bibleItem = _latestItemFor(items, FlowType.bible);
        final sermonItem = _latestItemFor(items, FlowType.sermon);
        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final isWide = width >= 700;
            // Give mobile cards a bit more vertical room so long
            // titles/subtitles (especially Tamil) don't overflow.
            final cardHeight = isWide ? 160.0 : 210.0;
            final gap = isWide ? 16.0 : 12.0;

            final children = [
              Expanded(
                child: _buildContinueReadingCard(
                  context: context,
                  ref: ref,
                  title: bibleItem?.title ?? 'Bible Reading',
                  subtitle: bibleItem?.subtitle ?? 'Resume your Bible reading.',
                  label: 'CONTINUE BIBLE',
                  icon: Icons.menu_book,
                  flowType: FlowType.bible,
                  item: bibleItem,
                  height: cardHeight,
                ),
              ),
              SizedBox(width: gap, height: gap),
              Expanded(
                child: _buildContinueReadingCard(
                  context: context,
                  ref: ref,
                  title: sermonItem?.title ?? 'Sermon Reading',
                  subtitle: sermonItem?.subtitle ?? 'Resume your last sermon.',
                  label: 'CONTINUE SERMON',
                  icon: Icons.headphones,
                  flowType: FlowType.sermon,
                  item: sermonItem,
                  height: cardHeight,
                ),
              ),
            ];

            return isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: children,
                  )
                : Column(
                    children: [
                      SizedBox(
                        height: cardHeight,
                        child: _buildContinueReadingCard(
                          context: context,
                          ref: ref,
                          title: bibleItem?.title ?? 'Bible Reading',
                          subtitle:
                              bibleItem?.subtitle ??
                              'Resume your Bible reading.',
                          label: 'CONTINUE BIBLE',
                          icon: Icons.menu_book,
                          flowType: FlowType.bible,
                          item: bibleItem,
                          height: cardHeight,
                        ),
                      ),
                      SizedBox(height: gap),
                      SizedBox(
                        height: cardHeight,
                        child: _buildContinueReadingCard(
                          context: context,
                          ref: ref,
                          title: sermonItem?.title ?? 'Sermon Reading',
                          subtitle:
                              sermonItem?.subtitle ??
                              'Resume your last sermon.',
                          label: 'CONTINUE SERMON',
                          icon: Icons.headphones,
                          flowType: FlowType.sermon,
                          item: sermonItem,
                          height: cardHeight,
                        ),
                      ),
                    ],
                  );
          },
        );
      },
      loading: () => const SizedBox(
        height: 180,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => _buildContinueReadingError(context),
    );
  }

  RecentReadItem? _latestItemFor(
    List<RecentReadItem> items,
    FlowType flowType,
  ) {
    final filtered = items.where((item) => item.flowType == flowType).toList();
    if (filtered.isEmpty) return null;
    filtered.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return filtered.first;
  }

  Widget _buildContinueReadingError(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        height: 160,
        child: Center(
          child: Text(
            'Unable to load recent reading.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContinueReadingCard({
    required BuildContext context,
    required WidgetRef ref,
    required String title,
    required String subtitle,
    required String label,
    required IconData icon,
    required FlowType flowType,
    required RecentReadItem? item,
    required double height,
  }) {
    final theme = Theme.of(context);
    final hasItem = item != null;

    return Card(
      elevation: 4,
      shadowColor: theme.colorScheme.primary.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.primary.withValues(alpha: 0.8),
              theme.colorScheme.primary,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        height: height,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.onPrimary, size: 20),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: theme.colorScheme.onPrimary.withValues(alpha: 0.8),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                color: theme.colorScheme.onPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                color: theme.colorScheme.onPrimary.withValues(alpha: 0.9),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                if (hasItem) {
                  if (flowType == FlowType.bible) {
                    ref
                        .read(readerProvider.notifier)
                        .restoreSession(item.snapshot);
                    context.push('/reader');
                  } else {
                    ref
                        .read(sermonFlowProvider.notifier)
                        .restoreSession(item.snapshot);
                    context.push('/sermon-reader');
                  }
                  return;
                }

                if (flowType == FlowType.bible) {
                  context.push('/reader');
                } else {
                  context.push('/sermons');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.onPrimary,
                foregroundColor: theme.colorScheme.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                minimumSize: const Size(0, 32),
                visualDensity: VisualDensity.compact,
              ),
              child: Text(hasItem ? 'Resume' : 'Start'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModulesGrid(BuildContext context, WidgetRef ref) {
    final englishSermonCountAsync = ref.watch(sermonCountByLangProvider('en'));
    final tamilSermonCountAsync = ref.watch(sermonCountByLangProvider('ta'));
    final englishSermonSubtitle = englishSermonCountAsync.when(
      data: (count) => '$count Messages',
      loading: () => 'Messages',
      error: (_, _) => 'Messages',
    );
    final tamilSermonSubtitle = tamilSermonCountAsync.when(
      data: (count) => '$count செய்திகள்',
      loading: () => 'செய்திகள்',
      error: (_, _) => 'செய்திகள்',
    );
    final modules = [
      _ModuleCardData(
        icon: Icons.book_outlined,
        title: 'English Bible',
        subtitle: 'KJV',
        color: const Color(0xFF4B6CB7),
        onTap: () {
          ref.read(selectedBibleLangProvider.notifier).setLang('en');
          context.push('/reader');
        },
      ),
      _ModuleCardData(
        icon: Icons.book_outlined,
        title: 'Tamil Bible',
        subtitle: 'BSI',
        color: const Color(0xFF4B6CB7),
        onTap: () {
          ref.read(selectedBibleLangProvider.notifier).setLang('ta');
          context.push('/reader');
        },
      ),
      _ModuleCardData(
        icon: Icons.menu_outlined,
        title: 'English Sermon',
        subtitle: englishSermonSubtitle,
        color: const Color(0xFF6B7FB7),
        onTap: () {
          ref.read(selectedSermonLangProvider.notifier).setLang('en');
          context.push('/sermons?resume=1');
        },
      ),
      _ModuleCardData(
        icon: Icons.menu_outlined,
        title: 'தமிழ் செய்திகள்',
        subtitle: tamilSermonSubtitle,
        color: const Color(0xFF6B7FB7),
        onTap: () {
          ref.read(selectedSermonLangProvider.notifier).setLang('ta');
          // Always open the sermon list for Tamil — don't try to resume
          // an English session.
          context.push('/sermons');
        },
      ),
      _ModuleCardData(
        icon: Icons.search,
        title: 'Search',
        subtitle: 'Bible & Sermons',
        color: const Color(0xFF7B5EA7),
        onTap: () => context.push('/search?fresh=1'),
      ),
      _ModuleCardData(
        icon: Icons.music_note_outlined,
        title: 'Only Believe Songs',
        subtitle: '1196 Hymns',
        color: const Color(0xFF4BA7A0),
        onTap: () => context.push('/songs'),
      ),
      _ModuleCardData(
        icon: Icons.music_note_outlined,
        title: 'தமிழ் பாடல்கள்',
        subtitle: 'Tamil Songs',
        color: const Color(0xFFE67E22),
        onTap: () => context.push('/songs/tamil'),
      ),
      _ModuleCardData(
        icon: Icons.article_outlined,
        title: 'Question and Answers',
        subtitle: 'COD English',
        color: const Color(0xFF8E44AD),
        onTap: () {
          context.push('/cod?lang=en');
        },
      ),
      _ModuleCardData(
        icon: Icons.article_outlined,
        title: 'கேள்விகளும் பதில்களும்',
        subtitle: 'COD தமிழ்',
        color: const Color(0xFFD35400),
        onTap: () {
          context.push('/cod?lang=ta');
        },
      ),
      _ModuleCardData(
        icon: Icons.layers_outlined,
        title: 'Seven Seals',
        subtitle: '10 Messages',
        color: const Color(0xFF2E86AB),
        onTap: () {
          ref.read(selectedSermonLangProvider.notifier).setLang('en');
          final uri = Uri(
            path: '/sermons',
            queryParameters: {
              'mode': 'sevenSeals',
              'title': '7 Seals',
              'lang': 'en',
            },
          );
          context.push(uri.toString());
        },
      ),
      _ModuleCardData(
        icon: Icons.layers_outlined,
        title: 'ஏழு முத்திரைகள்',
        subtitle: '10 செய்திகள்',
        color: const Color(0xFF6A4C93),
        onTap: () {
          ref.read(selectedSermonLangProvider.notifier).setLang('ta');
          final uri = Uri(
            path: '/sermons',
            queryParameters: {
              'mode': 'sevenSeals',
              'title': 'ஏழு முத்திரைகள்',
              'lang': 'ta',
            },
          );
          context.push(uri.toString());
        },
      ),
      _ModuleCardData(
        icon: Icons.article,
        title: 'English Tracts',
        subtitle: '26 Tracts',
        color: const Color(0xFFC0392B), // Unique color red-ish tone
        onTap: () {
          context.push('/tracts?lang=en');
        },
      ),
      _ModuleCardData(
        icon: Icons.article,
        title: 'தமிழ் பிரசுரங்கள்',
        subtitle: '34 Tracts',
        color: const Color(0xFFC0392B), // Same color scheme for coherence
        onTap: () {
          context.push('/tracts?lang=ta');
        },
      ),
      _ModuleCardData(
        icon: Icons.auto_stories_outlined,
        title: 'Stories English',
        subtitle: 'WMB / Kids / Timeline / Witnesses',
        color: const Color(0xFF4B8CF5),
        onTap: () {
          context.push('/stories?lang=en');
        },
      ),
      _ModuleCardData(
        icon: Icons.auto_stories_outlined,
        title: 'Stories Tamil',
        subtitle: 'ஆரம்ப 4 தலைப்புகள்',
        color: const Color(0xFF20A57A),
        onTap: () {
          context.push('/stories?lang=ta');
        },
      ),
      _ModuleCardData(
        icon: Icons.church_outlined,
        title: 'English Church Ages',
        subtitle: 'The 7 Church Ages',
        color: const Color(0xFF9B59B6),
        onTap: () {
          context.push('/church-ages?lang=en');
        },
      ),
      _ModuleCardData(
        icon: Icons.church_outlined,
        title: 'தமிழ் சபை காலங்கள்',
        subtitle: 'The 7 Church Ages',
        color: const Color(0xFF8E44AD),
        onTap: () {
          context.push('/church-ages?lang=ta');
        },
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // More columns on wider screens to reduce card size.
        final crossAxisCount = width >= 1200
            ? 4
            : width >= 900
            ? 3
            : 2;
        // Slightly shorter cards on desktop, taller on mobile.
        final childAspectRatio = width >= 1200
            ? 1.75
            : width >= 900
            ? 1.6
            : width >= 700
            ? 1.35
            : 1.1;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: modules.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: childAspectRatio,
          ),
          itemBuilder: (context, index) => _ModuleCard(data: modules[index]),
        );
      },
    );
  }

  // ignore: unused_element
  Widget _buildRecentReadsStrip(
    BuildContext context,
    WidgetRef ref,
    List<RecentReadItem> recentItems,
  ) {
    final sermonFlows = recentItems
        .where((item) => item.flowType == FlowType.sermon)
        .toList();
    if (sermonFlows.isEmpty) {
      return const SizedBox(
        height: 80,
        child: Center(
          child: Text(
            'No recent reads yet.',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return SizedBox(
      height: 120,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: sermonFlows.length,
        itemBuilder: (context, index) {
          final item = sermonFlows[index];
          final tabs = item.snapshot.toReaderTabs();
          final ReaderTab? firstSermon = tabs.cast<ReaderTab?>().firstWhere(
            (t) => t?.type == ReaderContentType.sermon,
            orElse: () => tabs.isNotEmpty ? tabs.first : null,
          );
          final title = (firstSermon?.title ?? '').isNotEmpty
              ? firstSermon!.title
              : item.title;
          const subtitle = 'Sermon';
          const icon = Icons.headphones;

          return Padding(
            padding: const EdgeInsets.only(right: 16),
            child: SizedBox(
              width: 160,
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    ref
                        .read(sermonFlowProvider.notifier)
                        .restoreSession(item.snapshot);
                    context.push('/sermon-reader');
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(14.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Icon(
                              icon,
                              size: 14,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              subtitle,
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ignore: unused_element
  Widget _buildRecentReadsHeader(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<RecentReadItem>> recentReadsAsync,
  ) {
    final hasItems = recentReadsAsync.maybeWhen(
      data: (items) => items.isNotEmpty,
      orElse: () => false,
    );

    return Row(
      children: [
        const Text(
          'Recent Reads',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: hasItems
              ? () async {
                  await ref
                      .read(readingStateRepositoryProvider)
                      .clearRecentReads();
                  ref.invalidate(recentReadsProvider);
                }
              : null,
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text('Clear'),
        ),
      ],
    );
  }

  Future<void> _showRecentReadsSheet(BuildContext context, WidgetRef ref) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Consumer(
          builder: (context, sheetRef, _) {
            final recentReadsAsync = sheetRef.watch(recentReadsProvider);
            return SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  margin: const EdgeInsets.only(top: 48, left: 16, right: 16, bottom: 24),
                  constraints: BoxConstraints(
                    maxWidth: 480,
                    maxHeight: MediaQuery.of(context).size.height * 0.7,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).dialogBackgroundColor,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                    child: recentReadsAsync.when(
                  loading: () => const SizedBox(
                    height: 180,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, _) => const SizedBox(
                    height: 180,
                    child: Center(
                      child: Text(
                        'Unable to load recent viewed items.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                  data: (items) {
                    if (items.isEmpty) {
                      return const SizedBox(
                        height: 180,
                        child: Center(
                          child: Text(
                            'No recent viewed items yet.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      );
                    }

                    final sorted = [...items]
                      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Recent Viewed',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: () async {
                                await sheetRef
                                    .read(readingStateRepositoryProvider)
                                    .clearRecentReads();
                                sheetRef.invalidate(recentReadsProvider);
                              },
                              icon: const Icon(Icons.delete_outline, size: 18),
                              label: const Text('Clear'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Flexible(
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: sorted.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = sorted[index];
                              final icon = item.flowType == FlowType.bible
                                  ? Icons.menu_book
                                  : Icons.headphones;
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(icon),
                                title: Text(
                                  item.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(item.subtitle),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {
                                  Navigator.of(sheetContext).pop();
                                  if (item.flowType == FlowType.bible) {
                                    ref
                                        .read(readerProvider.notifier)
                                        .restoreSession(item.snapshot);
                                    context.push('/reader');
                                  } else {
                                    ref
                                        .read(sermonFlowProvider.notifier)
                                        .restoreSession(item.snapshot);
                                    context.push('/sermon-reader');
                                  }
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    );
                    },
                  ),
                ), // Padding
              ), // Container
            ), // Align
          ); // SafeArea
        },
      ); // Consumer
    }, // showModalBottomSheet builder
  );
}
}

class _ModuleCardData {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ModuleCardData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
}

class _ModuleCard extends StatelessWidget {
  final _ModuleCardData data;

  const _ModuleCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = data.color;
    final screenWidth = MediaQuery.sizeOf(context).width;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final scale = (width / 220).clamp(0.85, 1.15);
        final largeScreenBoost = screenWidth >= 1400
            ? 1.22
            : screenWidth >= 1100
            ? 1.12
            : 1.0;
        final iconSize = 28 * scale;
        final titleSize = 15 * scale * largeScreenBoost;
        final subtitleSize = 12.5 * scale * largeScreenBoost;
        final cardPaddingH = 16 * scale;
        final cardPaddingV = 12 * scale;

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          clipBehavior: Clip.antiAlias,
          color: isDark
              ? color.withValues(alpha: 0.1)
              : theme.colorScheme.surfaceContainerLowest,
          child: InkWell(
            onTap: data.onTap,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: color.withValues(alpha: isDark ? 0.3 : 0.15),
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: cardPaddingH,
                vertical: cardPaddingV,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(data.icon, color: color, size: iconSize),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    data.title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: titleSize,
                      color: isDark ? color : theme.colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    data.subtitle,
                    style: TextStyle(
                      fontSize: subtitleSize,
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
