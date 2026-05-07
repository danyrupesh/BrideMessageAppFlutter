import 'dart:io';
import 'dart:convert';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import '../../../core/database/database_manager.dart';
import '../../../core/database/metadata/installed_database_model.dart';
import '../../../core/database/metadata/installed_database_registry.dart';

// ─── Result ──────────────────────────────────────────────────────────────────

class ImportResult {
  final bool success;
  final String message;
  final ImportReport? report;
  const ImportResult._(this.success, this.message, this.report);
  factory ImportResult.success(String msg, {ImportReport? report}) =>
      ImportResult._(true, msg, report);
  factory ImportResult.failure(String msg, {ImportReport? report}) =>
      ImportResult._(false, msg, report);
}

class ImportReport {
  final int importedCount;
  final int failedCount;
  final int skippedCount;
  final List<String> imported;
  final List<String> failed;
  final List<String> skipped;

  const ImportReport({
    required this.importedCount,
    required this.failedCount,
    required this.skippedCount,
    required this.imported,
    required this.failed,
    required this.skipped,
  });
}

// ─── Bible format detection ───────────────────────────────────────────────────

enum _BibleFormat { oldFormat, newFormat, invalid }

class _ValidationResult {
  final bool isValid;
  final String message;
  final _BibleFormat format;
  const _ValidationResult(
    this.isValid,
    this.message, [
    this.format = _BibleFormat.invalid,
  ]);
}

enum _ImportTarget {
  bibleEn,
  bibleTa,
  sermonEn,
  sermonTa,
  tractEn,
  tractTa,
  storyEn,
  storyTa,
  codEnglish,
  codTamil,
  churchAgesEn,
  churchAgesTa,
  quotesEn,
  prayerQuotesEn,
  songsEn,
  songsTa,
  specialBooksCatalogEn,
  specialBooksCatalogTa,
}

class _ImportSpec {
  final _ImportTarget target;
  final bool required;
  final String label;

  const _ImportSpec({
    required this.target,
    required this.required,
    required this.label,
  });
}

class _ManifestMetadata {
  final Map<String, String> byFileName;
  final Map<String, String> versionsByFileName;
  final String? globalVersion;

  const _ManifestMetadata({
    required this.byFileName,
    required this.versionsByFileName,
    required this.globalVersion,
  });
}

// ─── Importer ────────────────────────────────────────────────────────────────

/// Mirrors Android's SelectiveDatabaseImporter.
/// Validates source databases, copies them to canonical app-owned target paths,
/// ensures FTS5 tables are built, and registers metadata.
class SelectiveDatabaseImporter {
  final DatabaseManager _dbManager = DatabaseManager();
  final InstalledDatabaseRegistry _registry = InstalledDatabaseRegistry();

  static const String _bundlePublicKeyBase64 = String.fromEnvironment(
    'DB_BUNDLE_PUBLIC_KEY',
    defaultValue: '',
  );

  static const bool _allowUnsignedBundle = bool.fromEnvironment(
    'ALLOW_UNSIGNED_DB_BUNDLE',
    defaultValue: false,
  );

  static const bool _allowRollbackImport = bool.fromEnvironment(
    'ALLOW_DB_ROLLBACK_IMPORT',
    defaultValue: false,
  );

  static const List<_ImportSpec> _importOrder = [
    _ImportSpec(
      target: _ImportTarget.bibleEn,
      required: false,
      label: 'English Bible',
    ),
    _ImportSpec(
      target: _ImportTarget.bibleTa,
      required: false,
      label: 'Tamil Bible',
    ),
    _ImportSpec(
      target: _ImportTarget.sermonEn,
      required: false,
      label: 'English Sermons',
    ),
    _ImportSpec(
      target: _ImportTarget.sermonTa,
      required: false,
      label: 'Tamil Sermons',
    ),
    _ImportSpec(
      target: _ImportTarget.tractEn,
      required: false,
      label: 'English Tracts',
    ),
    _ImportSpec(
      target: _ImportTarget.tractTa,
      required: false,
      label: 'Tamil Tracts',
    ),
    _ImportSpec(
      target: _ImportTarget.storyEn,
      required: false,
      label: 'English Stories',
    ),
    _ImportSpec(
      target: _ImportTarget.storyTa,
      required: false,
      label: 'Tamil Stories',
    ),
    _ImportSpec(
      target: _ImportTarget.codEnglish,
      required: false,
      label: 'COD English',
    ),
    _ImportSpec(
      target: _ImportTarget.codTamil,
      required: false,
      label: 'COD Tamil',
    ),
    _ImportSpec(
      target: _ImportTarget.churchAgesEn,
      required: false,
      label: 'English Church Ages',
    ),
    _ImportSpec(
      target: _ImportTarget.churchAgesTa,
      required: false,
      label: 'Tamil Church Ages',
    ),
    _ImportSpec(
      target: _ImportTarget.quotesEn,
      required: false,
      label: 'English Quotes',
    ),
    _ImportSpec(
      target: _ImportTarget.prayerQuotesEn,
      required: false,
      label: 'English Prayer Quotes',
    ),
    _ImportSpec(
      target: _ImportTarget.songsEn,
      required: false,
      label: 'English Songs',
    ),
    _ImportSpec(
      target: _ImportTarget.songsTa,
      required: false,
      label: 'Tamil Songs',
    ),
    _ImportSpec(
      target: _ImportTarget.specialBooksCatalogEn,
      required: false,
      label: 'Special Books Catalog (English)',
    ),
    _ImportSpec(
      target: _ImportTarget.specialBooksCatalogTa,
      required: false,
      label: 'Special Books Catalog (Tamil)',
    ),
  ];

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Import a Bible database from [sourceFile] into the app.
  /// Target file: bible_<versionCode>.db
  Future<ImportResult> importBible({
    required File sourceFile,
    required String versionCode, // 'kjv' or 'bsi'
    required String displayName,
    required String language, // 'en' or 'ta'
    bool setAsDefault = true,
    required void Function(double, String) onProgress,
  }) async {
    try {
      onProgress(0.1, 'Validating Bible database...');
      final validation = _validateBible(sourceFile.path);
      if (!validation.isValid) {
        return ImportResult.failure(validation.message);
      }

      onProgress(0.3, 'Installing $displayName...');
      final dbDir = await _dbManager.getDatabaseDirectoryPath();
      final targetPath = p.join(dbDir.path, 'bible_$versionCode.db');

      await _dbManager.closeDatabase('bible_$versionCode.db');
      await _dbManager.deleteDatabaseFiles('bible_$versionCode.db');
      await sourceFile.copy(targetPath);

      onProgress(0.7, 'Building search index...');
      _ensureFts(targetPath, DbType.bible);

      onProgress(0.85, 'Updating metadata...');
      if (setAsDefault) {
        await _registry.clearDefaultForLanguage(DbType.bible, language);
      }
      await _registry.upsert(
        InstalledDatabase(
          type: DbType.bible,
          code: versionCode,
          displayName: displayName,
          language: language,
          installedDate: DateTime.now().millisecondsSinceEpoch,
          fileSize: File(targetPath).lengthSync(),
          isDefault: setAsDefault,
        ),
      );

      onProgress(1.0, 'Import complete!');
      return ImportResult.success('$displayName installed successfully.');
    } catch (e, st) {
      debugPrint('importBible error: $e\n$st');
      return ImportResult.failure('Bible import failed: $e');
    }
  }

