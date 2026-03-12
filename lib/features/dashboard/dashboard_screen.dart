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
    final readerState = ref.watch(readerProvider);
    final ReaderTab? activeTab = readerState.activeTab;
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
                _buildContinueReadingCard(context, activeTab),
                const SizedBox(height: 24),
                const SizedBox(height: 8),
                const Text(
                  'Modules',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                // const SizedBox(height: 16),
                _buildModulesGrid(context, ref),
                const SizedBox(height: 24),
                const Text(
                  'Recent Reads',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
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

  Widget _buildContinueReadingCard(BuildContext context, ReaderTab? activeTab) {
    final theme = Theme.of(context);

    final title = () {
      if (activeTab == null) return 'Start Reading';
      if (activeTab.type == ReaderContentType.bible &&
          activeTab.book != null &&
          activeTab.chapter != null) {
        return '${activeTab.book} ${activeTab.chapter}';
      }
      if (activeTab.type == ReaderContentType.sermon) {
        return activeTab.title;
      }
      return activeTab.title;
    }();

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
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.menu_book,
                  color: theme.colorScheme.onPrimary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'CONTINUE READING',
                  style: TextStyle(
                    color: theme.colorScheme.onPrimary.withValues(alpha: 0.8),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                color: theme.colorScheme.onPrimary,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (activeTab != null)
              Text(
                activeTab.type == ReaderContentType.bible
                    ? 'Tap to resume your last Bible location.'
                    : 'Tap to resume your last Sermon.',
                style: TextStyle(
                  color: theme.colorScheme.onPrimary.withValues(alpha: 0.9),
                ),
              ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.push('/reader'),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.onPrimary,
                foregroundColor: theme.colorScheme.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(activeTab == null ? 'Start Reading' : 'Resume'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModulesGrid(BuildContext context, WidgetRef ref) {
    final modules = [
      _ModuleCardData(
        icon: Icons.book_outlined,
        title: 'English Bible',
        subtitle: 'KJV',
        color: const Color(0xFF4B6CB7),
        onTap: () {
          ref.read(selectedBibleLangProvider.notifier).state = 'en';
          context.push('/reader');
        },
      ),
      _ModuleCardData(
        icon: Icons.book_outlined,
        title: 'Tamil Bible',
        subtitle: 'BSI',
        color: const Color(0xFF4B6CB7),
        onTap: () {
          ref.read(selectedBibleLangProvider.notifier).state = 'ta';
          context.push('/reader');
        },
      ),
      _ModuleCardData(
        icon: Icons.menu_outlined,
        title: 'English Sermon',
        subtitle: 'Messages',
        color: const Color(0xFF6B7FB7),
        onTap: () {
          ref.read(selectedSermonLangProvider.notifier).state = 'en';
          context.push('/sermons?resume=1');
        },
      ),
      _ModuleCardData(
        icon: Icons.menu_outlined,
        title: 'Tamil Sermon',
        subtitle: 'Messages',
        color: const Color(0xFF6B7FB7),
        onTap: () {
          ref.read(selectedSermonLangProvider.notifier).state = 'ta';
          context.push('/sermons?resume=1');
        },
      ),
      _ModuleCardData(
        icon: Icons.search,
        title: 'Search',
        subtitle: 'Bible & Sermons',
        color: const Color(0xFF7B5EA7),
        onTap: () => context.push('/search'),
      ),
      _ModuleCardData(
        icon: Icons.music_note_outlined,
        title: 'Only Believe Songs',
        subtitle: '1196 Hymns',
        color: const Color(0xFF4BA7A0),
        onTap: () => context.push('/songs'),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // 3-column above 700px (e.g. Windows), 2-column on mobile
        final crossAxisCount = width >= 700 ? 3 : 2;
        // Adjust aspect ratio: taller on mobile (more content), square-ish on desktop
        final childAspectRatio = width >= 700 ? 1.35 : 1.1;

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
    if (recentItems.isEmpty) {
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
        itemCount: recentItems.length,
        itemBuilder: (context, index) {
          final item = recentItems[index];
          final isBible = item.flowType == FlowType.bible;
          final title = item.title;
          final subtitle = item.subtitle;
          final icon = isBible ? Icons.menu_book : Icons.headphones;

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
                    if (isBible) {
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

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isDark ? 0.25 : 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(data.icon, color: color, size: 28),
              ),
              const SizedBox(height: 12),
              Text(
                data.title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                data.subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
