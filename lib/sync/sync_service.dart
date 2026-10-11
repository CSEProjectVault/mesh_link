import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
 
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
 
import '../crdt/hlc.dart';
import '../crdt/report.dart';
import '../db/database_helper.dart';
 
/// Turns local data into payloads for other devices and merges payloads
/// received from them. It only deals with bytes, so it does not care whether
/// they travel over Nearby Connections, sockets or anything else.
///
/// Sync model: state-based. Every report is sent as its current fields
/// (each with its own HLC timestamp) plus its thread messages. Merging is
/// idempotent, commutative and associative, so syncing the same pair twice,
/// or in any order, converges to the same state.
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();
 
  /// Incremented whenever incoming data changed the local database.
  /// Screens listen to this and reload.
  final ValueNotifier<int> dataVersion = ValueNotifier<int>(0);
 
  // ---- Hybrid logical clock for this device -------------------------------
 
  HLC? _lastClock;
 
  /// Use this for every new local edit. It is always ordered after anything
  /// this device has already seen from others, even if phone clocks differ.
  HLC nextClock() {
    _lastClock = HLC.tick(_lastClock);
    return _lastClock!;
  }
 
  void _observe(HLC seen) {
    if (_lastClock == null || seen.isAfter(_lastClock!)) {
      _lastClock = seen;
    }
  }
 
  // ---- Building payloads --------------------------------------------------
 
  // Nearby Connections limits a bytes payload to about 32 KB, so messages
  // are sent in small batches instead of one big blob.
  static const int _messageBatchSize = 20;
 
  /// Every report on this device, ready to send to a newly connected peer.
  Future<List<Uint8List>> buildSnapshotPayloads() async {
    final ids = await DatabaseHelper.instance.getAllReportIds();
    final out = <Uint8List>[];
    for (final id in ids) {
      out.addAll(await buildReportPayloads(id));
    }
    return out;
  }
 
  /// One report: a payload with its fields, then payloads with its messages.
  Future<List<Uint8List>> buildReportPayloads(String reportId) async {
    final db = await DatabaseHelper.instance.database;
 
    final fieldRows = await db.query(
      'report_fields',
      where: 'report_id = ?',
      whereArgs: [reportId],
    );
    if (fieldRows.isEmpty) return [];
 
    final payloads = <Uint8List>[
      _encode({
        'v': 1,
        'type': 'report',
        'id': reportId,
        'fields': {
          for (final r in fieldRows)
            r['field_name'] as String: {
              'v': r['value'], // already a JSON-encoded string
              'p': r['hlc_physical'],
              'l': r['hlc_logical'],
              'by': r['updated_by'],
            },
        },
      }),
    ];
 
    final msgRows = await db.query(
      'thread_messages',
      where: 'report_id = ?',
      whereArgs: [reportId],
      orderBy: 'hlc_physical ASC, hlc_logical ASC',
    );
    for (var i = 0; i < msgRows.length; i += _messageBatchSize) {
      final batch =
          msgRows.sublist(i, min(i + _messageBatchSize, msgRows.length));
      payloads.add(_encode({
        'v': 1,
        'type': 'messages',
        'id': reportId,
        'messages': [
          for (final m in batch)
            {
              'id': m['id'],
              'from': m['from_team'],
              'type': m['type'],
              'content': m['content'],
              'p': m['hlc_physical'],
              'l': m['hlc_logical'],
            },
        ],
      }));
    }
    return payloads;
  }
 
  Uint8List _encode(Map<String, dynamic> map) =>
      Uint8List.fromList(utf8.encode(jsonEncode(map)));
 
  // ---- Applying incoming payloads ----------------------------------------
 
  /// Merge one payload received from another device.
  /// Returns true if it changed anything locally.
  Future<bool> applyIncoming(Uint8List bytes) async {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Sync: ignoring unreadable payload: $e');
      return false;
    }
    if (data['v'] != 1) return false;
 
    final reportId = data['id'] as String;
    var changed = false;
    try {
      switch (data['type']) {
        case 'report':
          changed = await _mergeFields(
            reportId,
            Map<String, dynamic>.from(data['fields'] as Map),
          );
        case 'messages':
          changed = await _mergeMessages(
            reportId,
            List<dynamic>.from(data['messages'] as List),
          );
      }
    } catch (e) {
      debugPrint('Sync: failed to merge payload: $e');
      return false;
    }
 
    if (changed) dataVersion.value++;
    return changed;
  }
 
  Future<bool> _mergeFields(
    String reportId,
    Map<String, dynamic> incoming,
  ) async {
    final local = await DatabaseHelper.instance.getReport(reportId);
    final before = {
      for (final e in local.fields.entries) e.key: _signature(e.value),
    };
 
    final remoteFields = <String, FieldValue>{};
    final remoteAuthors = <String, String>{};
 
    incoming.forEach((name, raw) {
      final m = Map<String, dynamic>.from(raw as Map);
      final remote = FieldValue(
        jsonDecode(m['v'] as String),
        HLC(m['p'] as int, m['l'] as int),
      );
      remoteAuthors[name] = (m['by'] as String?) ?? 'unknown';
      _observe(remote.timestamp);
 
      final mine = local.fields[name];
      final sameStamp = mine != null &&
          mine.timestamp.physicalTime == remote.timestamp.physicalTime &&
          mine.timestamp.logicalCounter == remote.timestamp.logicalCounter;
 
      if (sameStamp && jsonEncode(mine!.value) != jsonEncode(remote.value)) {
        // Identical clocks but different values. Break the tie the same way
        // on every device (larger encoded value wins) so they cannot diverge.
        if (jsonEncode(remote.value).compareTo(jsonEncode(mine.value)) > 0) {
          local.fields[name] = remote;
        }
      } else {
        remoteFields[name] = remote;
      }
    });
 
    // The actual CRDT merge: per-field last-writer-wins by HLC,
    // with the special rules defined in Report.mergeWith.
    local.mergeWith(Report(remoteFields));
 
    var changed = false;
    for (final e in local.fields.entries) {
      if (before[e.key] != _signature(e.value)) {
        await DatabaseHelper.instance.upsertField(
          reportId,
          e.key,
          e.value,
          remoteAuthors[e.key] ?? 'sync',
        );
        changed = true;
      }
    }
    return changed;
  }
 
  String _signature(FieldValue f) =>
      '${f.timestamp.physicalTime}:${f.timestamp.logicalCounter}:'
      '${jsonEncode(f.value)}';
 
  Future<bool> _mergeMessages(
    String reportId,
    List<dynamic> messages,
  ) async {
    final db = await DatabaseHelper.instance.database;
    var changed = false;
    for (final raw in messages) {
      final m = Map<String, dynamic>.from(raw as Map);
      // Messages are append-only and identified by a unique id, so merging
      // is just "add the ones I do not have yet".
      final exists = await db.query(
        'thread_messages',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [m['id']],
        limit: 1,
      );
      if (exists.isNotEmpty) continue;
 
      await db.insert(
        'thread_messages',
        {
          'id': m['id'],
          'report_id': reportId,
          'from_team': m['from'],
          'type': m['type'],
          'content': m['content'],
          'hlc_physical': m['p'],
          'hlc_logical': m['l'],
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      changed = true;
    }
    return changed;
  }
}
 