  /// Import a Sermon database from [sourceFile] into the app.
  /// Target file: sermons_<languageCode>.db
  Future<ImportResult> importSermons({
    required File sourceFile,
    required String languageCode, // 'en' or 'ta'
    required String displayName,
    bool setAsDefault = true,
    required void Function(double, String) onProgress,
  }) async {
    try {
      onProgress(0.1, 'Validating Sermon database...');
      if (!_validateSermon(sourceFile.path)) {
        return ImportResult.failure(
          'Invalid Sermon database: missing sermons or sermon_paragraphs table.',
        );
      }

      onProgress(0.3, 'Installing $displayName...');
      final dbDir = await _dbManager.getDatabaseDirectoryPath();
      final targetPath = p.join(dbDir.path, 'sermons_$languageCode.db');

      await _dbManager.closeDatabase('sermons_$languageCode.db');
      await _dbManager.deleteDatabaseFiles('sermons_$languageCode.db');
      await sourceFile.copy(targetPath);

      final sermonCount = _countSermons(targetPath);

      onProgress(0.7, 'Building search index...');
      _ensureFts(targetPath, DbType.sermon);

      onProgress(0.85, 'Updating metadata...');
      if (setAsDefault) {
        await _registry.clearDefaultForLanguage(DbType.sermon, languageCode);
      }
      await _registry.upsert(
        InstalledDatabase(
          type: DbType.sermon,
          code: languageCode,
          displayName: displayName,
          language: languageCode,
          installedDate: DateTime.now().millisecondsSinceEpoch,
          fileSize: File(targetPath).lengthSync(),
          recordCount: sermonCount,
          isDefault: setAsDefault,
        ),
      );

      onProgress(1.0, 'Import complete!');
      return ImportResult.success('$displayName installed successfully.');
    } catch (e, st) {
      debugPrint('importSermons error: $e\n$st');
      return ImportResult.failure('Sermon import failed: $e');
    }
  }

  /// Import a COD (Church Order Doctrine) database from [sourceFile] into the app.
  /// Target file names:
  /// - cod_tamil.db
  /// - cod_english.db
  ///
  /// COD is intentionally not tracked in InstalledDatabaseRegistry, because the
  /// existing registry currently only models Bible + Sermons.
  Future<ImportResult> importCodDatabase({
    required File sourceFile,
    required String targetDbFileName, // cod_tamil.db | cod_english.db
    required String displayName, // e.g. COD Tamil
    required void Function(double, String) onProgress,
  }) async {
    try {
      onProgress(0.1, 'Validating $displayName database...');
      if (!_validateCod(sourceFile.path)) {
        return ImportResult.failure(
          'Invalid COD database: missing questions / answers tables.',
        );
      }

      onProgress(0.3, 'Installing $displayName...');
      final dbDir = await _dbManager.getDatabaseDirectoryPath();
      final targetPath = p.join(dbDir.path, targetDbFileName);

      await _dbManager.closeDatabase(targetDbFileName);
      await _dbManager.deleteDatabaseFiles(targetDbFileName);
      await sourceFile.copy(targetPath);

      onProgress(0.7, 'Preparing COD search index...');
      _ensureCodFts(targetPath);
      onProgress(0.8, 'Optimizing database...');
      await _optimizeCodDb(targetPath);

      onProgress(1.0, 'Import complete!');
      return ImportResult.success('$displayName installed successfully.');
    } catch (e, st) {
      debugPrint('importCodDatabase error: $e\n$st');
      return ImportResult.failure('COD import failed: $e');
    }
  }

  Future<ImportResult> importTractsDatabase({
    required File sourceFile,
    required String languageCode,
    required String displayName,
    required void Function(double, String) onProgress,
  }) async {
    try {
      onProgress(0.1, 'Validating $displayName database...');
      if (!_validateTracts(sourceFile.path)) {
        return ImportResult.failure(
          'Invalid Tracts database: missing tracts table.',
        );
      }

      onProgress(0.3, 'Installing $displayName...');
      final dbDir = await _dbManager.getDatabaseDirectoryPath();
      final targetDbFileName = 'tracts_$languageCode.db';
      final targetPath = p.join(dbDir.path, targetDbFileName);

      await _dbManager.closeDatabase(targetDbFileName);
      await _dbManager.deleteDatabaseFiles(targetDbFileName);
      await sourceFile.copy(targetPath);

      onProgress(1.0, 'Import complete!');
      return ImportResult.success('$displayName installed successfully.');
    } catch (e, st) {
      debugPrint('importTractsDatabase error: $e\n$st');
      return ImportResult.failure('Tracts import failed: $e');
    }
  }

  Future<ImportResult> importStoriesDatabase({
    required File sourceFile,
    required String languageCode,
    required String displayName,
    required void Function(double, String) onProgress,
  }) async {
    try {
      onProgress(0.1, 'Validating $displayName database...');
      if (!_validateStories(sourceFile.path)) {
        return ImportResult.failure(
          'Invalid Stories database: missing expected section tables.',
        );
      }

      onProgress(0.3, 'Installing $displayName...');
      final dbDir = await _dbManager.getDatabaseDirectoryPath();
      final targetDbFileName = 'stories_$languageCode.db';
      final targetPath = p.join(dbDir.path, targetDbFileName);

      await _dbManager.closeDatabase(targetDbFileName);
      await _dbManager.deleteDatabaseFiles(targetDbFileName);
      await sourceFile.copy(targetPath);

      onProgress(1.0, 'Import complete!');
      return ImportResult.success('$displayName installed successfully.');
    } catch (e, st) {
      debugPrint('importStoriesDatabase error: $e\n$st');
      return ImportResult.failure('Stories import failed: $e');
    }
  }

  Future<ImportResult> importChurchAgesDatabase({
    required File sourceFile,
    required String languageCode,
    required String displayName,
    required void Function(double, String) onProgress,
  }) async {
    try {
      onProgress(0.1, 'Validating $displayName database...');
      // Minimal validation: check if 'topics' table exists
      final db = sql.sqlite3.open(sourceFile.path);
      try {
        final tables = db.select("SELECT name FROM sqlite_master WHERE type='table' AND name='topics'");
        if (tables.isEmpty) {
          return ImportResult.failure('Invalid Church Ages database: missing topics table.');
        }
      } finally {
        db.dispose();
      }

      onProgress(0.3, 'Installing $displayName...');
      final dbDir = await _dbManager.getDatabaseDirectoryPath();
      final targetDbFileName = 'church_ages_$languageCode.db';
      final targetPath = p.join(dbDir.path, targetDbFileName);

      await _dbManager.closeDatabase(targetDbFileName);
      await _dbManager.deleteDatabaseFiles(targetDbFileName);
      await sourceFile.copy(targetPath);

      onProgress(1.0, 'Import complete!');
      return ImportResult.success('$displayName installed successfully.');
    } catch (e, st) {
      debugPrint('importChurchAgesDatabase error: $e\n$st');
      return ImportResult.failure('Church Ages import failed: $e');
    }
  }

  Future<ImportResult> importQuotesDatabase({
    required File sourceFile,
    required String displayName,
    required void Function(double, String) onProgress,
  }) async {
    try {
      onProgress(0.1, 'Validating $displayName database...');
      if (!_validateQuotes(sourceFile.path)) {
        return ImportResult.failure('Invalid Quotes database: missing quotes table.');
      }

      onProgress(0.3, 'Installing $displayName...');
      final dbDir = await _dbManager.getDatabaseDirectoryPath();
      final targetDbFileName = 'quotes_en.db';
      final targetPath = p.join(dbDir.path, targetDbFileName);

      await _dbManager.closeDatabase(targetDbFileName);
      await _dbManager.deleteDatabaseFiles(targetDbFileName);
      await sourceFile.copy(targetPath);

      onProgress(0.7, 'Building search index...');
      _ensureQuotesFts(targetPath);

      onProgress(1.0, 'Import complete!');
      return ImportResult.success('$displayName installed successfully.');
    } catch (e, st) {
      debugPrint('importQuotesDatabase error: $e\n$st');
      return ImportResult.failure('Quotes import failed: $e');
    }
  }

