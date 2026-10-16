import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';
import '../crdt/hlc.dart';
import '../crdt/report.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  DatabaseHelper._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), 'meshlink.db');
    return openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        // Every field of every report, one row per field.
        // This is what makes CRDT merging possible — we track
        // each field's own timestamp, not just the whole report's.
        await db.execute('''
          CREATE TABLE report_fields (
            report_id TEXT NOT NULL,
            field_name TEXT NOT NULL,
            value TEXT NOT NULL,
            hlc_physical INTEGER NOT NULL,
            hlc_logical INTEGER NOT NULL,
            updated_by TEXT NOT NULL,
            PRIMARY KEY (report_id, field_name)
          )
        ''');

        // Append-only thread messages — never conflict, just accumulate.
        await db.execute('''
          CREATE TABLE thread_messages (
            id TEXT PRIMARY KEY,
            report_id TEXT NOT NULL,
            from_team TEXT NOT NULL,
            type TEXT NOT NULL,
            content TEXT NOT NULL,
            hlc_physical INTEGER NOT NULL,
            hlc_logical INTEGER NOT NULL
          )
        ''');

        await _createAcksTable(db);
      },
      // Phones that already have the version 1 database get the new table
      // without losing any of their reports.
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createAcksTable(db);
        }
      },
    );
  }

  /// Which of OUR messages another phone has confirmed receiving.
  /// This is local bookkeeping only; it is never synced to other phones.
  Future<void> _createAcksTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS message_acks (
        message_id TEXT PRIMARY KEY
      )
    ''');
  }

  // Save/update one field of one report.
  Future<void> upsertField(String reportId, String fieldName, FieldValue fv, String updatedBy) async {
    final db = await database;
    await db.insert(
      'report_fields',
      {
        'report_id': reportId,
        'field_name': fieldName,
        'value': jsonEncode(fv.value),
        'hlc_physical': fv.timestamp.physicalTime,
        'hlc_logical': fv.timestamp.logicalCounter,
        'updated_by': updatedBy,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Rebuild a full Report object from stored fields.
  Future<Report> getReport(String reportId) async {
    final db = await database;
    final rows = await db.query(
      'report_fields',
      where: 'report_id = ?',
      whereArgs: [reportId],
    );
    final fields = <String, FieldValue>{};
    for (final row in rows) {
      fields[row['field_name'] as String] = FieldValue(
        jsonDecode(row['value'] as String),
        HLC(row['hlc_physical'] as int, row['hlc_logical'] as int),
      );
    }
    return Report(fields);
  }

  // List every report ID that exists on this device.
  Future<List<String>> getAllReportIds() async {
    final db = await database;
    final rows = await db.rawQuery('SELECT DISTINCT report_id FROM report_fields');
    return rows.map((r) => r['report_id'] as String).toList();
  }

  // Add a message/photo/location share to a report's thread.
  Future<void> insertMessage(String reportId, String id, String fromTeam, String type, String content, HLC ts) async {
    final db = await database;
    await db.insert(
      'thread_messages',
      {
        'id': id,
        'report_id': reportId,
        'from_team': fromTeam,
        'type': type,
        'content': content,
        'hlc_physical': ts.physicalTime,
        'hlc_logical': ts.logicalCounter,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore, // same id = already have it
    );
  }

  // Get all thread messages for a report, in order.
  Future<List<Map<String, dynamic>>> getMessages(String reportId) async {
    final db = await database;
    return db.query(
      'thread_messages',
      where: 'report_id = ?',
      whereArgs: [reportId],
      orderBy: 'hlc_physical ASC, hlc_logical ASC',
    );
  }

  // ---- Delivery confirmations ---------------------------------------------

  /// Record that another phone confirmed receiving these messages.
  /// Returns true if at least one of them was new information.
  Future<bool> markDelivered(List<String> messageIds) async {
    if (messageIds.isEmpty) return false;
    final db = await database;

    final placeholders = List.filled(messageIds.length, '?').join(',');
    final existing = await db.rawQuery(
      'SELECT message_id FROM message_acks WHERE message_id IN ($placeholders)',
      messageIds,
    );
    final known = {for (final r in existing) r['message_id'] as String};

    var changed = false;
    for (final id in messageIds) {
      if (known.contains(id)) continue;
      await db.insert(
        'message_acks',
        {'message_id': id},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      changed = true;
    }
    return changed;
  }

  /// Ids of messages that another phone has confirmed receiving.
  Future<Set<String>> getDeliveredIds() async {
    final db = await database;
    final rows = await db.query('message_acks', columns: ['message_id']);
    return {for (final r in rows) r['message_id'] as String};
  }
}
