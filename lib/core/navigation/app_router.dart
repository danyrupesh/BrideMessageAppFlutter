import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/history/history_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/reader/reader_screen.dart';
import '../../features/search/search_screen.dart';
import '../../features/search/search_help_screen.dart';
import '../../features/sermons/sermons_screen.dart';
import '../../features/sermons/sermon_reader_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/songs/songs_gate_screen.dart';
import '../../features/songs/song_detail_screen.dart';
import '../../features/cod/cod_questions_screen.dart';
import '../../features/cod/cod_answer_screen.dart';
import '../database/metadata/installed_content_provider.dart';
import '../../features/reader/providers/reader_provider.dart';
import '../../features/reader/models/reader_tab.dart';
import '../../features/sermons/providers/sermon_provider.dart';
import '../../features/sermons/providers/sermon_flow_provider.dart';

/// Routes based on real installed-database content rather than a persisted flag.
/// Mirrors Android's MainActivity.checkAnyDatabasesInstalled() logic:
///   - hasContent == true  → start at /
///   - hasContent == false → start at /onboarding
///
/// The user can "Skip for now" (session-only) which sets the flag in memory so
/// the redirect passes; next cold start re-checks real content.
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (BuildContext context, GoRouterState state) {
      final contentState = ref.read(hasInstalledContentProvider);

      return contentState.when(
        loading: () {
          // Still checking — hold at onboarding (shows progress indicator).
          if (state.matchedLocation == '/onboarding') return null;
          return '/onboarding';
        },
        error: (e, st) {
          if (state.matchedLocation == '/onboarding') return null;
          return '/onboarding';
        },
        data: (hasContent) {
          if (!hasContent && state.matchedLocation != '/onboarding') {
            return '/onboarding';
          }
          if (hasContent && state.matchedLocation == '/onboarding') {
            return '/';
          }
          return null;
        },
      );
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(path: '/', builder: (context, state) => const DashboardScreen()),
      GoRoute(
        path: '/reader',
        builder: (context, state) => const ReaderScreen(),
      ),
      GoRoute(
        path: '/search',
        builder: (context, state) {
          final tab = state.uri.queryParameters['tab'];
          final fresh = state.uri.queryParameters['fresh'] == '1';
          final query = state.uri.queryParameters['q'];
          return SearchScreen(initialTab: tab, fresh: fresh, initialQuery: query);
        },
      ),
      GoRoute(
        path: '/sermons',
        builder: (context, state) {
          final resume = state.uri.queryParameters['resume'] == '1';
          final prefix = state.uri.queryParameters['prefix'];
          final title = state.uri.queryParameters['title'];
          final mode = state.uri.queryParameters['mode'];
          final lang = state.uri.queryParameters['lang'];
          const sevenSealsIds = [
            '63-0317M',
            '63-0317E',
            '63-0318',
            '63-0319',
            '63-0320',
            '63-0321',
            '63-0322',
            '63-0323',
            '63-0324M',
            '63-0324E',
          ];
          final isSevenSeals = mode == 'sevenSeals';
          if ((mode == 'cod' || isSevenSeals) && lang != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref.read(selectedSermonLangProvider.notifier).setLang(lang);
            });
          }
          return SermonListScreen(
            autoResume: resume,
            initialQuery: mode == 'cod' || isSevenSeals ? null : prefix,
            titlePrefix: mode == 'cod' ? prefix : null,
            customTitle: title,
            hideFilters: mode == 'cod' || isSevenSeals,
            allowedIds: isSevenSeals ? sevenSealsIds : null,
          );
        },
      ),
      GoRoute(
        path: '/sermon-reader',
        builder: (context, state) => const SermonReaderScreen(),
      ),
      GoRoute(
        path: '/appshare/bible',
        builder: (context, state) {
          final book = state.uri.queryParameters['book'];
          final chapter = int.tryParse(state.uri.queryParameters['chapter'] ?? '1') ?? 1;
          final lang = state.uri.queryParameters['lang'];
          final verse = int.tryParse(state.uri.queryParameters['verse'] ?? '');

          if (lang != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref.read(selectedBibleLangProvider.notifier).setLang(lang);
            });
          }

          if (book != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref.read(readerProvider.notifier).openTab(ReaderTab(
                    type: ReaderContentType.bible,
                    title: "$book $chapter",
                    book: book,
                    chapter: chapter,
                    verse: verse,
                  ));
            });
          }
          return const ReaderScreen();
        },
      ),
      GoRoute(
        path: '/appshare/sermon',
        builder: (context, state) {
          final id = state.uri.queryParameters['id'];
          final lang = state.uri.queryParameters['lang'];

          if (lang != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref.read(selectedSermonLangProvider.notifier).setLang(lang);
            });
          }

          if (id != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              // Note: We don't have the title here, but SermonReaderScreen 
              // fetches metadata by ID if needed.
              ref.read(sermonFlowProvider.notifier).addSermonTab(ReaderTab(
                    type: ReaderContentType.sermon,
                    title: 'Loading...', 
                    sermonId: id,
                  ));
            });
          }
          return const SermonReaderScreen();
        },
      ),
      GoRoute(
        path: '/songs',
        builder: (context, state) => const SongsGateScreen(),
      ),
      GoRoute(
        path: '/song-detail',
        builder: (context, state) {
          final extra = state.extra;
          final hymnNoFromExtra =
              extra is int ? extra : null;
          final hymnNoFromQuery =
              int.tryParse(state.uri.queryParameters['hymnNo'] ?? '');
          final hymnNo = hymnNoFromExtra ?? hymnNoFromQuery ?? 0;
          return SongDetailScreen(hymnNo: hymnNo);
        },
      ),
      GoRoute(
        path: '/history',
        builder: (context, state) => const HistoryScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/search-help',
        builder: (context, state) => const SearchHelpScreen(),
      ),
      GoRoute(
        path: '/cod',
        builder: (context, state) {
          final lang = state.uri.queryParameters['lang'] ?? 'en';
          return CodQuestionsScreen(lang: lang);
        },
      ),
      GoRoute(
        path: '/cod/detail/:id',
        builder: (context, state) {
          final lang = state.uri.queryParameters['lang'] ?? 'en';
          final id = state.pathParameters['id']!;
          final paraRaw = state.uri.queryParameters['para'];
          final paraId = int.tryParse(paraRaw ?? '');
          final qRaw = state.uri.queryParameters['q']?.trim();
          return CodAnswerScreen(
            lang: lang,
            id: id,
            scrollToAnswerParagraphId: paraId,
            highlightQuery:
                (qRaw != null && qRaw.isNotEmpty) ? qRaw : null,
          );
        },
      ),
    ],
  );
});
