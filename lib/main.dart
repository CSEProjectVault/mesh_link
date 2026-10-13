import 'package:flutter/material.dart';
import 'config/device_identity.dart';
import 'services/auth_service.dart';
import 'screens/login_join_screen.dart';
import 'screens/home_screen.dart';
import 'screens/create_pin_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AuthService.instance.load(); // restore a saved login, if any
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
      // Switches between Login and Home whenever the session changes.
      home: ValueListenableBuilder<Session?>(
        valueListenable: AuthService.instance.session,
        builder: (context, session, _) {
          if (session == null) return const LoginJoinScreen();
          DeviceIdentity.current = session.displayName;
          return HomeScreen(key: ValueKey(session.displayName));
        },
      ),
      routes: {
        '/create': (context) => const CreatePinScreen(),
      },
    );
  }
}