import 'package:flutter/material.dart';
import '../config/device_identity.dart';
import '../db/database_helper.dart';
import '../models/pin_models.dart';
import '../models/report_pin_adapter.dart';
import '../sync/sync_controller.dart';
import '../sync/sync_service.dart';
import 'report_detail_screen.dart';
 
class _HomeItem {
  final Pin pin;
  final String status;
  const _HomeItem(this.pin, this.status);
}
 
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
 
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}
 
class _HomeScreenState extends State<HomeScreen> {
  late Future<List<_HomeItem>> _itemsFuture;
 
  @override
  void initState() {
    super.initState();
    _itemsFuture = _load();
    SyncService.instance.dataVersion.addListener(_onSyncData);
    // Start discovery after the first frame so permission dialogs can show.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SyncController.start(DeviceIdentity.current);
    });
  }
 
  @override
  void dispose() {
    SyncService.instance.dataVersion.removeListener(_onSyncData);
    super.dispose();
  }
 
  void _onSyncData() {
    if (mounted) _reload();
  }
 
  Future<List<_HomeItem>> _load() async {
    final ids = await DatabaseHelper.instance.getAllReportIds();
    final items = <_HomeItem>[];
    for (final id in ids) {
      final report = await DatabaseHelper.instance.getReport(id);
      items.add(_HomeItem(
        ReportPinAdapter.pinFromReport(report, id),
        (report.fields['status']?.value as String?) ?? 'Open',
      ));
    }
    // Unresolved first, then most severe, then newest.
    items.sort((a, b) {
      final aDone = a.status == 'Resolved' ? 1 : 0;
      final bDone = b.status == 'Resolved' ? 1 : 0;
      if (aDone != bDone) return aDone.compareTo(bDone);
      final bySeverity = b.pin.severity.index.compareTo(a.pin.severity.index);
      if (bySeverity != 0) return bySeverity;
      return b.pin.createdAt.compareTo(a.pin.createdAt);
    });
    return items;
  }
 
  void _reload() => setState(() => _itemsFuture = _load());
 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('MeshLink · ${DeviceIdentity.current}'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ValueListenableBuilder<int>(
              valueListenable: SyncController.peerCount,
              builder: (context, count, _) {
                final connected = count > 0;
                return Chip(
                  avatar: Icon(
                    connected ? Icons.wifi : Icons.wifi_off,
                    size: 16,
                    color: connected ? Colors.green : Colors.grey,
                  ),
                  label: Text(connected ? '$count connected' : 'No peers'),
                );
              },
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<_HomeItem>>(
        future: _itemsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return const Center(
              child: Text('No reports yet. Tap + to add one.'),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final item = items[i];
              final pin = item.pin;
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: CircleAvatar(
                    radius: 8,
                    backgroundColor: pin.severity.color,
                  ),
                  title: Text(pin.title),
                  subtitle: Text(
                    '${pin.severity.label} · ${pin.category.label} · ${item.status}',
                  ),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReportDetailScreen(pinId: pin.id),
                      ),
                    );
                    if (mounted) _reload();
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.pushNamed(context, '/create');
          if (mounted) _reload();
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}