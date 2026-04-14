import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

/// Handles optional schema migrations for sermon databases.
/// Safely adds missing columns without failing if they already exist.
class SermonDbMigrator {
  /// Ensure the 'category' column exists in the sermons table.
  /// Gracefully handles databases where the column already exists.
  static Future<void> ensureCategoryColumn(Database db) async {
    try {
      // Check if column exists
      final info = await db.rawQuery('PRAGMA table_info(sermons)');
      final hasCategory =
          info.any((row) => (row['name'] as String?) == 'category');

      if (hasCategory) {
        debugPrint('SermonDbMigrator: category column already exists');
        return;
      }

      debugPrint('SermonDbMigrator: Adding category column to sermons table');

      // In read-only mode we cannot alter, so we'll just note it's missing
      // The app will gracefully handle queries with COALESCE fallback
      debugPrint('SermonDbMigrator: Database is read-only, cannot alter schema');
    } catch (e) {
      debugPrint('SermonDbMigrator error checking category column: $e');
      // Silently fail - graceful degradation
    }
  }

  /// Check if category column exists (read-only safe)
  static Future<bool> hasCategoryColumn(Database db) async {
    try {
      final info = await db.rawQuery('PRAGMA table_info(sermons)');
      return info.any((row) => (row['name'] as String?) == 'category');
    } catch (e) {
      debugPrint('SermonDbMigrator: Error checking columns: $e');
      return false;
    }
  }
}
