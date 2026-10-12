import 'package:flutter/material.dart';
import 'config/device_identity.dart';
import 'screens/create_pin_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_join_screen.dart';
import 'services/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AuthService.instance.load(); // restores a saved login, if any
  runApp(const MeshLinkApp());
}

class MeshLinkApp extends StatelessWidget {
  const MeshLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MeshLink',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: ValueListenableBuilder<Session?>(
        valueListenable: AuthService.instance.session,
        builder: (context, s, _) {
          if (s == null) return const LoginJoinScreen();
          DeviceIdentity.current = s.displayName;
          return const HomeScreen();
        },
      ),
      routes: {
        '/create': (context) => const CreatePinScreen(),
      },
    );
  }
}