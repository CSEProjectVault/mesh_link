import 'package:flutter/material.dart';
import '../config/device_identity.dart';
import '../crdt/report.dart';
import '../db/database_helper.dart';
import '../models/pin_models.dart';
import '../models/report_pin_adapter.dart';
import '../sync/sync_controller.dart';
import '../sync/sync_service.dart';
import 'report_map_screen.dart';
import '../services/report_actions.dart';

class ReportDetailScreen extends StatefulWidget {
  final String pinId;
 
  const ReportDetailScreen({super.key, required this.pinId});
 
  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}
 
class _ReportDetailScreenState extends State<ReportDetailScreen> {
  Pin? _pin;
  String _status = 'Open';
  List<ThreadMessage> _messages = [];
  final _composerController = TextEditingController();
  final _scrollController = ScrollController();
 
  @override
  void initState() {
    super.initState();
    _load();
    SyncService.instance.dataVersion.addListener(_onSyncData);
  }
 
  void _onSyncData() {
    if (mounted) _load();
  }
 
  @override
  void dispose() {
    SyncService.instance.dataVersion.removeListener(_onSyncData);
    _composerController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
 
  Future<void> _load() async {
    final report = await DatabaseHelper.instance.getReport(widget.pinId);
    final rows = await DatabaseHelper.instance.getMessages(widget.pinId);
    if (!mounted) return;
    setState(() {
      _pin = ReportPinAdapter.pinFromReport(report, widget.pinId);
      _status = (report.fields['status']?.value as String?) ?? 'Open';
      _messages = ReportPinAdapter.threadMessagesFromRows(
        rows,
        widget.pinId,
        DeviceIdentity.current,
      );
    });
  }
 
  /// Change one field of this report (status, severity...). The new value
  /// gets a fresh HLC timestamp, is saved locally, then pushed to any
  /// connected device. If another device changed the same field while we
  /// were apart, the later timestamp wins when we next sync.
  Future<void> _setField(String name, dynamic value) async {
    await DatabaseHelper.instance.upsertField(
      widget.pinId,
      name,
      FieldValue(value, SyncService.instance.nextClock()),
      DeviceIdentity.current,
    );
    await _load();
    SyncController.broadcastReport(widget.pinId);
  }
 
  Future<void> _sendMessage() async {
    final text = _composerController.text.trim();
    if (text.isEmpty) return;
    _composerController.clear();
 
    await DatabaseHelper.instance.insertMessage(
      widget.pinId,
      'msg_${DeviceIdentity.current}_${DateTime.now().microsecondsSinceEpoch}',
      DeviceIdentity.current,
      'text',
      text,
      SyncService.instance.nextClock(),
    );
    await _load();
    SyncController.broadcastReport(widget.pinId);
 
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }
      Future<void> _deleteReport(Pin pin) async {
    final deleted = await ReportActions.deleteWithConfirm(context, pin);
    if (deleted && mounted) Navigator.of(context).pop();
  }
  @override
  Widget build(BuildContext context) {
    final pin = _pin;
    if (pin == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
            appBar: AppBar(
        title: Text(pin.category.label),
        actions: [
          IconButton(
            tooltip: 'Report location on map',
            icon: const Icon(Icons.map_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ReportMapScreen(pin: pin)),
            ),
          ),
                    if (ReportActions.canDelete(pin))
            IconButton(
              tooltip: 'Delete report',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _deleteReport(pin),
            ),
        ],
      ),
      body: Column(
        children: [
          _ReportSummaryCard(pin: pin),
          _ControlsBar(
            status: _status,
            severity: pin.severity,
            onStatusChanged: (s) => _setField('status', s),
            onSeverityChanged: (s) => _setField('severity', s.name),
          ),
          const Divider(height: 1),
          Expanded(
            child: _ThreadList(
              messages: _messages,
              scrollController: _scrollController,
            ),
          ),
          _Composer(controller: _composerController, onSend: _sendMessage),
        ],
      ),
    );
  }
}
 
