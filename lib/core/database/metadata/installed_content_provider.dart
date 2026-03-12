import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'installed_database_model.dart';
import 'installed_database_registry.dart';

final installedDbRegistryProvider = Provider<InstalledDatabaseRegistry>(
  (_) => InstalledDatabaseRegistry(),
);

/// Mirrors Android's checkAnyDatabasesInstalled().
/// True if Bible or Sermon databases are installed (metadata + file scan fallback).
/// The notifier supports a session-level skip so the user can reach Home without
/// importing — next cold start will re-check real content and route accordingly.
class HasInstalledContentNotifier extends AsyncNotifier<bool> {
  bool _skippedThisSession = false;

  @override
  Future<bool> build() async {
    if (_skippedThisSession) return true;
    return ref
        .read(installedDbRegistryProvider)
        .hasAnyContent(allowFileFallback: false);
  }

  /// Called after a successful import to force re-evaluation.
  Future<void> refresh() async {
    _skippedThisSession = false;
    state = const AsyncLoading();
    state = AsyncData(
      await ref
          .read(installedDbRegistryProvider)
          .hasAnyContent(allowFileFallback: false),
    );
  }

  /// Session-only skip: routes to Home without persisting anything.
  /// On next cold start the real DB check runs again.
  void skipForSession() {
    _skippedThisSession = true;
    state = const AsyncData(true);
  }
}

final hasInstalledContentProvider =
    AsyncNotifierProvider<HasInstalledContentNotifier, bool>(
      HasInstalledContentNotifier.new,
    );

/// Resolves the default installed database for a given (type, language) pair.
final defaultInstalledDbProvider =
    FutureProvider.family<InstalledDatabase?, (DbType, String)>((
      ref,
      args,
    ) async {
      final registry = ref.read(installedDbRegistryProvider);
      // Try metadata default first, then any match for that language.
      return await registry.getDefault(args.$1, args.$2) ??
          await registry.getFirstByTypeAndLanguage(args.$1, args.$2);
    });
