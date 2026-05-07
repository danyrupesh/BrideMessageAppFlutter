import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../church_ages/providers/church_ages_provider.dart';
import '../settings/widgets/theme_picker_sheet.dart';
import 'module_resume_prefs.dart';
import '../help/widgets/help_button.dart';
import '../reader/providers/reader_provider.dart';
import '../reader/models/reader_tab.dart';
import '../sermons/providers/sermon_flow_provider.dart';
import '../sermons/providers/sermon_provider.dart';
import '../reading_state/providers/reading_state_provider.dart';
import '../reading_state/models/reading_flow_models.dart';
import 'dashboard_language_provider.dart';

/// Pushes a module list route, then the reader, so the back button returns
/// to the list (not the dashboard) when resuming a saved item.
Future<void> _pushModuleListThenReader(
  BuildContext context, {
  required String listLocation,
  required String readerLocation,
}) async {
  await context.push(listLocation);
  if (context.mounted) {
    context.push(readerLocation);
  }
}

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
              _buildLanguageToggle(context, ref),
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
              onPressed: () async {
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
                    await _pushModuleListThenReader(
                      context,
                      listLocation: '/sermons?resume=1',
                      readerLocation: '/sermon-reader',
                    );
                  }
                  return;
                }

                if (flowType == FlowType.bible) {
                  await ref
                      .read(readerProvider.notifier)
                      .reloadBibleFlowFromDisk();
                  if (context.mounted) context.push('/reader');
                } else {
                  await ref
                      .read(sermonFlowProvider.notifier)
                      .reloadSermonFlowFromDisk();
                  if (!context.mounted) return;
                  if (ref.read(sermonFlowProvider).hasSermon) {
                    await _pushModuleListThenReader(
                      context,
                      listLocation: '/sermons?resume=1',
                      readerLocation: '/sermon-reader',
                    );
                  } else {
                    context.push('/sermons');
                  }
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
    final selectedLang = ref.watch(dashboardLanguageProvider);
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
        language: 'en',
        onTap: () async {
          ref.read(selectedBibleLangProvider.notifier).setLang('en');
          await ref.read(readerProvider.notifier).reloadBibleFlowFromDisk();
          if (context.mounted) context.push('/reader');
        },
      ),
      _ModuleCardData(
        icon: Icons.book_outlined,
        title: 'தமிழ் பைபிள்',
        subtitle: 'BSI',
        color: const Color(0xFF4B6CB7),
        language: 'ta',
        onTap: () async {
          ref.read(selectedBibleLangProvider.notifier).setLang('ta');
          await ref.read(readerProvider.notifier).reloadBibleFlowFromDisk();
          if (context.mounted) context.push('/reader');
        },
      ),
      _ModuleCardData(
        icon: Icons.menu_outlined,
        title: 'English Sermon',
        subtitle: englishSermonSubtitle,
        color: const Color(0xFF6B7FB7),
        language: 'en',
        onTap: () async {
          ref.read(selectedSermonLangProvider.notifier).setLang('en');
          await ref
              .read(sermonFlowProvider.notifier)
              .reloadSermonFlowFromDisk();
          if (!context.mounted) return;
          if (ref.read(sermonFlowProvider).hasSermon) {
            await _pushModuleListThenReader(
              context,
              listLocation: '/sermons?resume=1',
              readerLocation: '/sermon-reader',
            );
          } else {
            context.push('/sermons?resume=1');
          }
        },
      ),
      _ModuleCardData(
        icon: Icons.menu_outlined,
        title: 'தமிழ் செய்திகள்',
        subtitle: tamilSermonSubtitle,
        color: const Color(0xFF6B7FB7),
        language: 'ta',
        onTap: () async {
          ref.read(selectedSermonLangProvider.notifier).setLang('ta');
          await ref
              .read(sermonFlowProvider.notifier)
              .reloadSermonFlowFromDisk();
          if (!context.mounted) return;
          if (ref.read(sermonFlowProvider).hasSermon) {
            await _pushModuleListThenReader(
              context,
              listLocation: '/sermons?resume=1',
              readerLocation: '/sermon-reader',
            );
          } else {
            context.push('/sermons?resume=1');
          }
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
        language: 'en',
        onTap: () async {
          final n = await ModuleResumePrefs.peekLastEnglishHymn();
          if (!context.mounted) return;
          if (n != null) {
            context.push('/song-detail?hymnNo=$n');
          } else {
            context.push('/songs');
          }
        },
      ),
      _ModuleCardData(
        icon: Icons.music_note_outlined,
        title: 'தமிழ் பாடல்கள்',
        subtitle: 'Tamil Songs',
        color: const Color(0xFFE67E22),
        language: 'ta',
        onTap: () async {
          final id = await ModuleResumePrefs.peekLastTamilSongId();
          if (!context.mounted) return;
          if (id != null) {
            context.push('/song-detail/tamil?id=$id');
          } else {
            context.push('/songs/tamil');
          }
        },
      ),
      _ModuleCardData(
        icon: Icons.article_outlined,
        title: 'Question and Answers',
        subtitle: 'COD English',
        color: const Color(0xFFD35400),
        language: 'ta',
        onTap: () async {
          final id = await ModuleResumePrefs.peekLastCodDetailId('ta');
          if (!context.mounted) return;
          if (id != null) {
            context.push('/cod/detail/$id?lang=ta');
          } else {
            context.push('/cod?lang=ta');
          }
        },
      ),
      _ModuleCardData(
        icon: Icons.layers_outlined,
        title: 'Seven Seals',
        subtitle: '10 Messages',
        color: const Color(0xFF6A4C93),
        language: 'en',
        onTap: () async {
          ref.read(selectedSermonLangProvider.notifier).setLang('en');
          await ref
              .read(sermonFlowProvider.notifier)
              .reloadSermonFlowFromDisk();
          if (!context.mounted) return;
          final sevenSealsList = Uri(
            path: '/sermons',
            queryParameters: {
              'mode': 'sevenSeals',
              'title': '7 Seals',
              'lang': 'en',
            },
          ).toString();
          if (ref.read(sermonFlowProvider).hasSermon) {
            await _pushModuleListThenReader(
              context,
              listLocation: sevenSealsList,
              readerLocation: '/sermon-reader',
            );
          } else {
            context.push(sevenSealsList);
          }
        },
      ),
      _ModuleCardData(
        icon: Icons.layers_outlined,
        title: 'ஏழு முத்திரைகள்',
        subtitle: '10 Messages',
        color: const Color(0xFF6A4C93),
        language: 'ta',
        onTap: () async {
          ref.read(selectedSermonLangProvider.notifier).setLang('ta');
          await ref
              .read(sermonFlowProvider.notifier)
              .reloadSermonFlowFromDisk();
          if (!context.mounted) return;
          final sevenSealsList = Uri(
            path: '/sermons',
            queryParameters: {
              'mode': 'sevenSeals',
              'title': 'ஏழு முத்திரைகள்',
              'lang': 'ta',
            },
          ).toString();
          if (ref.read(sermonFlowProvider).hasSermon) {
            await _pushModuleListThenReader(
              context,
              listLocation: sevenSealsList,
              readerLocation: '/sermon-reader',
            );
          } else {
            context.push(sevenSealsList);
          }
        },
      ),
      _ModuleCardData(
        icon: Icons.article,
        title: 'English Tracts',
        subtitle: '26 Tracts',
        color: const Color(0xFFC0392B), // Unique color red-ish tone
        language: 'en',
        onTap: () async {
          final id = await ModuleResumePrefs.peekLastTractId('en');
          if (!context.mounted) return;
          if (id != null) {
            await _pushModuleListThenReader(
              context,
              listLocation: '/tracts?lang=en',
              readerLocation: Uri(
                path: '/tract-reader',
                queryParameters: {'id': id},
              ).toString(),
            );
          } else {
            context.push('/tracts?lang=en');
          }
        },
      ),
      _ModuleCardData(
        icon: Icons.article,
        title: 'தமிழ் பிரசுரங்கள்',
        subtitle: '34 Tracts',
        color: const Color(0xFFC0392B), // Same color scheme for coherence
        language: 'ta',
        onTap: () async {
          final id = await ModuleResumePrefs.peekLastTractId('ta');
          if (!context.mounted) return;
          if (id != null) {
            await _pushModuleListThenReader(
              context,
              listLocation: '/tracts?lang=ta',
              readerLocation: Uri(
                path: '/tract-reader',
                queryParameters: {'id': id},
              ).toString(),
            );
          } else {
            context.push('/tracts?lang=ta');
          }
        },
      ),
      _ModuleCardData(
        icon: Icons.auto_stories_outlined,
        title: 'Stories English',
        subtitle: 'WMB / Kids / Timeline / Witnesses',
        color: const Color(0xFF20A57A),
        language: 'ta',
        onTap: () async {
          final pair = await ModuleResumePrefs.peekLastStory('ta');
          if (!context.mounted) return;
          final id = pair[0];
          final section = pair[1];
          if (id != null) {
            final sec = (section != null && section.isNotEmpty)
                ? section
                : 'wmbStories';
            await _pushModuleListThenReader(
              context,
              listLocation: '/stories?lang=ta',
              readerLocation: Uri(
                path: '/story-reader',
                queryParameters: {'id': id, 'lang': 'ta', 'section': sec},
              ).toString(),
            );
          } else {
            context.push('/stories?lang=ta');
          }
        },
      ),
      _ModuleCardData(
        icon: Icons.auto_stories,
        title: 'Special Books',
        subtitle: 'Books & Chapters',
        color: const Color(0xFF16A085),
        language: 'en',
        onTap: () => context.push('/special-books?lang=en'),
      ),
      _ModuleCardData(
        icon: Icons.auto_stories,
        title: 'சிறப்பு புத்தகங்கள்',
        subtitle: 'Special Books',
        color: const Color(0xFF1ABC9C),
        language: 'ta',
        onTap: () => context.push('/special-books?lang=ta'),
      ),
      _ModuleCardData(
        icon: Icons.church_outlined,
        title: 'English Church Ages',
        subtitle: 'The 7 Church Ages',
        color: const Color(0xFF9B59B6),
        language: 'en',
        onTap: () async {
          await ref
              .read(activeChurchAgesLangProvider.notifier)
              .setLang('en');
          final topicId = await ModuleResumePrefs.peekChurchAgesTopicId('en');
          if (!context.mounted) return;
          if (topicId != null) {
            await _pushModuleListThenReader(
              context,
              listLocation: '/church-ages?lang=en',
              readerLocation: Uri(
                path: '/church-ages-reader',
                queryParameters: {'id': topicId.toString()},
              ).toString(),
            );
          } else {
            context.push('/church-ages?lang=en');
          }
        },
      ),
      _ModuleCardData(
        icon: Icons.church_outlined,
        title: 'தமிழ் சபை காலங்கள்',
        subtitle: 'The 7 Church Ages',
        color: const Color(0xFF8E44AD),
        language: 'ta',
        onTap: () async {
          await ref
              .read(activeChurchAgesLangProvider.notifier)
              .setLang('ta');
          final id = await ModuleResumePrefs.peekChurchAgesTopicId('ta');
          if (!context.mounted) return;
          if (id != null) {
            await _pushModuleListThenReader(
              context,
              listLocation: '/church-ages?lang=ta',
              readerLocation: Uri(
                path: '/church-ages-reader',
                queryParameters: {'id': id.toString()},
              ).toString(),
            );
          } else {
            context.push('/church-ages?lang=ta');
          }
        },
      ),
      _ModuleCardData(
        icon: Icons.format_quote_rounded,
        title: 'Prayer Quotes',
        subtitle: 'Inspirational Prayers',
        color: const Color(0xFF2980B9),
        language: 'en', // Assuming English
        onTap: () => context.push('/prayer-quotes'),
      ),
      _ModuleCardData(
        icon: Icons.format_quote_outlined,
        title: 'English Quotes',
        subtitle: 'A–Z · Topics · VGR',
        color: const Color(0xFF27AE60),
        language: 'en',
        onTap: () => context.push('/quotes'),
      ),
    ];

    final filteredModules = modules
        .where((m) => m.language == null || m.language == selectedLang)
        .toList();

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
          itemCount: filteredModules.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: childAspectRatio,
          ),
          itemBuilder: (context, index) =>
              _ModuleCard(data: filteredModules[index]),
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
                  onTap: () async {
                    ref
                        .read(sermonFlowProvider.notifier)
                        .restoreSession(item.snapshot);
                    await _pushModuleListThenReader(
                      context,
                      listLocation: '/sermons?resume=1',
                      readerLocation: '/sermon-reader',
                    );
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
                  margin: const EdgeInsets.only(
                    top: 48,
                    left: 16,
                    right: 16,
                    bottom: 24,
                  ),
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
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                  ),
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
                                    onTap: () async {
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
                                        await _pushModuleListThenReader(
                                          context,
                                          listLocation: '/sermons?resume=1',
                                          readerLocation: '/sermon-reader',
                                        );
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

  void _showComingSoonSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _buildLanguageToggle(BuildContext context, WidgetRef ref) {
    final selectedLang = ref.watch(dashboardLanguageProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(
            value: 'en',
            label: Text(
              'EN',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          ButtonSegment(
            value: 'ta',
            label: Text(
              'TA',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
        selected: {selectedLang},
        onSelectionChanged: (Set<String> newSelection) {
          ref
              .read(dashboardLanguageProvider.notifier)
              .setLang(newSelection.first);
        },
        showSelectedIcon: false,
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Theme.of(context).colorScheme.primary;
            }
            return null;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Theme.of(context).colorScheme.onPrimary;
            }
            return null;
          }),
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
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
  final String? language;

  const _ModuleCardData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.language,
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
