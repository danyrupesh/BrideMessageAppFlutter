import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/database/database_manager.dart';
import 'core/database/metadata/installed_database_registry.dart';
import 'core/navigation/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise metadata registry so the first DB check is fast.
  await InstalledDatabaseRegistry().hasAnyContent();

  // Log SQLite version & compile options for diagnostics.
  DatabaseManager.logSqliteDiagnostics();

  runApp(const ProviderScope(child: BrideMessageApp()));
}

class BrideMessageApp extends ConsumerWidget {
  const BrideMessageApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeSettings = ref.watch(themeProvider);

    ThemeMode getThemeMode(ThemeModePreference pref) {
      switch (pref) {
        case ThemeModePreference.light:
        case ThemeModePreference.sepia:
          return ThemeMode.light;
        case ThemeModePreference.dark:
          return ThemeMode.dark;
        case ThemeModePreference.system:
          return ThemeMode.system;
      }
    }

    return MaterialApp.router(
      title: 'Bride Message App',
      themeMode: getThemeMode(themeSettings.mode),
      theme: AppTheme.getThemeData(
        preference: themeSettings.mode == ThemeModePreference.sepia
            ? ThemeModePreference.sepia
            : ThemeModePreference.light,
        primaryColor: themeSettings.primaryColor,
      ),
      darkTheme: AppTheme.getThemeData(
        preference: ThemeModePreference.dark,
        primaryColor: themeSettings.primaryColor,
      ),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
