import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../../core/database/database_manager.dart';

/// Provides a list of .db files currently present on the device
final localDatabaseFilesProvider = FutureProvider<List<File>>((ref) async {
  final dbManager = DatabaseManager();
  return await dbManager.listInstalledDatabaseFiles();
});

/// Maps file names back to potential database IDs
final installedDatabaseIdsProvider = Provider<AsyncValue<Set<String>>>((ref) {
  final filesAsync = ref.watch(localDatabaseFilesProvider);
  
  return filesAsync.whenData((files) {
    return files.map((f) {
      final base = p.basename(f.path);
      return base.replaceAll('.db', '');
    }).toSet();
  });
});
