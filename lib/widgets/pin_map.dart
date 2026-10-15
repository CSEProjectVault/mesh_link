import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/pin_models.dart';
import '../services/location_service.dart';

/// Map of pins with a live "you are here" dot and your coordinates.
///
/// OFFLINE NOTE: map *tiles* (the street/terrain images) come from the
/// internet. Without a connection the background stays blank, but pins, your
/// GPS dot and the coordinate readout still work, because those need no
/// network. For real offline tiles, pre-download an area while online (see the
/// flutter_map_tile_caching package).
class PinMap extends StatefulWidget {
  final List<Pin> pins;
  final ValueChanged<Pin>? onPinTap;

  /// When set, the map opens centred on this report (instead of on you) and
  /// shows how far away it is.
  final Pin? focusPin;

  /// Space kept free at the bottom-right for the recentre button, so it does
  /// not sit under a floating action button on the screen hosting the map.
  final double controlsBottomInset;

  const PinMap({
    super.key,
    required this.pins,
    this.onPinTap,
    this.focusPin,
    this.controlsBottomInset = 12,
  });

  @override
  State<PinMap> createState() => _PinMapState();
}

class _PinMapState extends State<PinMap> {
  final MapController _controller = MapController();
  StreamSubscription<Position>? _sub;
  LatLng? _me;
  late bool _following;

  @override
  void initState() {
    super.initState();
    // Follow the user by default, but not when we were asked to show one
    // specific report.
    _following = widget.focusPin == null;
    _startLocation();
  }

  Future<void> _startLocation() async {
    // LocationService asks for permission and returns null if there is no
    // position at all.
    final first = await LocationService.current();
    if (!mounted) return;
    if (first != null) {
      final point = LatLng(first.lat, first.lng);
      setState(() => _me = point);
      if (_following) _moveTo(point);
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
    final focus = widget.focusPin;
    if (focus != null) return LatLng(focus.lat, focus.lng);
    if (_me != null) return _me!;
    if (widget.pins.isNotEmpty) {
      return LatLng(widget.pins.first.lat, widget.pins.first.lng);
    }
    return const LatLng(20.5937, 78.9629); // fallback: centre of India
  }

  static String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = _me;
    final focus = widget.focusPin;
    final hasTarget = me != null || focus != null || widget.pins.isNotEmpty;

    String? distanceText;
    if (focus != null && me != null) {
      final meters = const Distance()
          .as(LengthUnit.Meter, me, LatLng(focus.lat, focus.lng));
      distanceText = _formatDistance(meters);
    }

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
                if (me != null)
                  Marker(
                    point: me,
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
        // Your coordinates (and distance to the report, if one is focused).
        // Plain text, so it stays useful with no internet and blank tiles.
        if (me != null)
          Positioned(
            left: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.my_location, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        'You  ${formatLatLng(me.latitude, me.longitude)}',
                        style: theme.textTheme.labelMedium,
                      ),
                    ],
                  ),
                  if (distanceText != null && focus != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          focus.severity.icon,
                          size: 14,
                          color: focus.severity.color,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$distanceText to report',
                          style: theme.textTheme.labelMedium,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        Positioned(
          right: 12,
          bottom: widget.controlsBottomInset,
          child: FloatingActionButton.small(
            // No hero tag: several maps can be on the navigation stack at once.
            heroTag: null,
            tooltip: 'Centre on my location',
            onPressed: me == null
                ? null
                : () {
                    setState(() => _following = true);
                    _moveTo(me);
                  },
            child: Icon(
              _following ? Icons.my_location : Icons.location_searching,
            ),
          ),
        ),
        if (me == null)
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