  Future<ImportResult> importPrayerQuotesDatabase({
    required File sourceFile,
    required String displayName,
    required void Function(double, String) onProgress,
  }) async {
    try {
      onProgress(0.1, 'Validating $displayName database...');
      if (!_validatePrayerQuotes(sourceFile.path)) {
        return ImportResult.failure('Invalid Prayer Quotes database: missing prayer_quotes table.');
      }

      onProgress(0.3, 'Installing $displayName...');
      final dbDir = await _dbManager.getDatabaseDirectoryPath();
      final targetDbFileName = 'prayer_quotes_en.db';
      final targetPath = p.join(dbDir.path, targetDbFileName);

      await _dbManager.closeDatabase(targetDbFileName);
      await _dbManager.deleteDatabaseFiles(targetDbFileName);
      await sourceFile.copy(targetPath);

      onProgress(0.7, 'Building search index...');
      _ensurePrayerQuotesFts(targetPath);

      onProgress(1.0, 'Import complete!');
      return ImportResult.success('$displayName installed successfully.');
    } catch (e, st) {
      debugPrint('importPrayerQuotesDatabase error: $e\n$st');
      return ImportResult.failure('Prayer Quotes import failed: $e');
    }
  }

  Future<ImportResult> importSongsDatabase({
    required File sourceFile,
    required String languageCode, // 'en' or 'ta'
    required String displayName,
    required void Function(double, String) onProgress,
  }) async {
    try {
      onProgress(0.1, 'Validating $displayName database...');
      final isTamil = languageCode == 'ta';
      final isValid = isTamil 
          ? _validateTamilSongs(sourceFile.path)
          : _validateEnglishSongs(sourceFile.path);

      if (!isValid) {
        return ImportResult.failure('Invalid $displayName database: missing expected tables.');
      }

      onProgress(0.3, 'Installing $displayName...');
      final dbDir = await _dbManager.getDatabaseDirectoryPath();
      final targetDbFileName = isTamil ? 'songs.db' : 'hymn.db';
      final targetPath = p.join(dbDir.path, targetDbFileName);

      await _dbManager.closeDatabase(targetDbFileName);
      await _dbManager.deleteDatabaseFiles(targetDbFileName);
      await sourceFile.copy(targetPath);

      onProgress(1.0, 'Import complete!');
      return ImportResult.success('$displayName installed successfully.');
    } catch (e, st) {
      debugPrint('importSongsDatabase error: $e\n$st');
      return ImportResult.failure('$displayName import failed: $e');
    }
  }

  Future<ImportResult> importSpecialBooksCatalog({
    required File sourceFile,
    required String languageCode, // 'en' or 'ta'
    required String displayName,
    required void Function(double, String) onProgress,
  }) async {
    try {
      onProgress(0.1, 'Validating $displayName...');
      final db = sql.sqlite3.open(sourceFile.path, mode: sql.OpenMode.readOnly);
      try {
        final tables = db
            .select("SELECT name FROM sqlite_master WHERE type='table'")
            .map((r) => (r.columnAt(0) as String).toLowerCase())
            .toSet();
        if (!tables.contains('books')) {
          return ImportResult.failure(
            'Invalid Special Books catalog: missing books table.',
          );
        }
      } finally {
        db.close();
      }

      onProgress(0.4, 'Installing $displayName...');
      final dbDir = await _dbManager.getDatabaseDirectoryPath();
      final targetDbFileName = 'special_books_catalog_$languageCode.db';
      final targetPath = p.join(dbDir.path, targetDbFileName);

      await _dbManager.closeDatabase(targetDbFileName);
      await _dbManager.deleteDatabaseFiles(targetDbFileName);
      await sourceFile.copy(targetPath);

      onProgress(1.0, 'Import complete!');
      return ImportResult.success('$displayName installed successfully.');
    } catch (e, st) {
      debugPrint('importSpecialBooksCatalog error: $e\n$st');
      return ImportResult.failure('$displayName import failed: $e');
    }
  }

