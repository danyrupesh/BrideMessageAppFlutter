import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../settings/widgets/theme_picker_sheet.dart';
import '../reader/providers/reader_provider.dart';
import '../reader/models/reader_tab.dart';
import '../sermons/providers/sermon_flow_provider.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final readerState = ref.watch(readerProvider);
    final sermonFlowState = ref.watch(sermonFlowProvider);
    final ReaderTab? activeTab = readerState.activeTab;

    // Combine Bible tabs (most recent first) + the active sermon (if any).
    final List<ReaderTab> recentTabs = [
      ...readerState.tabs.reversed,
      if (sermonFlowState.hasSermon) sermonFlowState.tabs.first,
    ];

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
                      theme.colorScheme.primaryContainer.withOpacity(
                        isDark ? 0.3 : 0.8,
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
                _buildModulesGrid(context),
                const SizedBox(height: 24),
                const Text(
                  'Recent Reads',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                _buildRecentReadsStrip(context, ref, recentTabs),
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
      shadowColor: theme.colorScheme.primary.withOpacity(0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.primary.withOpacity(0.8),
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
                    color: theme.colorScheme.onPrimary.withOpacity(0.8),
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
                  color: theme.colorScheme.onPrimary.withOpacity(0.9),
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

  Widget _buildModulesGrid(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 1.2,
      children: [
        _ModuleCard(
          icon: Icons.book,
          title: 'Bible',
          color: Colors.blue,
          onTap: () => context.push('/reader'),
        ),
        _ModuleCard(
          icon: Icons.record_voice_over,
          title: 'Sermons',
          color: Colors.brown,
          onTap: () => context.push('/sermons'),
        ),
        _ModuleCard(
          icon: Icons.search,
          title: 'Search',
          color: Colors.deepPurple,
          onTap: () => context.push('/search'),
        ),
        _ModuleCard(
          icon: Icons.music_note,
          title: 'Songs',
          color: Colors.teal,
          onTap: () => context.push('/songs'),
        ),
      ],
    );
  }

  Widget _buildRecentReadsStrip(
    BuildContext context,
    WidgetRef ref,
    List<ReaderTab> recentTabs,
  ) {
    if (recentTabs.isEmpty) {
      return const SizedBox(
        height: 80,
        child: Center(
          child: Text('No recent reads yet.',
              style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    return SizedBox(
      height: 120,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: recentTabs.length,
        itemBuilder: (context, index) {
          final tab = recentTabs[index];
          final isBible = tab.type == ReaderContentType.bible;

          final title = isBible && tab.book != null && tab.chapter != null
              ? '${tab.book} ${tab.chapter}'
              : tab.title;

          final subtitle = isBible ? 'Bible' : 'Sermon';
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
                      final bibleIndex = ref
                          .read(readerProvider)
                          .tabs
                          .indexOf(tab);
                      if (bibleIndex >= 0) {
                        ref
                            .read(readerProvider.notifier)
                            .switchTab(bibleIndex);
                      }
                      context.push('/reader');
                    } else {
                      ref
                          .read(sermonFlowProvider.notifier)
                          .openSermon(tab);
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
                            Icon(icon,
                                size: 14,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
                            const SizedBox(width: 4),
                            Text(
                              subtitle,
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
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

class _ModuleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  const _ModuleCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                isDark ? color.withOpacity(0.2) : color.withOpacity(0.1),
                theme.colorScheme.surface,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
