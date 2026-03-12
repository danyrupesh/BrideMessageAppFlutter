import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../../core/database/database_manager.dart';
import '../models/reading_flow_models.dart';

class ReadingStateRepository {
  static Database? _db;

  Future<Database> get _database async {
    if (_db != null && _db!.isOpen) return _db!;
    final dbDir = await DatabaseManager().getDatabaseDirectoryPath();
    final path = p.join(dbDir.path, 'reading_state.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE active_sessions (
            flow_type TEXT PRIMARY KEY,
            tabs_json TEXT NOT NULL,
            active_tab_index INTEGER NOT NULL,
            schema_version INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE saved_flows (
            flow_id TEXT PRIMARY KEY,
            flow_type TEXT NOT NULL,
            name TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            schema_version INTEGER NOT NULL,
            source TEXT,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE recent_reads (
            entry_key TEXT PRIMARY KEY,
            flow_type TEXT NOT NULL,
            title TEXT NOT NULL,
            subtitle TEXT NOT NULL,
            snapshot_json TEXT NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_recent_reads_updated_at ON recent_reads(updated_at DESC)',
        );
        await db.execute(
          'CREATE INDEX idx_saved_flows_type_updated_at ON saved_flows(flow_type, updated_at DESC)',
        );
      },
    );
    return _db!;
  }

  Future<ReadingFlowPayloadV1?> loadActiveSession(FlowType flowType) async {
    final db = await _database;
    final rows = await db.query(
      'active_sessions',
      where: 'flow_type = ?',
      whereArgs: [flowType.dbValue],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    try {
      final row = rows.first;
      final tabsRaw = (row['tabs_json'] as String?) ?? '[]';
      final tabsDecoded = jsonDecode(tabsRaw);
      final tabs = tabsDecoded is List
          ? tabsDecoded
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList(growable: false)
          : <Map<String, dynamic>>[];
      return ReadingFlowPayloadV1(
        schemaVersion:
            (row['schema_version'] as num?)?.toInt() ??
            ReadingFlowPayloadV1.currentSchemaVersion,
        flowType: flowType,
        tabs: tabs,
        activeTabIndex: (row['active_tab_index'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveActiveSession(
    FlowType flowType,
    ReadingFlowPayloadV1 payload,
  ) async {
    final db = await _database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('active_sessions', {
      'flow_type': flowType.dbValue,
      'tabs_json': jsonEncode(payload.tabs),
      'active_tab_index': payload.activeTabIndex,
      'schema_version': payload.schemaVersion,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteActiveSession(FlowType flowType) async {
    final db = await _database;
    await db.delete(
      'active_sessions',
      where: 'flow_type = ?',
      whereArgs: [flowType.dbValue],
    );
  }

  Future<void> upsertRecentRead({
    required String entryKey,
    required FlowType flowType,
    required String title,
    required String subtitle,
    required ReadingFlowPayloadV1 snapshot,
  }) async {
    final db = await _database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('recent_reads', {
      'entry_key': entryKey,
      'flow_type': flowType.dbValue,
      'title': title,
      'subtitle': subtitle,
      'snapshot_json': jsonEncode(snapshot.toJson()),
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    await db.execute('''
      DELETE FROM recent_reads
      WHERE entry_key NOT IN (
        SELECT entry_key FROM recent_reads
        ORDER BY updated_at DESC
        LIMIT 10
      )
    ''');
  }

  Future<List<RecentReadItem>> listRecentReads({int limit = 10}) async {
    final db = await _database;
    final rows = await db.query(
      'recent_reads',
      orderBy: 'updated_at DESC',
      limit: limit,
    );
    final items = <RecentReadItem>[];
    for (final row in rows) {
      try {
        final snapshotRaw = (row['snapshot_json'] as String?) ?? '{}';
        final snapshotMap = jsonDecode(snapshotRaw);
        if (snapshotMap is! Map) continue;
        final snapshot = ReadingFlowPayloadV1.fromJson(
          Map<String, dynamic>.from(snapshotMap),
        );
        items.add(
          RecentReadItem(
            entryKey: (row['entry_key'] as String?) ?? '',
            flowType: FlowTypeX.fromDbValue(
              (row['flow_type'] as String?) ?? FlowType.bible.name,
            ),
            title: (row['title'] as String?) ?? '',
            subtitle: (row['subtitle'] as String?) ?? '',
            snapshot: snapshot,
            updatedAt: (row['updated_at'] as num?)?.toInt() ?? 0,
          ),
        );
      } catch (_) {}
    }
    return items;
  }

  Future<void> upsertSavedFlow({
    required String flowId,
    required FlowType flowType,
    required String name,
    required ReadingFlowPayloadV1 payload,
    String? source,
  }) async {
    final db = await _database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('saved_flows', {
      'flow_id': flowId,
      'flow_type': flowType.dbValue,
      'name': name,
      'payload_json': jsonEncode(payload.toJson()),
      'schema_version': payload.schemaVersion,
      'source': source,
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<ReadingFlowPayloadV1>> listSavedFlows(FlowType flowType) async {
    final db = await _database;
    final rows = await db.query(
      'saved_flows',
      where: 'flow_type = ?',
      whereArgs: [flowType.dbValue],
      orderBy: 'updated_at DESC',
    );
    final payloads = <ReadingFlowPayloadV1>[];
    for (final row in rows) {
      try {
        final payloadRaw = (row['payload_json'] as String?) ?? '{}';
        final payloadMap = jsonDecode(payloadRaw);
        if (payloadMap is! Map) continue;
        payloads.add(
          ReadingFlowPayloadV1.fromJson(Map<String, dynamic>.from(payloadMap)),
        );
      } catch (_) {}
    }
    return payloads;
  }

  Future<void> deleteSavedFlow(String flowId) async {
    final db = await _database;
    await db.delete('saved_flows', where: 'flow_id = ?', whereArgs: [flowId]);
  }

  Future<String?> exportFlowPayload(String flowId) async {
    final db = await _database;
    final rows = await db.query(
      'saved_flows',
      where: 'flow_id = ?',
      whereArgs: [flowId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['payload_json'] as String?;
  }

  Future<String?> importFlowPayload(
    ReadingFlowPayloadV1 payload, {
    String? name,
    String? source,
  }) async {
    final flowId = DateTime.now().microsecondsSinceEpoch.toString();
    await upsertSavedFlow(
      flowId: flowId,
      flowType: payload.flowType,
      name: name ?? 'Imported ${payload.flowType.name} flow',
      payload: payload,
      source: source ?? 'import',
    );
    return flowId;
  }
}