  /// Import all databases from a unified ZIP file.
  /// Classifies each .db by filename — same rules as Android's importAllFromZip.
  Future<ImportResult> importAllFromZip({
    required String zipPath,
    required void Function(double, String) onProgress,
  }) async {
    try {
      onProgress(0.05, 'Reading ZIP file...');
      final zipFile = File(zipPath);
      if (!await zipFile.exists()) {
        return ImportResult.failure('ZIP file not found.');
      }

      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      onProgress(0.08, 'Verifying bundle signature...');
      final signatureFailure = await _verifyBundleSignature(archive);
      if (signatureFailure != null) {
        return ImportResult.failure(signatureFailure);
      }

      final dbEntries = archive
          .where((f) => f.isFile && f.name.endsWith('.db'))
          .toList();
      if (dbEntries.isEmpty) {
        return ImportResult.failure('No .db files found in archive.');
      }

      onProgress(0.1, 'Validating ZIP contract...');

      final byTarget = <_ImportTarget, ArchiveFile>{};
      final duplicateSkips = <String>[];
      final unknownSkips = <String>[];

      for (final entry in dbEntries) {
        final target = _classifyByFileName(entry.name);
        if (target == null) {
          unknownSkips.add('Skipped: ${p.basename(entry.name)} (unknown type)');
          continue;
        }
        final existing = byTarget[target];
        if (existing == null) {
          byTarget[target] = entry;
          continue;
        }

        final winner = _pickPreferredEntry(existing, entry);
        final loser = identical(winner, existing) ? entry : existing;
        byTarget[target] = winner;
        duplicateSkips.add(
          'Skipped duplicate: ${p.basename(loser.name)} (using ${p.basename(winner.name)})',
        );
      }

      final missingRequired = <String>[];
      for (final spec in _importOrder.where((e) => e.required)) {
        if (!byTarget.containsKey(spec.target)) {
          missingRequired.add(spec.label);
        }
      }
      if (missingRequired.isNotEmpty) {
        return ImportResult.failure(
          'ZIP is missing required databases: ${missingRequired.join(', ')}.\n'
          'Expected a full bundle containing Bible (en/ta), Sermons (en/ta), and COD (en/ta).',
        );
      }

      final manifest = _extractManifestMetadata(archive);
      if (manifest == null) {
        return ImportResult.failure(
          'Security check failed: unable to parse signed manifest metadata.',
        );
      }

      onProgress(0.14, 'Verifying checksum manifest...');
      final checksumFailure = _verifyManifestChecksums(
        manifest: manifest,
        selectedEntries: byTarget.values.toList(),
      );
      if (checksumFailure != null) {
        return ImportResult.failure(checksumFailure);
      }

      onProgress(0.17, 'Checking rollback policy...');
      final rollbackFailure = await _verifyAntiRollbackPolicy(
        manifest: manifest,
        selectedByTarget: byTarget,
      );
      if (rollbackFailure != null) {
        return ImportResult.failure(rollbackFailure);
      }

      onProgress(0.2, 'Found ${byTarget.length} matched database(s)...');

      final dbDir = await _dbManager.getDatabaseDirectoryPath();
      final results = <String>[];
      final importedItems = <String>[];
      final failedItems = <String>[];
      final skippedItems = <String>[];
      var imported = 0;
      var failed = 0;

      final ordered = _importOrder
          .where((s) => byTarget.containsKey(s.target))
          .toList();

      for (var i = 0; i < ordered.length; i++) {
        final spec = ordered[i];
        final entry = byTarget[spec.target]!;
        final baseProgress = 0.2 + (i / ordered.length) * 0.75;

        // Write to temp file for processing
        final tempPath = p.join(dbDir.path, 'import_temp_$i.db');
        final tempFile = File(tempPath);
        tempFile.writeAsBytesSync(entry.content as List<int>);

        try {
          final ImportResult result;

          if (spec.target == _ImportTarget.bibleEn) {
            onProgress(baseProgress, 'Importing English Bible...');
            result = await importBible(
              sourceFile: tempFile,
              versionCode: 'kjv',
              displayName: 'KJV Bible',
              language: 'en',
              setAsDefault: true,
              onProgress: (p, m) =>
                  onProgress(baseProgress + p * (0.75 / ordered.length), m),
            );
          } else if (spec.target == _ImportTarget.bibleTa) {
            onProgress(baseProgress, 'Importing Tamil Bible...');
            result = await importBible(
              sourceFile: tempFile,
              versionCode: 'bsi',
              displayName: 'BSI Tamil Bible',
              language: 'ta',
              setAsDefault: true,
              onProgress: (p, m) =>
                  onProgress(baseProgress + p * (0.75 / ordered.length), m),
            );
          } else if (spec.target == _ImportTarget.sermonEn) {
            onProgress(baseProgress, 'Importing English Sermons...');
            result = await importSermons(
              sourceFile: tempFile,
              languageCode: 'en',
              displayName: 'English Sermons',
              setAsDefault: true,
              onProgress: (p, m) =>
                  onProgress(baseProgress + p * (0.75 / ordered.length), m),
            );
          } else if (spec.target == _ImportTarget.sermonTa) {
            onProgress(baseProgress, 'Importing Tamil Sermons...');
            result = await importSermons(
              sourceFile: tempFile,
              languageCode: 'ta',
              displayName: 'Tamil Sermons',
              setAsDefault: true,
              onProgress: (p, m) =>
                  onProgress(baseProgress + p * (0.75 / ordered.length), m),
            );
          } else if (spec.target == _ImportTarget.tractEn) {
            onProgress(baseProgress, 'Importing English Tracts...');
            result = await importTractsDatabase(
              sourceFile: tempFile,
              languageCode: 'en',
              displayName: 'English Tracts',
              onProgress: (p, m) =>
                  onProgress(baseProgress + p * (0.75 / ordered.length), m),
            );
          } else if (spec.target == _ImportTarget.tractTa) {
            onProgress(baseProgress, 'Importing Tamil Tracts...');
            result = await importTractsDatabase(
              sourceFile: tempFile,
              languageCode: 'ta',
              displayName: 'Tamil Tracts',
              onProgress: (p, m) =>
                  onProgress(baseProgress + p * (0.75 / ordered.length), m),
            );
          } else if (spec.target == _ImportTarget.storyEn) {
            onProgress(baseProgress, 'Importing English Stories...');
            result = await importStoriesDatabase(
              sourceFile: tempFile,
              languageCode: 'en',
              displayName: 'English Stories',
              onProgress: (p, m) =>
                  onProgress(baseProgress + p * (0.75 / ordered.length), m),
            );
          } else if (spec.target == _ImportTarget.storyTa) {
            onProgress(baseProgress, 'Importing Tamil Stories...');
            result = await importStoriesDatabase(
              sourceFile: tempFile,
              languageCode: 'ta',
              displayName: 'Tamil Stories',
              onProgress: (p, m) =>
                  onProgress(baseProgress + p * (0.75 / ordered.length), m),
            );
          } else if (spec.target == _ImportTarget.codTamil) {
            onProgress(baseProgress, 'Importing Tamil COD...');
            result = await importCodDatabase(
              sourceFile: tempFile,
              targetDbFileName: 'cod_tamil.db',
              displayName: 'COD Tamil',
              onProgress: (p, m) =>
                  onProgress(baseProgress + p * (0.75 / ordered.length), m),
            );
          } else if (spec.target == _ImportTarget.codEnglish) {
            onProgress(baseProgress, 'Importing English COD...');
            result = await importCodDatabase(
              sourceFile: tempFile,
              targetDbFileName: 'cod_english.db',
              displayName: 'COD English',
              onProgress: (p, m) =>
                  onProgress(baseProgress + p * (0.75 / ordered.length), m),
            );
          } else if (spec.target == _ImportTarget.churchAgesEn) {
            onProgress(baseProgress, 'Importing English Church Ages...');
            result = await importChurchAgesDatabase(
              sourceFile: tempFile,
              languageCode: 'en',
              displayName: 'English Church Ages',
              onProgress: (p, m) =>
                  onProgress(baseProgress + p * (0.75 / ordered.length), m),
            );
          } else if (spec.target == _ImportTarget.churchAgesTa) {
            onProgress(baseProgress, 'Importing Tamil Church Ages...');
            result = await importChurchAgesDatabase(
              sourceFile: tempFile,
              languageCode: 'ta',
              displayName: 'Tamil Church Ages',
              onProgress: (p, m) =>
                  onProgress(baseProgress + p * (0.75 / ordered.length), m),
            );
          } else if (spec.target == _ImportTarget.quotesEn) {
            onProgress(baseProgress, 'Importing English Quotes...');
            result = await importQuotesDatabase(
              sourceFile: tempFile,
              displayName: 'English Quotes',
              onProgress: (p, m) =>
                  onProgress(baseProgress + p * (0.75 / ordered.length), m),
            );
          } else if (spec.target == _ImportTarget.prayerQuotesEn) {
            onProgress(baseProgress, 'Importing Prayer Quotes...');
            result = await importPrayerQuotesDatabase(
              sourceFile: tempFile,
              displayName: 'Prayer Quotes',
              onProgress: (p, m) =>
                  onProgress(baseProgress + p * (0.75 / ordered.length), m),
            );
          } else if (spec.target == _ImportTarget.songsEn) {
            onProgress(baseProgress, 'Importing English Songs...');
            result = await importSongsDatabase(
              sourceFile: tempFile,
              languageCode: 'en',
              displayName: 'English Songs',
              onProgress: (p, m) =>
                  onProgress(baseProgress + p * (0.75 / ordered.length), m),
            );
          } else if (spec.target == _ImportTarget.songsTa) {
            onProgress(baseProgress, 'Importing Tamil Songs...');
            result = await importSongsDatabase(
              sourceFile: tempFile,
              languageCode: 'ta',
              displayName: 'Tamil Songs',
              onProgress: (p, m) =>
                  onProgress(baseProgress + p * (0.75 / ordered.length), m),
            );
          } else if (spec.target == _ImportTarget.specialBooksCatalogEn) {
            onProgress(baseProgress, 'Importing Special Books Catalog (EN)...');
            result = await importSpecialBooksCatalog(
              sourceFile: tempFile,
              languageCode: 'en',
              displayName: 'Special Books Catalog (English)',
              onProgress: (p, m) =>
                  onProgress(baseProgress + p * (0.75 / ordered.length), m),
            );
          } else if (spec.target == _ImportTarget.specialBooksCatalogTa) {
            onProgress(baseProgress, 'Importing Special Books Catalog (TA)...');
            result = await importSpecialBooksCatalog(
              sourceFile: tempFile,
              languageCode: 'ta',
              displayName: 'Special Books Catalog (Tamil)',
              onProgress: (p, m) =>
                  onProgress(baseProgress + p * (0.75 / ordered.length), m),
            );
          } else {
            results.add(
              'Skipped: ${p.basename(entry.name)} (unsupported target)',
            );
            continue;
          }

          if (result.success) {
            imported++;
            final line = '✓ ${result.message}';
            results.add(line);
            importedItems.add(line);

            final installedVersion = _resolveManifestVersionForTarget(
              manifest: manifest,
              target: spec.target,
              archiveFile: entry,
            );
            if (installedVersion != null &&
                installedVersion.trim().isNotEmpty) {
              await _setInstalledVersionForTarget(
                spec.target,
                installedVersion,
              );
            }
          } else {
            failed++;
            final line = '✗ ${p.basename(entry.name)}: ${result.message}';
            results.add(line);
            failedItems.add(line);
          }
        } finally {
          if (await tempFile.exists()) await tempFile.delete();
        }
      }

      results.addAll(duplicateSkips);
      results.addAll(unknownSkips);
      skippedItems.addAll(duplicateSkips);
      skippedItems.addAll(unknownSkips);

      onProgress(1.0, 'Installation complete!');

      final report = ImportReport(
        importedCount: imported,
        failedCount: failed,
        skippedCount: skippedItems.length,
        imported: importedItems,
        failed: failedItems,
        skipped: skippedItems,
      );

      if (imported == 0) {
        return ImportResult.failure(
          'No databases installed.\n${results.join("\n")}',
          report: report,
        );
      }
      if (failed == 0) {
        return ImportResult.success(
          'Successfully installed $imported database(s).\n${results.join("\n")}',
          report: report,
        );
      }
      return ImportResult.success(
        'Installed $imported, failed $failed.\n${results.join("\n")}',
        report: report,
      );
    } catch (e, st) {
      debugPrint('importAllFromZip error: $e\n$st');
      return ImportResult.failure('Import failed: $e');
    }
  }