class _ControlsBar extends StatelessWidget {
  final String status;
  final Severity severity;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<Severity> onSeverityChanged;
 
  const _ControlsBar({
    required this.status,
    required this.severity,
    required this.onStatusChanged,
    required this.onSeverityChanged,
  });
 
  static const _statuses = ['Open', 'In progress', 'Resolved'];
 
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final safeStatus = _statuses.contains(status) ? status : 'Open';
 
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Row(
        children: [
          Expanded(
            child: _LabeledDropdown<String>(
              label: 'Status',
              value: safeStatus,
              items: _statuses
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: onStatusChanged,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _LabeledDropdown<Severity>(
              label: 'Severity',
              value: severity,
              items: Severity.values
                  .map((s) => DropdownMenuItem(value: s, child: Text(s.label)))
                  .toList(),
              onChanged: onSeverityChanged,
            ),
          ),
        ],
      ),
    );
  }
}
 
class _LabeledDropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T> onChanged;
 
  const _LabeledDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });
 
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 1.1,
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        DropdownButton<T>(
          value: value,
          isExpanded: true,
          items: items,
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ],
    );
  }
}
 
class _ReportSummaryCard extends StatelessWidget {
  final Pin pin;
  const _ReportSummaryCard({required this.pin});
 
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final age = DateTime.now().difference(pin.createdAt);
 
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Badge(
                icon: pin.severity.icon,
                label: pin.severity.label,
                color: pin.severity.color,
                filled: true,
              ),
              _Badge(
                icon: pin.category.icon,
                label: pin.category.label,
                color: theme.colorScheme.onSurfaceVariant,
                filled: false,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            pin.title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (pin.description.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              pin.description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.person_outline,
                  size: 16, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(pin.authorName, style: theme.textTheme.bodySmall),
              const SizedBox(width: 14),
              Icon(Icons.location_on_outlined,
                  size: 16, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                '${pin.lat.toStringAsFixed(4)}, ${pin.lng.toStringAsFixed(4)}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(width: 14),
              Icon(Icons.schedule,
                  size: 16, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(_formatAge(age), style: theme.textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
 
  String _formatAge(Duration d) {
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}
 
class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool filled;
 
  const _Badge({
    required this.icon,
    required this.label,
    required this.color,
    required this.filled,
  });
 
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.16) : null,
        border: filled ? null : Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}
 
class _ThreadList extends StatelessWidget {
  final List<ThreadMessage> messages;
  final ScrollController scrollController;
 
  const _ThreadList({required this.messages, required this.scrollController});
 
  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return Center(
        child: Text(
          'No messages yet — be the first to update this report.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }
 
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      itemCount: messages.length,
      itemBuilder: (context, index) => _MessageBubble(message: messages[index]),
    );
  }
}
 
class _MessageBubble extends StatelessWidget {
  final ThreadMessage message;
  const _MessageBubble({required this.message});
 
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOwn = message.isOwnDevice;
 
    return Align(
      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isOwn
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isOwn ? 16 : 4),
            bottomRight: Radius.circular(isOwn ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isOwn)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  message.authorName,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            Text(
              message.text,
              style: TextStyle(
                color: isOwn
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(message.timestamp),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: (isOwn
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurfaceVariant)
                        .withValues(alpha: 0.7),
                  ),
                ),
                if (isOwn) ...[
                  const SizedBox(width: 5),
                  Icon(
                    message.synced ? Icons.done_all : Icons.schedule,
                    size: 13,
                    color: message.synced
                        ? theme.colorScheme.onPrimaryContainer
                            .withValues(alpha: 0.7)
                        : theme.colorScheme.error,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
 
  String _formatTime(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
 
class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
 
  const _Composer({required this.controller, required this.onSend});
 
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border:
              Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                textCapitalization: TextCapitalization.sentences,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Add an update…',
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              icon: const Icon(Icons.arrow_upward_rounded),
              onPressed: onSend,
            ),
          ],
        ),
      ),
    );
  }
}