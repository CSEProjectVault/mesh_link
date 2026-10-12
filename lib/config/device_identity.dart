/// Who this phone is. Set once after login (and on app start if a saved
/// session exists). The adapter uses it to decide which messages are "yours".
class DeviceIdentity {
  static String current = 'You';
}

/// Kept so existing code (`currentDeviceName`) keeps working unchanged.
String get currentDeviceName => DeviceIdentity.current;