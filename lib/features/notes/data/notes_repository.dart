import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../../core/database/database_manager.dart';
import '../models/note_model.dart';

class NotesRepository {
  static Database? _db;
  static bool _ftsReady = false;

  Future<void> _createFtsTableIfPossible(Database db) async {
    try {
      await db.execute('''
        CREATE VIRTUAL TABLE notes_fts USING fts5(
          title,
          body
        )
      ''');
      _ftsReady = true;
      return;
    } catch (_) {
      // Try legacy fts4 module next.
    }

    try {
      await db.execute('''
        CREATE VIRTUAL TABLE notes_fts USING fts4(
          title,
          body
        )
      ''');
      _ftsReady = true;
      return;
    } catch (_) {
      _ftsReady = false;
    }
  }

  Future<bool> _hasFtsTable(Database db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'notes_fts' LIMIT 1",
    );
    return rows.isNotEmpty;
  }

  Future<void> _rebuildFtsIndex(Database db) async {
    if (!_ftsReady) return;
    final rows = await db.query('notes', columns: ['id', 'title', 'body']);
    await db.delete('notes_fts');
    for (final row in rows) {
      final id = (row['id'] as num?)?.toInt();
      if (id == null) continue;
      await db.insert('notes_fts', {
        'rowid': id,
        'title': (row['title'] as String?) ?? '',
        'body': (row['body'] as String?) ?? '',
      });
    }
  }

  Future<void> _syncFtsRow(
    Database db,
    int id,
    String title,
    String body,
  ) async {
    if (!_ftsReady) return;
    await db.delete('notes_fts', where: 'rowid = ?', whereArgs: [id]);
    await db.insert('notes_fts', {'rowid': id, 'title': title, 'body': body});
  }

  Future<Database> get _database async {
    if (_db != null && _db!.isOpen) return _db!;

    final dbDir = await DatabaseManager().getDatabaseDirectoryPath();
    final path = p.join(dbDir.path, 'user_notes.db');

    _db = await openDatabase(
      path,
      version: 2,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE notes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL DEFAULT '',
            body TEXT NOT NULL DEFAULT '',
            body_json TEXT,
            category TEXT NOT NULL DEFAULT '',
            tags TEXT NOT NULL DEFAULT '',
            source_ref_json TEXT,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await _createFtsTableIfPossible(db);

        await db.execute(
          'CREATE INDEX idx_notes_updated_at ON notes(updated_at DESC)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute("ALTER TABLE notes ADD COLUMN body_json TEXT");
          await db.execute(
            "ALTER TABLE notes ADD COLUMN category TEXT NOT NULL DEFAULT ''",
          );

          final rows = await db.query(
            'notes',
            columns: ['id', 'source_ref_json'],
          );
          for (final row in rows) {
            final id = (row['id'] as num?)?.toInt();
            final raw = row['source_ref_json'] as String?;
            if (id == null || raw == null || raw.trim().isEmpty) {
              continue;
            }

            try {
              final decoded = jsonDecode(raw);
              if (decoded is Map) {
                final migrated = jsonEncode([decoded]);
                await db.update(
                  'notes',
                  {'source_ref_json': migrated},
                  where: 'id = ?',
                  whereArgs: [id],
                );
              }
            } catch (_) {
              // Keep legacy or malformed values as-is to avoid destructive migration.
            }
          }
        }
      },
      onOpen: (db) async {
        _ftsReady = await _hasFtsTable(db);
        if (!_ftsReady) {
          await _createFtsTableIfPossible(db);
          _ftsReady = await _hasFtsTable(db);
          if (_ftsReady) {
            await _rebuildFtsIndex(db);
          }
        }
      },
    );

    return _db!;
  }

  String _buildFtsQuery(String query) {
    final tokens = query
        .trim()
        .split(RegExp(r'\s+'))
        .map((part) => part.replaceAll('"', '').trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (tokens.isEmpty) return '';
    return tokens.map((token) => '$token*').join(' ');
  }

  Future<List<NoteListItem>> listNotes({
    String? query,
    String? tag,
    String? category,
    int limit = 200,
  }) async {
    final db = await _database;
    final queryTrimmed = query?.trim() ?? '';

    if (queryTrimmed.isEmpty) {
      String? where;
      final whereArgs = <Object?>[];
      if (tag != null && tag.trim().isNotEmpty) {
        where = 'tags LIKE ?';
        whereArgs.add('%${tag.trim()}%');
      }
      if (category != null && category.trim().isNotEmpty) {
        where = where == null ? 'category = ?' : '$where AND category = ?';
        whereArgs.add(category.trim());
      }

      final rows = await db.query(
        'notes',
        where: where,
        whereArgs: whereArgs,
        orderBy: 'updated_at DESC',
        limit: limit,
      );

      return rows
          .map((row) {
            final note = NoteModel.fromDbRow(row);
            final body = note.body.trim();
            return NoteListItem(
              note: note,
              snippet: body.length <= 180
                  ? body
                  : '${body.substring(0, 180)}...',
            );
          })
          .toList(growable: false);
    }

    final ftsQuery = _buildFtsQuery(queryTrimmed);
    if (ftsQuery.isEmpty) return const <NoteListItem>[];

    if (!_ftsReady) {
      String where = '(title LIKE ? OR body LIKE ?)';
      final whereArgs = <Object?>['%$queryTrimmed%', '%$queryTrimmed%'];
      if (tag != null && tag.trim().isNotEmpty) {
        where = '$where AND tags LIKE ?';
        whereArgs.add('%${tag.trim()}%');
      }
      if (category != null && category.trim().isNotEmpty) {
        where = '$where AND category = ?';
        whereArgs.add(category.trim());
      }

      final rows = await db.query(
        'notes',
        where: where,
        whereArgs: whereArgs,
        orderBy: 'updated_at DESC',
        limit: limit,
      );

      return rows
          .map((row) {
            final note = NoteModel.fromDbRow(row);
            final body = note.body.trim();
            return NoteListItem(
              note: note,
              snippet: body.length <= 180
                  ? body
                  : '${body.substring(0, 180)}...',
            );
          })
          .toList(growable: false);
    }

    final args = <Object?>[ftsQuery];
    final tagFilter = (tag != null && tag.trim().isNotEmpty)
        ? ' AND n.tags LIKE ?'
        : '';
    final categoryFilter = (category != null && category.trim().isNotEmpty)
        ? ' AND n.category = ?'
        : '';
    if (tagFilter.isNotEmpty) {
      args.add('%${tag!.trim()}%');
    }
    if (categoryFilter.isNotEmpty) {
      args.add(category!.trim());
    }

    final rows = await db.rawQuery('''
      SELECT n.*, n.body AS snippet_text
      FROM notes_fts
      JOIN notes n ON n.id = notes_fts.rowid
      WHERE notes_fts MATCH ?$tagFilter$categoryFilter
      ORDER BY n.updated_at DESC
      LIMIT $limit
    ''', args);

    return rows
        .map((row) {
          final note = NoteModel.fromDbRow(row);
          return NoteListItem(
            note: note,
            snippet: ((row['snippet_text'] as String?) ?? note.body).trim(),
          );
        })
        .toList(growable: false);
  }

  Future<NoteModel?> getById(int id) async {
    final db = await _database;
    final rows = await db.query(
      'notes',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return NoteModel.fromDbRow(rows.first);
  }

  Future<int> upsert(NoteModel note) async {
    final db = await _database;

    if (note.id == null) {
      final id = await db.insert(
        'notes',
        note.toDbMap()..remove('id'),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      await _syncFtsRow(db, id, note.title, note.body);
      return id;
    }

    await db.update(
      'notes',
      note.toDbMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [note.id],
    );

    await _syncFtsRow(db, note.id!, note.title, note.body);

    return note.id!;
  }

  Future<void> deleteById(int id) async {
    final db = await _database;
    await db.delete('notes', where: 'id = ?', whereArgs: [id]);
    if (_ftsReady) {
      await db.delete('notes_fts', where: 'rowid = ?', whereArgs: [id]);
    }
  }

  Future<List<String>> listKnownTags() async {
    final db = await _database;
    final rows = await db.query('notes', columns: ['tags']);
    final tags = <String>{};

    for (final row in rows) {
      final raw = (row['tags'] as String?) ?? '';
      for (final tag
          in raw
              .split(',')
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)) {
        tags.add(tag);
      }
    }

    final sorted = tags.toList(growable: false)..sort();
    return sorted;
  }

  Future<List<String>> listKnownCategories() async {
    final db = await _database;
    final rows = await db.query('notes', columns: ['category']);
    final categories = <String>{};

    for (final row in rows) {
      final value = ((row['category'] as String?) ?? '').trim();
      if (value.isNotEmpty) {
        categories.add(value);
      }
    }

    final sorted = categories.toList(growable: false)..sort();
    return sorted;
  }

  Future<List<NoteModel>> getNotesByLinkKey(String linkKey) async {
    final db = await _database;
    final rows = await db.query(
      'notes',
      where: 'source_ref_json LIKE ?',
      whereArgs: ['%$linkKey%'],
      orderBy: 'updated_at DESC',
    );
    return rows.map((r) => NoteModel.fromDbRow(r)).toList();
  }

  Future<NoteModel?> findRecentNoteBySourceId(String type, String referenceId) async {
    final db = await _database;
    final linkKey = '${type}_$referenceId';
    final rows = await db.query(
      'notes',
      where: 'source_ref_json LIKE ?',
      whereArgs: ['%$linkKey%'],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return NoteModel.fromDbRow(rows.first);
  }
}
