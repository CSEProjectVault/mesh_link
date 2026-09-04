import 'package:flutter/material.dart';

class LoginJoinScreen extends StatefulWidget {
  const LoginJoinScreen({super.key});

  @override
  State<LoginJoinScreen> createState() => _LoginJoinScreenState();
}

class _LoginJoinScreenState extends State<LoginJoinScreen> {
  // This is the "state" — which tab is currently selected.
  // When this changes, Flutter automatically redraws the screen.
  bool showOrgTab = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
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

              // Tab toggle
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

              // Show different content depending on which tab is selected
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
            onPressed: () {
              // Fake login for now — just navigate to Home
              Navigator.pushReplacementNamed(context, '/home');
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Log in'),
            ),
          ),
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
            onPressed: () {
              Navigator.pushReplacementNamed(context, '/home');
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Join trip'),
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextButton(
          onPressed: () {
            Navigator.pushReplacementNamed(context, '/home');
          },
          child: const Text('Start a new trip instead'),
        ),
      ],
    );
  }
}