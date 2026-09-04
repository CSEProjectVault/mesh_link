import 'package:flutter/material.dart';
import 'screens/login_join_screen.dart';
import 'screens/home_screen.dart';
import 'screens/create_pin_screen.dart';
import 'screens/report_detail_screen.dart';

void main() {
  runApp(const MeshLinkApp());
}

class MeshLinkApp extends StatelessWidget {
  const MeshLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MeshLink',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) =>  LoginJoinScreen(),
        '/home': (context) => HomeScreen(),
        '/create': (context) => const CreatePinScreen(),
        '/detail': (context) => const ReportDetailScreen(),
      },
    );
  }
}