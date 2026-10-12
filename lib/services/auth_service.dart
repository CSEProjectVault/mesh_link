import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How the user got in.
enum AuthMode { hiker, org }

class Session {
  final AuthMode mode;
  final String displayName;
  final String? tripCode; // hikers
  final String? orgId; // rescue organisations

  const Session({
    required this.mode,
    required this.displayName,
    this.tripCode,
    this.orgId,
  });

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'name': displayName,
        'trip': tripCode,
        'org': orgId,
      };

  factory Session.fromJson(Map<String, dynamic> j) => Session(
        mode: AuthMode.values.byName(j['mode'] as String),
        displayName: j['name'] as String,
        tripCode: j['trip'] as String?,
        orgId: j['org'] as String?,
      );
}

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => message;
}

/// Works fully offline.
///
/// Hiker flow: no account. A name plus a trip code is the whole identity.
/// Org flow: a persistent login that survives app restarts.
///
/// SECURITY NOTE (demo only): org PINs are checked against hashes stored in
/// the app. Anyone who unpacks the APK can read them, so this proves the flow
/// and nothing more. Real accountability needs the HTTP server to verify
/// logins when online; keep the same Session shape and swap [orgLogin].
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const _prefsKey = 'meshlink_session_v1';

  /// Null when logged out. Listen to this to switch between login and home.
  final ValueNotifier<Session?> session = ValueNotifier<Session?>(null);

  bool get isLoggedIn => session.value != null;
  String get deviceName => session.value?.displayName ?? 'Unknown';

  // Demo organisations: sha256('<ORG_ID>:<PIN>').
  //   SAR-DEMO / 2468
  //   RANGER-1 / 1357
  static const Map<String, String> _demoOrgHashes = {
    'SAR-DEMO':
        '5046ff8f7de23bf29c0a415565f42496e328e1c28f740fd7347db17f69d14140',
    'RANGER-1':
        'b8c5e99a85357203704d1297c73fe3c2a5642ea817bd306fd1469ba076932d51',
  };

  /// Call once at startup, before runApp, to restore a saved login.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        session.value =
            Session.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('[auth] could not restore session: $e');
    }
  }

  // ---- Hiker flow ---------------------------------------------------------

  /// Create a new trip and become its first member. Returns the session
  /// including the generated code to show or share with the group.
  Future<Session> startTrip(String name) async {
    final s = Session(
      mode: AuthMode.hiker,
      displayName: _cleanName(name),
      tripCode: generateTripCode(),
    );
    await _save(s);
    return s;
  }

  /// Join an existing trip with the code someone shared.
  Future<Session> joinTrip(String name, String code) async {
    final normalized = normalizeCode(code);
    if (!_codePattern.hasMatch(normalized)) {
      throw AuthException('Trip codes are 6 letters and numbers.');
    }
    final s = Session(
      mode: AuthMode.hiker,
      displayName: _cleanName(name),
      tripCode: normalized,
    );
    await _save(s);
    return s;
  }

  // ---- Org flow -----------------------------------------------------------

  Future<Session> orgLogin({
    required String orgId,
    required String memberName,
    required String pin,
  }) async {
    final id = orgId.trim().toUpperCase();
    final expected = _demoOrgHashes[id];
    final given = sha256.convert(utf8.encode('$id:${pin.trim()}')).toString();
    if (expected == null || expected != given) {
      throw AuthException('Organisation ID or PIN is not correct.');
    }
    final s = Session(
      mode: AuthMode.org,
      displayName: _cleanName(memberName),
      orgId: id,
    );
    await _save(s);
    return s;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    session.value = null;
  }

  // ---- Helpers ------------------------------------------------------------

  // No 0/O or 1/I so codes are easy to read out loud.
  static const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static final _codePattern = RegExp(r'^[A-Z0-9]{6}$');

  static String generateTripCode() {
    final rng = Random.secure();
    return List.generate(6, (_) => _alphabet[rng.nextInt(_alphabet.length)])
        .join();
  }

  static String normalizeCode(String raw) =>
      raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  String _cleanName(String name) {
    final n = name.trim();
    if (n.isEmpty) throw AuthException('Please enter a name.');
    return n.length > 24 ? n.substring(0, 24) : n;
  }

  Future<void> _save(Session s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(s.toJson()));
    session.value = s;
  }
}