import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class LoginJoinScreen extends StatefulWidget {
  const LoginJoinScreen({super.key});

  @override
  State<LoginJoinScreen> createState() => _LoginJoinScreenState();
}

class _LoginJoinScreenState extends State<LoginJoinScreen> {
  bool showOrgTab = true;
  bool _busy = false;

  final _orgId = TextEditingController();
  final _orgName = TextEditingController();
  final _orgPin = TextEditingController();
  final _tripName = TextEditingController();
  final _tripCode = TextEditingController();

  @override
  void dispose() {
    _orgId.dispose();
    _orgName.dispose();
    _orgPin.dispose();
    _tripName.dispose();
    _tripCode.dispose();
    super.dispose();
  }

  /// Runs a login action. There is no navigation here: on success AuthService
  /// updates its session and main.dart swaps this screen for Home.
  Future<void> _run(Future<Session> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
        TextField(
          controller: _orgId,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Organization ID',
            hintText: 'e.g. SAR-DEMO',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _orgName,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Your name',
            hintText: 'e.g. Alpha',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _orgPin,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'PIN',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _busy
                ? null
                : () => _run(() => AuthService.instance.orgLogin(
                      orgId: _orgId.text,
                      memberName: _orgName.text,
                      pin: _orgPin.text,
                    )),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_busy ? 'Checking...' : 'Log in'),
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Demo organization: SAR-DEMO, PIN 2468',
          style: TextStyle(color: Colors.grey, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildTripForm() {
    return Column(
      children: [
        TextField(
          controller: _tripName,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Your name',
            hintText: 'e.g. Meena',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _tripCode,
          textAlign: TextAlign.center,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Trip code',
            hintText: 'e.g. K7M2QX',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _busy
                ? null
                : () => _run(() => AuthService.instance
                    .joinTrip(_tripName.text, _tripCode.text)),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Join trip'),
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextButton(
          onPressed: _busy
              ? null
              : () => _run(() => AuthService.instance.startTrip(_tripName.text)),
          child: const Text('Start a new trip instead'),
        ),
      ],
    );
  }
}