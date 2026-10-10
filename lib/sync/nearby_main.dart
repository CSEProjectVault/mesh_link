import 'package:flutter/material.dart';
import 'nearby_test_screen.dart';

/// Standalone entry point for the Nearby spike, so main.dart stays untouched.
/// Run with:  flutter run -t lib/sync/nearby_main.dart
void main() {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const NearbyTestScreen(),
    ),
  );
}
