import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/pin_models.dart';
import '../models/report_pin_adapter.dart';
import 'report_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Pin>> _pinsFuture;

  @override
  void initState() {
    super.initState();
    _pinsFuture = _loadPins();
  }

  Future<List<Pin>> _loadPins() async {
    final ids = await DatabaseHelper.instance.getAllReportIds();
    final pins = <Pin>[];
    for (final id in ids) {
      final report = await DatabaseHelper.instance.getReport(id);
      pins.add(ReportPinAdapter.pinFromReport(report, id));
    }
    // Most severe first, then newest first
    pins.sort((a, b) {
      final bySeverity = b.severity.index.compareTo(a.severity.index);
      return bySeverity != 0 ? bySeverity : b.createdAt.compareTo(a.createdAt);
    });
    return pins;
  }

  void _reload() => setState(() => _pinsFuture = _loadPins());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MeshLink')),
      body: FutureBuilder<List<Pin>>(
        future: _pinsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final pins = snapshot.data ?? [];
          if (pins.isEmpty) {
            return const Center(child: Text('No reports yet. Tap + to add one.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: pins.length,
            itemBuilder: (context, i) {
              final pin = pins[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: CircleAvatar(radius: 8, backgroundColor: pin.severity.color),
                  title: Text(pin.title),
                  subtitle: Text('${pin.severity.label} · ${pin.category.label}'),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReportDetailScreen(pinId: pin.id),
                      ),
                    );
                    _reload();
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
          _reload(); // refresh the list when she comes back from Create
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}