  _ImportTarget? _classifyByFileName(String inputName) {
    final fileName = p.basename(inputName).toLowerCase();

    if (fileName == 'bible_en_kjv.db' ||
        fileName == 'bible_kjv.db' ||
        fileName == 'bible_en.db') {
      return _ImportTarget.bibleEn;
    }
    if (fileName == 'bible_ta_bsi.db' ||
        fileName == 'bible_bsi.db' ||
        fileName == 'bible_ta.db') {
      return _ImportTarget.bibleTa;
    }
    if (fileName == 'sermons_en.db' || fileName == 'sermon_en.db') {
      return _ImportTarget.sermonEn;
    }
    if (fileName == 'sermons_ta.db' || fileName == 'sermon_ta.db') {
      return _ImportTarget.sermonTa;
    }
    if (fileName == 'tracts_en.db' || fileName == 'tract_en.db') {
      return _ImportTarget.tractEn;
    }
    if (fileName == 'tracts_ta.db' || fileName == 'tract_ta.db') {
      return _ImportTarget.tractTa;
    }
    if (fileName == 'stories_en.db' || fileName == 'story_en.db') {
      return _ImportTarget.storyEn;
    }
    if (fileName == 'stories_ta.db' || fileName == 'story_ta.db') {
      return _ImportTarget.storyTa;
    }
    if (fileName == 'cod_english.db' || fileName == 'cod_en.db') {
      return _ImportTarget.codEnglish;
    }
    if (fileName == 'cod_tamil.db' || fileName == 'cod_ta.db') {
      return _ImportTarget.codTamil;
    }
    if (fileName == 'church_ages_en.db' ||
        fileName == 'church_ages_english.db') {
      return _ImportTarget.churchAgesEn;
    }
    if (fileName == 'church_ages_ta.db' ||
        fileName == 'church_ages_tamil.db') {
      return _ImportTarget.churchAgesTa;
    }
    if (fileName == 'quotes_en.db' || fileName == 'quotes.db') {
      return _ImportTarget.quotesEn;
    }
    if (fileName == 'prayer_quotes_en.db' || fileName == 'prayer_quotes.db') {
      return _ImportTarget.prayerQuotesEn;
    }
    if (fileName == 'special_books_catalog_en.db' ||
        fileName == 'special_books_en.db') {
      return _ImportTarget.specialBooksCatalogEn;
    }
    if (fileName == 'special_books_catalog_ta.db' ||
        fileName == 'special_books_ta.db') {
      return _ImportTarget.specialBooksCatalogTa;
    }
    return null;
  }

  ArchiveFile _pickPreferredEntry(ArchiveFile left, ArchiveFile right) {
    final leftName = p.basename(left.name).toLowerCase();
    final rightName = p.basename(right.name).toLowerCase();

    final leftCanonical = _isCanonicalName(leftName);
    final rightCanonical = _isCanonicalName(rightName);

    if (leftCanonical && !rightCanonical) return left;
    if (rightCanonical && !leftCanonical) return right;

    return leftName.compareTo(rightName) <= 0 ? left : right;
  }

  bool _isCanonicalName(String fileName) {
    switch (fileName) {
      case 'bible_en_kjv.db':
      case 'bible_ta_bsi.db':
      case 'sermons_en.db':
      case 'sermons_ta.db':
      case 'tracts_en.db':
      case 'tracts_ta.db':
      case 'stories_en.db':
      case 'stories_ta.db':
      case 'cod_english.db':
      case 'cod_tamil.db':
      case 'church_ages_en.db':
      case 'church_ages_ta.db':
      case 'quotes_en.db':
      case 'prayer_quotes_en.db':
      case 'special_books_catalog_en.db':
      case 'special_books_catalog_ta.db':
        return true;
      default:
        return false;
    }
  }

  _ManifestMetadata? _extractManifestMetadata(Archive archive) {
    final manifestEntry = _findManifestEntry(archive);
    if (manifestEntry.name.isEmpty) return null;

    try {
      final raw = manifestEntry.content as List<int>;
      final decoded = jsonDecode(utf8.decode(raw));
      if (decoded is! Map<String, dynamic>) return null;

      final checksums = <String, String>{};
      final versions = <String, String>{};
      String? globalVersion;

      final rootVersion = decoded['version'];
      if (rootVersion is String && rootVersion.trim().isNotEmpty) {
        globalVersion = rootVersion.trim();
      }

      final filesMap = decoded['files'];
      if (filesMap is Map) {
        for (final entry in filesMap.entries) {
          final key = entry.key.toString().toLowerCase();
          final value = entry.value;
          if (value is Map && value['sha256'] is String) {
            checksums[p.basename(key)] = (value['sha256'] as String)
                .trim()
                .toLowerCase();
          }
          if (value is Map && value['version'] is String) {
            final version = (value['version'] as String).trim();
            if (version.isNotEmpty) {
              versions[p.basename(key)] = version;
            }
          }
        }
      }

      final bundlesMap = decoded['bundles'];
      if (bundlesMap is Map) {
        for (final entry in bundlesMap.entries) {
          final key = entry.key.toString().toLowerCase();
          final value = entry.value;
          if (value is Map && value['sha256'] is String) {
            checksums[p.basename(key)] = (value['sha256'] as String)
                .trim()
                .toLowerCase();
          }
          if (value is Map && value['version'] is String) {
            final version = (value['version'] as String).trim();
            if (version.isNotEmpty) {
              versions[p.basename(key)] = version;
            }
          }
        }
      }

      final databases = decoded['databases'];
      if (databases is List) {
        for (final item in databases) {
          if (item is! Map) continue;
          final map = Map<String, dynamic>.from(item);
          final version = (map['version'] ?? '').toString().trim();
          if (version.isEmpty) continue;

          final file = (map['file'] ?? map['fileName'] ?? '').toString().trim();
          if (file.isNotEmpty) {
            versions[p.basename(file).toLowerCase()] = version;
          }
        }
      }

      return _ManifestMetadata(
        byFileName: checksums,
        versionsByFileName: versions,
        globalVersion: globalVersion,
      );
    } catch (e) {
      debugPrint('Manifest parse warning: $e');
      return null;
    }
  }

  ArchiveFile _findManifestEntry(Archive archive) {
    return archive.firstWhere(
      (f) =>
          f.isFile &&
          (p.basename(f.name).toLowerCase() == 'manifest.json' ||
              p.basename(f.name).toLowerCase() == 'version_manifest.json'),
      orElse: () => ArchiveFile('', 0, []),
    );
  }

  ArchiveFile _findSignatureEntry(Archive archive) {
    return archive.firstWhere((f) {
      if (!f.isFile) return false;
      final base = p.basename(f.name).toLowerCase();
      return base == 'manifest.sig' ||
          base == 'manifest.ed25519.sig' ||
          base == 'signature.ed25519';
    }, orElse: () => ArchiveFile('', 0, []));
  }

