import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/pin_models.dart';
import '../services/location_service.dart';

/// Map of pins with a live "you are here" dot.
///
/// OFFLINE NOTE: map *tiles* (the street/terrain images) come from the
/// internet. Without a connection the background stays blank, but pins and
/// your GPS dot still draw correctly, because those need no network. For real
/// offline tiles, pre-download an area while online (see the
/// flutter_map_tile_caching package).
class PinMap extends StatefulWidget {
  final List<Pin> pins;
  final ValueChanged<Pin>? onPinTap;

  const PinMap({super.key, required this.pins, this.onPinTap});

  @override
  State<PinMap> createState() => _PinMapState();
}

class _PinMapState extends State<PinMap> {
  final MapController _controller = MapController();
  StreamSubscription<Position>? _sub;
  LatLng? _me;
  bool _following = true;

  @override
  void initState() {
    super.initState();
    _startLocation();
  }

  Future<void> _startLocation() async {
    // LocationService asks for permission and returns null if there is no
    // position at all.
    final first = await LocationService.current();
    if (!mounted) return;
    if (first != null) {
      setState(() => _me = LatLng(first.lat, first.lng));
    }

    // Live updates for the moving dot. Throws if permission was refused.
    try {
      _sub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen(
        (pos) {
          if (!mounted) return;
          final point = LatLng(pos.latitude, pos.longitude);
          setState(() => _me = point);
          if (_following) _moveTo(point);
        },
        onError: (_) {},
      );
    } catch (_) {}
  }

  void _moveTo(LatLng point) {
    try {
      _controller.move(point, _controller.camera.zoom);
    } catch (_) {
      // Map not ready yet; the next update will move it.
    }
  }

  Future<void> _openLocationSettings() async {
    if (await Geolocator.isLocationServiceEnabled()) {
      await Geolocator.openAppSettings();
    } else {
      await Geolocator.openLocationSettings();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  LatLng get _initialCenter {
    if (_me != null) return _me!;
    if (widget.pins.isNotEmpty) {
      return LatLng(widget.pins.first.lat, widget.pins.first.lng);
    }
    return const LatLng(20.5937, 78.9629); // fallback: centre of India
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasTarget = _me != null || widget.pins.isNotEmpty;

    return Stack(
      children: [
        FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: _initialCenter,
            initialZoom: hasTarget ? 15 : 4,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            onPositionChanged: (camera, hasGesture) {
              // Stop auto-following once the user pans the map themselves.
              if (hasGesture && _following) {
                setState(() => _following = false);
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.mesh_link',
              // Missing tiles (offline) are simply left blank.
              errorTileCallback: (tile, error, stackTrace) {},
            ),
            MarkerLayer(
              markers: [
                for (final pin in widget.pins)
                  Marker(
                    point: LatLng(pin.lat, pin.lng),
                    width: 44,
                    height: 44,
                    child: GestureDetector(
                      onTap: () => widget.onPinTap?.call(pin),
                      child: Icon(
                        pin.severity.icon,
                        color: pin.severity.color,
                        size: 36,
                      ),
                    ),
                  ),
                if (_me != null)
                  Marker(
                    point: _me!,
                    width: 24,
                    height: 24,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        Positioned(
          right: 12,
          bottom: 12,
          child: FloatingActionButton.small(
            heroTag: 'recenter',
            tooltip: 'Centre on my location',
            onPressed: _me == null
                ? null
                : () {
                    setState(() => _following = true);
                    _moveTo(_me!);
                  },
            child: Icon(
              _following ? Icons.my_location : Icons.location_searching,
            ),
          ),
        ),
        if (_me == null)
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.gps_off, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Waiting for GPS. Check that location is on and '
                        'permission is allowed.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    TextButton(
                      onPressed: _openLocationSettings,
                      child: const Text('Settings'),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}