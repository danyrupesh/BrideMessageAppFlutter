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
import '../database/metadata/installed_content_provider.dart';

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
        builder: (context, state) => const SearchScreen(),
      ),
      GoRoute(
        path: '/sermons',
        builder: (context, state) {
          final resume = state.uri.queryParameters['resume'] == '1';
          return SermonListScreen(autoResume: resume);
        },
      ),
      GoRoute(
        path: '/sermon-reader',
        builder: (context, state) => const SermonReaderScreen(),
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
    ],
  );
});