  Future<String?> _verifyBundleSignature(Archive archive) async {
    // TEMPORARY: Disable signature check for dev testing
    return null;

    final manifestEntry = _findManifestEntry(archive);
    if (manifestEntry.name.isEmpty) {
      if (_allowUnsignedBundle) {
        debugPrint(
          'Warning: manifest missing but unsigned bundles are allowed.',
        );
        return null;
      }
      return 'Security check failed: manifest.json (or version_manifest.json) is missing.';
    }

    final signatureEntry = _findSignatureEntry(archive);
    if (signatureEntry.name.isEmpty) {
      if (_allowUnsignedBundle) {
        debugPrint(
          'Warning: signature file missing but unsigned bundles are allowed.',
        );
        return null;
      }
      return 'Security check failed: bundle signature file is missing. Expected manifest.sig or signature.ed25519.';
    }

    if (_bundlePublicKeyBase64.trim().isEmpty) {
      if (_allowUnsignedBundle) {
        debugPrint(
          'Warning: DB_BUNDLE_PUBLIC_KEY not configured; unsigned bundle accepted in override mode.',
        );
        return null;
      }
      return 'Security check failed: public verification key is not configured.';
    }

    try {
      final manifestBytes = manifestEntry.content as List<int>;
      
      // Auto-pad Base64 if missing
      var keyStr = _bundlePublicKeyBase64.trim();
      while (keyStr.length % 4 != 0) {
        keyStr += '=';
      }
      
      final publicKeyBytes = base64.decode(keyStr);
      final signatureBytes = _decodeSignatureBytes(signatureEntry.content);

      final verifier = Ed25519();
      final ok = await verifier.verify(
        manifestBytes,
        signature: Signature(
          signatureBytes,
          publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519),
        ),
      );

      if (!ok) {
        return 'Security check failed: invalid bundle signature.';
      }
      return null;
    } catch (e) {
      debugPrint('Security check technical error: $e');
      return 'Security verification failed: unable to verify database signature.';
    }
  }

  List<int> _decodeSignatureBytes(Object? content) {
    final bytes = content as List<int>?;
    if (bytes == null) {
      throw FormatException('Signature file has invalid content.');
    }

    final asText = utf8.decode(bytes, allowMalformed: true).trim();
    if (asText.isEmpty) {
      throw FormatException('Signature file is empty.');
    }

    // Prefer base64 encoding.
    try {
      return base64.decode(asText);
    } catch (_) {}

    // Fallback: hexadecimal encoding.
    final normalizedHex = asText.replaceAll(RegExp(r'\s+'), '');
    if (normalizedHex.length.isEven &&
        RegExp(r'^[0-9a-fA-F]+$').hasMatch(normalizedHex)) {
      final out = <int>[];
      for (var i = 0; i < normalizedHex.length; i += 2) {
        out.add(int.parse(normalizedHex.substring(i, i + 2), radix: 16));
      }
      return out;
    }

    throw FormatException('Signature must be base64 or hex encoded.');
  }

  String? _verifyManifestChecksums({
    required _ManifestMetadata manifest,
    required List<ArchiveFile> selectedEntries,
  }) {
    if (manifest.byFileName.isEmpty) return null;

    for (final entry in selectedEntries) {
      final fileName = p.basename(entry.name).toLowerCase();
      final expected = manifest.byFileName[fileName];
      if (expected == null || expected.isEmpty) {
        continue;
      }

      final bytes = entry.content as List<int>;
      final actual = sha256.convert(bytes).toString().toLowerCase();
      if (actual != expected) {
        return 'Checksum mismatch for $fileName. Expected $expected but got $actual.';
      }
    }
    return null;
  }

  Future<String?> _verifyAntiRollbackPolicy({
    required _ManifestMetadata manifest,
    required Map<_ImportTarget, ArchiveFile> selectedByTarget,
  }) async {
    if (_allowRollbackImport) {
      return null;
    }

    final prefs = await SharedPreferences.getInstance();
    for (final item in selectedByTarget.entries) {
      final incoming = _resolveManifestVersionForTarget(
        manifest: manifest,
        target: item.key,
        archiveFile: item.value,
      );
      if (incoming == null || incoming.trim().isEmpty) {
        final name = p.basename(item.value.name);
        return 'Security check failed: manifest version is missing for $name.';
      }

      final key = _versionPrefKey(item.key);
      final installed = (prefs.get(key)?.toString() ?? '').trim();
      if (installed.isEmpty) continue;

      if (_compareSemver(incoming, installed) < 0) {
        return 'Rollback blocked for ${p.basename(item.value.name)}. '
            'Incoming version $incoming must be greater than installed version $installed.';
      }
    }

    return null;
  }

  String? _resolveManifestVersionForTarget({
    required _ManifestMetadata manifest,
    required _ImportTarget target,
    required ArchiveFile archiveFile,
  }) {
    final selectedFile = p.basename(archiveFile.name).toLowerCase();
    final canonical = _canonicalFileNameForTarget(target);

    return manifest.versionsByFileName[selectedFile] ??
        manifest.versionsByFileName[canonical] ??
        manifest.globalVersion;
  }

  Future<void> _setInstalledVersionForTarget(
    _ImportTarget target,
    String version,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_versionPrefKey(target), version.trim());
  }

  String _versionPrefKey(_ImportTarget target) {
    return 'onboarding.db.version.${_canonicalFileNameForTarget(target)}';
  }

  String _canonicalFileNameForTarget(_ImportTarget target) {
    switch (target) {
      case _ImportTarget.bibleEn:
        return 'bible_en_kjv.db';
      case _ImportTarget.bibleTa:
        return 'bible_ta_bsi.db';
      case _ImportTarget.sermonEn:
        return 'sermons_en.db';
      case _ImportTarget.sermonTa:
        return 'sermons_ta.db';
      case _ImportTarget.tractEn:
        return 'tracts_en.db';
      case _ImportTarget.tractTa:
        return 'tracts_ta.db';
      case _ImportTarget.storyEn:
        return 'stories_en.db';
      case _ImportTarget.storyTa:
        return 'stories_ta.db';
      case _ImportTarget.codEnglish:
        return 'cod_english.db';
      case _ImportTarget.codTamil:
        return 'cod_tamil.db';
      case _ImportTarget.churchAgesEn:
        return 'church_ages_en.db';
      case _ImportTarget.churchAgesTa:
        return 'church_ages_ta.db';
      case _ImportTarget.quotesEn:
        return 'quotes_en.db';
      case _ImportTarget.prayerQuotesEn:
        return 'prayer_quotes_en.db';
      case _ImportTarget.songsEn:
        return 'hymn.db';
      case _ImportTarget.songsTa:
        return 'songs.db';
      case _ImportTarget.specialBooksCatalogEn:
        return 'special_books_catalog_en.db';
      case _ImportTarget.specialBooksCatalogTa:
        return 'special_books_catalog_ta.db';
    }
  }

  int _compareSemver(String a, String b) {
    final aParts = _toVersionParts(a);
    final bParts = _toVersionParts(b);
    final maxLen = aParts.length > bParts.length
        ? aParts.length
        : bParts.length;

    for (var i = 0; i < maxLen; i++) {
      final ai = i < aParts.length ? aParts[i] : 0;
      final bi = i < bParts.length ? bParts[i] : 0;
      if (ai > bi) return 1;
      if (ai < bi) return -1;
    }
    return 0;
  }

  List<int> _toVersionParts(String input) {
    final clean = input.split('+').first;
    return clean
        .split('.')
        .map(
          (part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
        )
        .toList();
  }

  // ── Validation ───────────────────────────────────────────────────────────────

  _ValidationResult _validateBible(String dbPath) {
    try {
      final db = sql.sqlite3.open(dbPath, mode: sql.OpenMode.readOnly);
      try {
        final tables = db
            .select("SELECT name FROM sqlite_master WHERE type='table'")
            .map((r) => (r.columnAt(0) as String).toLowerCase())
            .toSet();

        if (tables.contains('bible_verses')) {
          final count = db.select('SELECT COUNT(*) FROM bible_verses');
          final n = count.isEmpty ? 0 : (count.first.columnAt(0) as int? ?? 0);
          if (n == 0) {
            return const _ValidationResult(false, 'Bible database is empty.');
          }
          return const _ValidationResult(true, 'OK', _BibleFormat.newFormat);
        }
        if (tables.contains('words')) {
          return const _ValidationResult(true, 'OK', _BibleFormat.oldFormat);
        }
        return const _ValidationResult(
          false,
          'Not a valid Bible database (missing bible_verses / words).',
        );
      } finally {
        db.close();
      }
    } catch (e) {
      return _ValidationResult(false, 'Validation error: $e');
    }
  }

  bool _validateSermon(String dbPath) {
    try {
      final db = sql.sqlite3.open(dbPath, mode: sql.OpenMode.readOnly);
      try {
        final tables = db
            .select("SELECT name FROM sqlite_master WHERE type='table'")
            .map((r) => (r.columnAt(0) as String).toLowerCase())
            .toSet();
        return tables.contains('sermons') &&
            tables.contains('sermon_paragraphs');
      } finally {
        db.close();
      }
    } catch (_) {
      return false;
    }
  }

  int _countSermons(String dbPath) {
    try {
      final db = sql.sqlite3.open(dbPath, mode: sql.OpenMode.readOnly);
      try {
        final rows = db.select('SELECT COUNT(*) AS c FROM sermons');
        if (rows.isEmpty) return 0;
        return (rows.first['c'] as int?) ?? 0;
      } finally {
        db.close();
      }
    } catch (_) {
      return 0;
    }
  }

  bool _validateCod(String dbPath) {
    try {
      final db = sql.sqlite3.open(dbPath, mode: sql.OpenMode.readOnly);
      try {
        final tables = db
            .select("SELECT name FROM sqlite_master WHERE type='table'")
            .map((r) => (r.columnAt(0) as String).toLowerCase())
            .toSet();
        return tables.contains('questions') && tables.contains('answers');
      } finally {
        db.close();
      }
    } catch (_) {
      return false;
    }
  }

  bool _validateTracts(String dbPath) {
    try {
      final db = sql.sqlite3.open(dbPath, mode: sql.OpenMode.readOnly);
      try {
        final tables = db
            .select("SELECT name FROM sqlite_master WHERE type='table'")
            .map((r) => (r.columnAt(0) as String).toLowerCase())
            .toSet();
        return tables.contains('tracts');
      } finally {
        db.close();
      }
    } catch (_) {
      return false;
    }
  }

  bool _validateStories(String dbPath) {
    try {
      final db = sql.sqlite3.open(dbPath, mode: sql.OpenMode.readOnly);
      try {
        final tables = db
            .select("SELECT name FROM sqlite_master WHERE type='table'")
            .map((r) => (r.columnAt(0) as String).toLowerCase())
            .toSet();
        return tables.contains('wmb_stories') &&
            tables.contains('kids_corner') &&
            tables.contains('timeline') &&
            tables.contains('witnesses');
      } finally {
        db.close();
      }
    } catch (_) {
      return false;
    }
  }

  Future<void> _optimizeCodDb(String dbPath) async {
    try {
      final db = sql.sqlite3.open(dbPath);
      try {
        db.execute('PRAGMA optimize');
      } finally {
        db.close();
      }
    } catch (_) {
      // Best-effort only.
    }
  }

  void _ensureCodFts(String dbPath) {
    try {
      final db = sql.sqlite3.open(dbPath);
      try {
        // Create FTS5 tables if they don't exist (older DBs / schema variants).
        db.execute('''
          CREATE VIRTUAL TABLE IF NOT EXISTS questions_fts
          USING fts5(
            id UNINDEXED,
            title,
            title_short,
            scriptures
          )
        ''');
        db.execute('''
          CREATE VIRTUAL TABLE IF NOT EXISTS answers_fts
          USING fts5(
            question_id UNINDEXED,
            para_label,
            plain_text
          )
        ''');

        // Check if populated; if not, rebuild from `questions`/`answers`.
        final questionsCount = _safeFtsCount(db, 'questions_fts');
        final answersCount = _safeFtsCount(db, 'answers_fts');

        if (questionsCount == 0 || answersCount == 0) {
          debugPrint('COD FTS empty — rebuilding $dbPath...');
          try {
            db.execute('DELETE FROM questions_fts;');
            db.execute('DELETE FROM answers_fts;');

            // Best-effort rebuild:
            // - If columns like `title_short` / `scriptures` are missing,
            //   the rebuild query may fail. In that case we keep the DB as-is.
            db.execute('''
              INSERT INTO questions_fts(id, title, title_short, scriptures)
              SELECT
                q.id,
                q.title,
                COALESCE(q.title_short, ''),
                COALESCE(CAST(q.scriptures AS TEXT), '')
              FROM questions q
            ''');

            db.execute('''
              INSERT INTO answers_fts(question_id, para_label, plain_text)
              SELECT
                a.question_id,
                COALESCE(a.para_label, ''),
                a.plain_text
              FROM answers a
            ''');
          } catch (e) {
            debugPrint('COD FTS rebuild warning: $e');
          }
        }

        // Warm/optimize FTS for faster queries.
        db.execute(
          "INSERT INTO questions_fts(questions_fts) VALUES('optimize')",
        );
        db.execute("INSERT INTO answers_fts(answers_fts) VALUES('optimize')");
        db.execute('PRAGMA optimize');
      } finally {
        db.close();
      }
    } catch (e) {
      debugPrint('_ensureCodFts warning: $e');
    }
  }

  int _safeFtsCount(sql.Database db, String tableName) {
    try {
      final res = db.select('SELECT COUNT(*) FROM $tableName');
      if (res.isEmpty) return 0;
      return res.first.columnAt(0) as int? ?? 0;
    } catch (_) {
      return 0;
    }
  }

  // ── FTS maintenance ──────────────────────────────────────────────────────────

  /// Ensures the correct FTS5 virtual table exists and is populated.
  /// If the table already has rows, only verifies; otherwise rebuilds.
  void _ensureFts(String dbPath, DbType type) {
    try {
      final db = sql.sqlite3.open(dbPath);
      try {
        if (type == DbType.bible) {
          _ensureBibleFts(db);
        } else if (type == DbType.churchAges) {
          _ensureChurchAgesFtsFromDb(db);
        } else {
          _ensureSermonFts(db);
        }
      } finally {
        db.close();
      }
    } catch (e) {
      debugPrint('_ensureFts($type) warning: $e');
    }
  }

  void _ensureBibleFts(sql.Database db) {
    // Create FTS5 table if absent
    db.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS bible_fts
      USING fts5(
        language, book, text,
        content=bible_verses,
        content_rowid=id,
        tokenize='unicode61'
      )
    ''');

    // Check if populated
    final check = db.select('SELECT COUNT(*) FROM bible_fts');
    final count = check.isEmpty ? 0 : (check.first.columnAt(0) as int? ?? 0);
    final baseCheck = db.select('SELECT COUNT(*) FROM bible_verses');
    final baseCount = baseCheck.isEmpty
        ? 0
        : (baseCheck.first.columnAt(0) as int? ?? 0);
    if (count != baseCount) {
      debugPrint('bible_fts out of sync ($count/$baseCount) — rebuilding...');
      try {
        db.execute("INSERT INTO bible_fts(bible_fts) VALUES('rebuild')");
      } catch (_) {
        db.execute('DELETE FROM bible_fts;');
        db.execute(
          'INSERT INTO bible_fts(rowid, language, book, text) '
          'SELECT id, language, book, text FROM bible_verses',
        );
      }
    }
  }

  void _ensureSermonFts(sql.Database db) {
    db.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS sermon_fts
      USING fts5(
        text,
        content=sermon_paragraphs,
        content_rowid=id,
        tokenize='unicode61'
      )
    ''');

    final check = db.select('SELECT COUNT(*) FROM sermon_fts');
    final count = check.isEmpty ? 0 : (check.first.columnAt(0) as int? ?? 0);
    final paraCheck = db.select('SELECT COUNT(*) FROM sermon_paragraphs');
    final paraCount = paraCheck.isEmpty
        ? 0
        : (paraCheck.first.columnAt(0) as int? ?? 0);
    if (count != paraCount) {
      debugPrint('sermon_fts out of sync ($count/$paraCount) — rebuilding...');
      try {
        db.execute("INSERT INTO sermon_fts(sermon_fts) VALUES('rebuild')");
      } catch (_) {
        db.execute('DELETE FROM sermon_fts;');
        db.execute(
          'INSERT INTO sermon_fts(rowid, text) '
          'SELECT id, text FROM sermon_paragraphs',
        );
      }
    }
  }

  void _ensureChurchAgesFts(String dbPath) {
    try {
      final db = sql.sqlite3.open(dbPath);
      try {
        _ensureChurchAgesFtsFromDb(db);
      } finally {
        db.close();
      }
    } catch (e) {
      debugPrint('_ensureChurchAgesFts warning: $e');
    }
  }

  void _ensureChurchAgesFtsFromDb(sql.Database db) {
    // Create FTS5 table if absent
    db.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS fts_content
      USING fts5(
        topic_id UNINDEXED,
        title,
        content_text,
        content=content,
        content_rowid=id,
        tokenize='unicode61'
      )
    ''');

    // Check if populated
    final check = db.select('SELECT COUNT(*) FROM fts_content');
    final count = check.isEmpty ? 0 : (check.first.columnAt(0) as int? ?? 0);
    final contentCheck = db.select('SELECT COUNT(*) FROM content');
    final contentCount = contentCheck.isEmpty
        ? 0
        : (contentCheck.first.columnAt(0) as int? ?? 0);

    if (count != contentCount) {
      debugPrint('fts_content out of sync ($count/$contentCount) — rebuilding...');
      try {
        db.execute("INSERT INTO fts_content(fts_content) VALUES('rebuild')");
      } catch (_) {
        db.execute('DELETE FROM fts_content;');
        db.execute(
          'INSERT INTO fts_content(rowid, topic_id, title, content_text) '
          'SELECT c.id, c.topic_id, t.title, c.content_text '
          'FROM content c '
          'JOIN topics t ON c.topic_id = t.id',
        );
      }
    }
  }

  /// Run PRAGMA optimize on both FTS tables (lightweight, mirrors Android's FtsOptimizer).
  void warmUpFts(String dbPath, DbType type) {
    try {
      final db = sql.sqlite3.open(dbPath);
      try {
        db.execute('PRAGMA optimize');
        String tableName = 'sermon_fts';
        if (type == DbType.bible) tableName = 'bible_fts';
        if (type == DbType.churchAges) tableName = 'fts_content';
        
        db.execute("INSERT INTO $tableName($tableName) VALUES('optimize')");
      } finally {
        db.close();
      }
    } catch (e) {
      debugPrint('warmUpFts warning: $e');
    }
  }

  bool _validateQuotes(String dbPath) {
    try {
      final db = sql.sqlite3.open(dbPath, mode: sql.OpenMode.readOnly);
      try {
        final tables = db
            .select("SELECT name FROM sqlite_master WHERE type='table'")
            .map((r) => (r.columnAt(0) as String).toLowerCase())
            .toSet();
        return tables.contains('quotes');
      } finally {
        db.close();
      }
    } catch (_) {
      return false;
    }
  }

  bool _validatePrayerQuotes(String dbPath) {
    try {
      final db = sql.sqlite3.open(dbPath, mode: sql.OpenMode.readOnly);
      try {
        final tables = db
            .select("SELECT name FROM sqlite_master WHERE type='table'")
            .map((r) => (r.columnAt(0) as String).toLowerCase())
            .toSet();
        return tables.contains('prayer_quotes');
      } finally {
        db.close();
      }
    } catch (_) {
      return false;
    }
  }

  void _ensureQuotesFts(String dbPath) {
    try {
      final db = sql.sqlite3.open(dbPath);
      try {
        db.execute('''
          CREATE VIRTUAL TABLE IF NOT EXISTS quotes_fts
          USING fts5(
            quote_plain,
            reference_plain,
            source_group,
            content=quotes,
            content_rowid=id,
            tokenize='unicode61'
          )
        ''');

        final check = db.select('SELECT COUNT(*) FROM quotes_fts');
        final count = check.isEmpty ? 0 : (check.first.columnAt(0) as int? ?? 0);
        final baseCheck = db.select('SELECT COUNT(*) FROM quotes');
        final baseCount = baseCheck.isEmpty ? 0 : (baseCheck.first.columnAt(0) as int? ?? 0);

        if (count != baseCount) {
          debugPrint('quotes_fts out of sync — rebuilding...');
          try {
            db.execute("INSERT INTO quotes_fts(quotes_fts) VALUES('rebuild')");
          } catch (_) {
            db.execute('DELETE FROM quotes_fts;');
            db.execute('''
              INSERT INTO quotes_fts(rowid, quote_plain, reference_plain, source_group)
              SELECT id, quote_plain, reference_plain, source_group FROM quotes
            ''');
          }
        }
      } finally {
        db.close();
      }
    } catch (e) {
      debugPrint('_ensureQuotesFts warning: $e');
    }
  }

  void _ensurePrayerQuotesFts(String dbPath) {
    try {
      final db = sql.sqlite3.open(dbPath);
      try {
        db.execute('''
          CREATE VIRTUAL TABLE IF NOT EXISTS prayer_quotes_fts
          USING fts5(
            quote_plain,
            reference_plain,
            author_name_raw,
            source_group,
            content=prayer_quotes,
            content_rowid=id,
            tokenize='unicode61'
          )
        ''');

        final check = db.select('SELECT COUNT(*) FROM prayer_quotes_fts');
        final count = check.isEmpty ? 0 : (check.first.columnAt(0) as int? ?? 0);
        final baseCheck = db.select('SELECT COUNT(*) FROM prayer_quotes');
        final baseCount = baseCheck.isEmpty ? 0 : (baseCheck.first.columnAt(0) as int? ?? 0);

        if (count != baseCount) {
          debugPrint('prayer_quotes_fts out of sync — rebuilding...');
          try {
            db.execute("INSERT INTO prayer_quotes_fts(prayer_quotes_fts) VALUES('rebuild')");
          } catch (_) {
            db.execute('DELETE FROM prayer_quotes_fts;');
            db.execute('''
              INSERT INTO prayer_quotes_fts(rowid, quote_plain, reference_plain, author_name_raw, source_group)
              SELECT id, quote_plain, reference_plain, author_name_raw, source_group FROM prayer_quotes
            ''');
          }
        }
      } finally {
        db.close();
      }
    } catch (e) {
      debugPrint('_ensurePrayerQuotesFts warning: $e');
    }
  }

  bool _validateEnglishSongs(String dbPath) {
    try {
      final db = sql.sqlite3.open(dbPath, mode: sql.OpenMode.readOnly);
      try {
        final tables = db
            .select("SELECT name FROM sqlite_master WHERE type='table'")
            .map((r) => (r.columnAt(0) as String).toLowerCase())
            .toSet();
        return tables.contains('hymns');
      } finally {
        db.close();
      }
    } catch (_) {
      return false;
    }
  }

  bool _validateTamilSongs(String dbPath) {
    try {
      final db = sql.sqlite3.open(dbPath, mode: sql.OpenMode.readOnly);
      try {
        final tables = db
            .select("SELECT name FROM sqlite_master WHERE type='table'")
            .map((r) => (r.columnAt(0) as String).toLowerCase())
            .toSet();
        return tables.contains('songs');
      } finally {
        db.close();
      }
    } catch (_) {
      return false;
    }
  }
}
