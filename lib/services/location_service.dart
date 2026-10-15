import 'package:geolocator/geolocator.dart';

/// A plain latitude/longitude pair.
class GeoPoint {
  final double lat;
  final double lng;
  const GeoPoint(this.lat, this.lng);
}

/// Formats a position the way it is shown and copied everywhere in the app,
/// e.g. "13.08270, 80.27070" (5 decimals is roughly 1 metre).
String formatLatLng(double lat, double lng) =>
    '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';

/// One place that knows how to get the phone's position.
///
/// GPS works without internet, so this is fine offline. It returns null when
/// no position can be had (permission denied, location switched off, no fix).
/// Callers must handle null; never invent coordinates for a rescue report.
class LocationService {
  LocationService._();

  static Future<GeoPoint?> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return await _lastKnown();
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return await _lastKnown();
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      return GeoPoint(pos.latitude, pos.longitude);
    } catch (_) {
      // Timeout, no fix, or plugin error: fall back to the last known spot.
      return _lastKnown();
    }
  }

  static Future<GeoPoint?> _lastKnown() async {
    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos == null) return null;
      return GeoPoint(pos.latitude, pos.longitude);
    } catch (_) {
      return null;
    }
  }
}
