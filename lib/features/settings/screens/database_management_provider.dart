import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/metadata/installed_content_provider.dart';
import '../../../core/database/metadata/installed_database_model.dart';
import '../../../core/database/metadata/installed_database_registry.dart';

/// Loads all installed databases from the metadata registry and supports
/// refresh after mutations (delete, re-import, etc).
class InstalledDbListNotifier
    extends AsyncNotifier<List<InstalledDatabase>> {
  @override
  Future<List<InstalledDatabase>> build() async {
    final registry = ref.read(installedDbRegistryProvider);
    return registry.getAll();
  }

  Future<void> refreshList() async {
    state = const AsyncLoading();
    final registry = ref.read(installedDbRegistryProvider);
    final items = await registry.getAll();
    state = AsyncData(items);
  }
}

final installedDbListProvider =
    AsyncNotifierProvider<InstalledDbListNotifier, List<InstalledDatabase>>(
  InstalledDbListNotifier.new,
);
