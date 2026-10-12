import 'package:flutter/material.dart';

import 'config/device_identity.dart';
import 'screens/create_pin_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_join_screen.dart';
import 'services/auth_service.dart';
import 'sync/sync_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Restore a saved login, if there is one.
  await AuthService.instance.load();

  final session = AuthService.instance.session.value;
  if (session != null) {
    DeviceIdentity.current = session.displayName;
    // Not awaited: permission prompts must not block the first screen.
    SyncController.start(session.displayName);
  }

  runApp(MeshLinkApp(startLoggedIn: session != null));
}

class MeshLinkApp extends StatelessWidget {
  final bool startLoggedIn;
  const MeshLinkApp({super.key, required this.startLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MeshLink',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
      ),
      initialRoute: startLoggedIn ? '/home' : '/',
      routes: {
        '/': (context) => const LoginJoinScreen(),
        '/home': (context) => HomeScreen(),
        '/create': (context) => const CreatePinScreen(),
      },
    );
  }
}