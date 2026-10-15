import 'package:flutter/material.dart';

import '../config/device_identity.dart';
import '../crdt/report.dart';
import '../db/database_helper.dart';
import '../models/pin_models.dart';
import '../sync/sync_controller.dart';
import '../sync/sync_service.dart';
import 'auth_service.dart';

/// Things you can do to a whole report.
class ReportActions {
  ReportActions._();

  /// Who may delete a report: organization members can delete any report;
  /// everyone else only the reports they created.
  ///
  /// Demo-level, like the rest of the login: the check runs inside the app,
  /// and "creator" is matched by name, so two hikers who use the same name
  /// count as the same person.
  static bool canDelete(Pin pin) {
    final session = AuthService.instance.session.value;
    if (session == null) return false;
    if (session.mode == AuthMode.org) return true;
    return pin.authorName == session.displayName;
  }

  /// Checks permission, asks "are you sure?", then deletes.
  /// Returns true only if the report was deleted.
  static Future<bool> deleteWithConfirm(BuildContext context, Pin pin) async {
    if (!canDelete(pin)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Only the person who created this report, or an organization '
            'member, can delete it.',
          ),
        ),
      );
      return false;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this report?'),
        content: Text(
          '"${pin.title}" will be removed from this phone, and from other '
          'phones as they sync. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;

    await _markDeleted(pin.id);
    return true;
  }

  /// Marks the report as deleted and tells connected phones.
  ///
  /// The rows are kept on purpose (a "tombstone"). If they were erased, any
  /// phone that still has the report would send it back on the next sync and
  /// it would reappear. As a normal field with its own timestamp, "deleted"
  /// syncs like every other edit.
  static Future<void> _markDeleted(String reportId) async {
    await DatabaseHelper.instance.upsertField(
      reportId,
      'deleted',
      FieldValue(true, SyncService.instance.nextClock()),
      DeviceIdentity.current,
    );
    await SyncController.broadcastReport(reportId);
  }
}