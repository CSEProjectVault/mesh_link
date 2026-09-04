import 'package:flutter/material.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Fake/hardcoded pins for now — real data comes later from the local database
  final List<Map<String, dynamic>> pins = [
    {'title': 'Bridge collapse — Zone 3', 'severity': 'Emergency', 'color': Colors.red},
    {'title': 'Road blocked — Zone 4', 'severity': 'High', 'color': Colors.orange},
    {'title': 'Medical camp — Zone 2', 'severity': 'Resolved', 'color': Colors.green},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MeshLink'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Chip(
                avatar: const Icon(Icons.wifi, size: 16, color: Colors.green),
                label: const Text('3 nearby'),
                backgroundColor: Colors.green[50],
              ),
            ),
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: pins.length,
        itemBuilder: (context, index) {
          final pin = pins[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: CircleAvatar(
                radius: 8,
                backgroundColor: pin['color'],
              ),
              title: Text(pin['title']),
              subtitle: Text(pin['severity']),
              onTap: () {
                Navigator.pushNamed(context, '/detail');
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.pushNamed(context, '/create');
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}