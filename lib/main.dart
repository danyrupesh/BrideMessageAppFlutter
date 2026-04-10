import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/database/database_manager.dart';
import 'core/database/metadata/installed_database_registry.dart';
import 'core/database/sqlite_platform_bootstrap.dart';
import 'core/navigation/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/navigation/app_links_handler.dart';
import 'core/update/startup_update_coordinator.dart';
import 'package:protocol_handler/protocol_handler.dart';
import 'package:windows_single_instance/windows_single_instance.dart';
import 'dart:io';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await SqlitePlatformBootstrap.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await protocolHandler.register('bridemessage');
  }

  // Initialise metadata registry so the first DB check is fast.
  await InstalledDatabaseRegistry().hasAnyContent();

  // Log SQLite version & compile options for diagnostics.
  DatabaseManager.logSqliteDiagnostics();

  // Create a global ProviderContainer to access outside widgets
  final container = ProviderContainer();

  if (Platform.isWindows) {
    await WindowsSingleInstance.ensureSingleInstance(
      args,
      "bride_message_app_single_instance",
      onSecondWindow: (args) {
        if (args.isNotEmpty) {
          final uriString = args.firstWhere(
            (a) => a.startsWith('bridemessage:'),
            orElse: () => '',
          );
          if (uriString.isNotEmpty) {
            final uri = Uri.tryParse(uriString);
            if (uri != null) {
              container.read(appLinksHandlerProvider).processUriDirectly(uri);
            }
          }
        }
      },
    );
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const BrideMessageApp(),
    ),
  );
}

class BrideMessageApp extends ConsumerWidget {
  const BrideMessageApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Start listening for deep links
    ref.read(appLinksHandlerProvider);

    final router = ref.watch(appRouterProvider);
    final themeSettings = ref.watch(themeProvider);

    ThemeMode getThemeMode(ThemeModePreference pref) {
      switch (pref) {
        case ThemeModePreference.light:
        case ThemeModePreference.sepia:
        case ThemeModePreference.green:
        case ThemeModePreference.blue:
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
        preference: themeSettings.mode,
        primaryColor: themeSettings.primaryColor,
      ),
      darkTheme: AppTheme.getThemeData(
        preference: ThemeModePreference.dark,
        primaryColor: themeSettings.primaryColor,
      ),
      routerConfig: router,
      builder: (context, child) {
        return StartupUpdateCoordinator(
          child: child ?? const SizedBox.shrink(),
        );
      },
      debugShowCheckedModeBanner: false,
    );
  }
}
