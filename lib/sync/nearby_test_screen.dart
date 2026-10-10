import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';

/// SPIKE ONLY: smallest possible proof that two phones can talk.
/// Phone A taps Advertise, phone B taps Discover. They auto-connect
/// (both sides auto-accept), then either phone taps Send "hello".

const String _serviceId = 'com.meshlink.app.spike';
const Strategy _strategy = Strategy.P2P_CLUSTER; // many-to-many, suits mesh

class NearbyTestScreen extends StatefulWidget {
  const NearbyTestScreen({super.key});

  @override
  State<NearbyTestScreen> createState() => _NearbyTestScreenState();
}

class _NearbyTestScreenState extends State<NearbyTestScreen> {
  final List<String> _log = [];
  final Set<String> _connected = {};
  final Set<String> _requested = {};
  String _myName = 'MeshLink';
  bool _advertising = false;
  bool _discovering = false;

  @override
  void initState() {
    super.initState();
    _loadName();
  }

  @override
  void dispose() {
    Nearby().stopAdvertising();
    Nearby().stopDiscovery();
    Nearby().stopAllEndpoints();
    super.dispose();
  }

  void _add(String line) {
    debugPrint('[nearby] $line');
    if (!mounted) return;
    setState(() => _log.insert(0, line));
  }

  Future<void> _loadName() async {
    if (!Platform.isAndroid) return;
    final info = await DeviceInfoPlugin().androidInfo;
    if (!mounted) return;
    setState(() => _myName = info.model);
  }

  // ---- Permissions -------------------------------------------------------

  Future<bool> _ensurePermissions() async {
    if (!Platform.isAndroid) return true;
    final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;

    final perms = <Permission>[Permission.location];
    if (sdk >= 31) {
      perms.addAll([
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
      ]);
    }
    if (sdk >= 33) perms.add(Permission.nearbyWifiDevices);

    final results = await perms.request();
    final denied = results.entries.where((e) => !e.value.isGranted).toList();
    for (final d in denied) {
      _add('DENIED: ${d.key} (${d.value})');
    }

    final locationOn = (await Permission.location.serviceStatus).isEnabled;
    if (!locationOn) {
      _add('WARNING: Location services are OFF. Turn them on in system '
          'settings, discovery often fails without them.');
    }
    return denied.isEmpty;
  }

  // ---- Shared connection callbacks --------------------------------------

  void _onConnectionInitiated(String id, ConnectionInfo info) {
    _add('Connection initiated with ${info.endpointName} ($id), accepting');
    Nearby().acceptConnection(
      id,
      // NOTE: "Recieved" is misspelled in the plugin's own API.
      onPayLoadRecieved: (endpointId, payload) {
        if (payload.type == PayloadType.BYTES && payload.bytes != null) {
          _add('RECEIVED from $endpointId: ${utf8.decode(payload.bytes!)}');
        }
      },
      onPayloadTransferUpdate: (endpointId, update) {},
    );
  }

  void _onConnectionResult(String id, Status status) {
    _add('Connection result for $id: $status');
    if (status == Status.CONNECTED) {
      if (mounted) setState(() => _connected.add(id));
    } else {
      _requested.remove(id);
    }
  }

  void _onDisconnected(String id) {
    _add('Disconnected: $id');
    _requested.remove(id);
    if (mounted) setState(() => _connected.remove(id));
  }

  // ---- Buttons -----------------------------------------------------------

  Future<void> _advertise() async {
    if (!await _ensurePermissions()) {
      _add('Cannot advertise: missing permissions.');
      return;
    }
    try {
      final ok = await Nearby().startAdvertising(
        _myName,
        _strategy,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
        serviceId: _serviceId,
      );
      _add(ok ? 'Advertising as "$_myName"' : 'startAdvertising returned false');
      if (mounted) setState(() => _advertising = ok);
    } catch (e) {
      _add('Advertise ERROR: $e');
    }
  }

  Future<void> _discover() async {
    if (!await _ensurePermissions()) {
      _add('Cannot discover: missing permissions.');
      return;
    }
    try {
      final ok = await Nearby().startDiscovery(
        _myName,
        _strategy,
        onEndpointFound: (id, name, serviceId) {
          _add('Found "$name" ($id)');
          if (_requested.add(id)) {
            Nearby().requestConnection(
              _myName,
              id,
              onConnectionInitiated: _onConnectionInitiated,
              onConnectionResult: _onConnectionResult,
              onDisconnected: _onDisconnected,
            );
          }
        },
        onEndpointLost: (id) => _add('Lost endpoint: $id'),
        serviceId: _serviceId,
      );
      _add(ok ? 'Discovering...' : 'startDiscovery returned false');
      if (mounted) setState(() => _discovering = ok);
    } catch (e) {
      _add('Discover ERROR: $e');
    }
  }

  Future<void> _sendHello() async {
    if (_connected.isEmpty) {
      _add('No connected peers yet.');
      return;
    }
    final bytes = Uint8List.fromList(utf8.encode('hello from $_myName'));
    for (final id in _connected) {
      try {
        await Nearby().sendBytesPayload(id, bytes);
        _add('SENT hello to $id');
      } catch (e) {
        _add('Send ERROR to $id: $e');
      }
    }
  }

  // ---- UI ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Nearby Test')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This device: $_myName', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Advertising: $_advertising   Discovering: $_discovering   '
              'Connected peers: ${_connected.length}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton(onPressed: _advertise, child: const Text('Advertise')),
                FilledButton(onPressed: _discover, child: const Text('Discover')),
                FilledButton.tonal(
                  onPressed: _sendHello,
                  child: const Text('Send "hello"'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: _log.length,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(_log[i], style: theme.textTheme.bodySmall),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
