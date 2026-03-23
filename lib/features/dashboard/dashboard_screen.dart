import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../settings/widgets/theme_picker_sheet.dart';
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
    final recentReadsAsync = ref.watch(recentReadsProvider);

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
                icon: const Icon(Icons.color_lens),
                onPressed: () => ThemePickerSheet.show(context),
              ),
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
                _buildContinueReadingSection(context, ref, recentReadsAsync),
                const SizedBox(height: 24),
                const SizedBox(height: 8),
                const Text(
                  'Modules',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                // const SizedBox(height: 16),
                _buildModulesGrid(context, ref),
                const SizedBox(height: 24),
                _buildRecentReadsHeader(context, ref, recentReadsAsync),
                const SizedBox(height: 16),
                recentReadsAsync.when(
                  data: (items) => _buildRecentReadsStrip(context, ref, items),
                  loading: () => const SizedBox(
                    height: 80,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, _) => const SizedBox(
                    height: 80,
                    child: Center(
                      child: Text(
                        'Unable to load recent reads.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ]),
            ),
          ),
        ],
      ),
    );
  }

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
                        .restoreSession(item!.snapshot);
                    context.push('/reader');
                  } else {
                    ref
                        .read(sermonFlowProvider.notifier)
                        .restoreSession(item!.snapshot);
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
        icon: Icons.sticky_note_2_outlined,
        title: 'Pastor Notes',
        subtitle: 'Local notes',
        color: const Color(0xFF1F8A70),
        onTap: () => context.push('/notes'),
      ),
      _ModuleCardData(
        icon: Icons.music_note_outlined,
        title: 'Only Believe Songs',
        subtitle: '1196 Hymns',
        color: const Color(0xFF4BA7A0),
        onTap: () => context.push('/songs'),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final scale = (width / 220).clamp(0.85, 1.15);
        final iconSize = 28 * scale;
        final badgePadding = 14 * scale;
        final titleSize = 15 * scale;
        final subtitleSize = 12.5 * scale;
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
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    color.withValues(alpha: isDark ? 0.18 : 0.12),
                    theme.colorScheme.surface.withValues(
                      alpha: isDark ? 0.4 : 0.9,
                    ),
                  ],
                ),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: cardPaddingH,
                vertical: cardPaddingV,
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: -8,
                    bottom: -12,
                    child: Icon(
                      data.icon,
                      size: 88 * scale,
                      color: color.withValues(alpha: isDark ? 0.12 : 0.08),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: EdgeInsets.all(badgePadding),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: isDark ? 0.25 : 0.12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(data.icon, color: color, size: iconSize),
                      ),
                      SizedBox(height: 12 * scale),
                      Text(
                        data.title,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: titleSize,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 2 * scale),
                      Text(
                        data.subtitle,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: subtitleSize,
                        ),
                      ),
                    ],
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
