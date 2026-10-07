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
      version: 1,
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
      },
    );
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
}