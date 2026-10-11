import 'package:flutter/material.dart';
import '../config/device_identity.dart';

class LoginJoinScreen extends StatefulWidget {
  const LoginJoinScreen({super.key});

  @override
  State<LoginJoinScreen> createState() => _LoginJoinScreenState();
}

class _LoginJoinScreenState extends State<LoginJoinScreen> {
  // Which tab is currently selected. Changing it redraws the screen.
  bool showOrgTab = true;
  final _usernameController = TextEditingController();
  final _tripNameController = TextEditingController();

  @override
  void dispose() {
    _usernameController.dispose();
    _tripNameController.dispose();
    super.dispose();
  }

  /// The username (or trip name) becomes this phone's identity. It labels
  /// the reports and messages this phone writes, and decides which chat
  /// bubbles show as "mine". Two phones must use different names.
  void _enter(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a name to continue.')),
      );
      return;
    }
    DeviceIdentity.current = trimmed;
    Navigator.pushReplacementNamed(context, '/home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 40),
              const Text(
                'MeshLink',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              const Text(
                'Works with or without a connection',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => showOrgTab = true),
                        child: _buildTab('Organization', showOrgTab),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => showOrgTab = false),
                        child: _buildTab('Join a trip', !showOrgTab),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (showOrgTab) _buildOrgForm() else _buildTripForm(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTab(String label, bool selected) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: selected ? Colors.teal : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : Colors.grey[700],
          fontWeight: FontWeight.w500,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildOrgForm() {
    return Column(
      children: [
        const TextField(
          decoration: InputDecoration(
            labelText: 'Organization ID',
            hintText: 'e.g. district-rescue-12',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _usernameController,
          decoration: const InputDecoration(
            labelText: 'Username',
            hintText: 'e.g. alpha',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        const TextField(
          obscureText: true,
          decoration: InputDecoration(
            labelText: 'Password',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => _enter(_usernameController.text),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Log in'),
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Demo mode: organization ID and password are not verified yet.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildTripForm() {
    return Column(
      children: [
        const TextField(
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            labelText: 'Trip code',
            hintText: 'e.g. RIDGE-482',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _tripNameController,
          decoration: const InputDecoration(
            labelText: 'Your name',
            hintText: 'e.g. Meena',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.qr_code),
            label: const Text('Scan QR instead'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => _enter(_tripNameController.text),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Join trip'),
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextButton(
          onPressed: () => _enter(_tripNameController.text),
          child: const Text('Start a new trip instead'),
        ),
      ],
    );
  }
}