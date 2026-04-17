import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// AC API service – handles login, token management, and AC control.
/// Token auto-refreshes every 45 minutes and on app open.
class AcApiService {
  static final AcApiService _instance = AcApiService._internal();
  factory AcApiService() => _instance;
  AcApiService._internal();

  static const String _loginUrl =
      'https://14uv336e1j.execute-api.ap-south-1.amazonaws.com/dev/v1/login2';
  static const String _controlBaseUrl =
      'https://14uv336e1j.execute-api.ap-south-1.amazonaws.com/dev/v1/user/nodes/params';
  static const String _nodeIdUrl =
      'https://vdb-poc-default-rtdb.asia-southeast1.firebasedatabase.app/automation-flags/ac-node-id.json';

  String? _cachedNodeId;

  static const String _userName = '+918268667702';
  static const String _password = 'Keyoor@97';

  String? _accessToken;
  DateTime? _tokenFetchedAt;
  Timer? _refreshTimer;

  /// Initialize – login immediately and start 45-min refresh cycle.
  Future<void> initialize() async {
    debugPrint('❄️ AcAPI: Initializing...');
    await _login();
    _startRefreshTimer();
  }

  /// Login and extract access token.
  Future<bool> _login() async {
    try {
      debugPrint('❄️ AcAPI: Logging in...');
      final response = await http.post(
        Uri.parse(_loginUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_name': _userName,
          'password': _password,
        }),
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final token = body['accesstoken'] as String?;
        if (token != null && token.isNotEmpty) {
          _accessToken = token;
          _tokenFetchedAt = DateTime.now();
          debugPrint(
            '✅ AcAPI: Login success – token length: ${token.length}',
          );
          return true;
        }
        debugPrint('❌ AcAPI: Login response missing accesstoken');
      } else {
        debugPrint(
          '❌ AcAPI: Login failed (${response.statusCode}): ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('❌ AcAPI: Login error: $e');
    }
    return false;
  }

  /// Start a periodic timer to refresh token every 45 minutes.
  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(minutes: 45), (_) {
      debugPrint('❄️ AcAPI: 45-min token refresh triggered');
      _login();
    });
    debugPrint('❄️ AcAPI: Refresh timer started (every 45 min)');
  }

  /// Ensure we have a valid token; re-login if stale or missing.
  Future<bool> _ensureToken() async {
    if (_accessToken != null && _tokenFetchedAt != null) {
      final age = DateTime.now().difference(_tokenFetchedAt!);
      if (age.inMinutes < 55) return true; // still valid
    }
    return await _login();
  }

  /// Fetch the AC node ID from Firebase RTDB.
  Future<String?> _fetchNodeId() async {
    if (_cachedNodeId != null) return _cachedNodeId;
    try {
      debugPrint('❄️ AcAPI: Fetching ac-node-id from Firebase...');
      final response = await http.get(Uri.parse(_nodeIdUrl));
      if (response.statusCode == 200 && response.body != 'null') {
        // Firebase REST returns JSON-encoded string (with quotes)
        final decoded = jsonDecode(response.body);
        if (decoded is String && decoded.isNotEmpty) {
          _cachedNodeId = decoded;
          debugPrint('✅ AcAPI: ac-node-id = $_cachedNodeId');
          return _cachedNodeId;
        }
      }
      debugPrint('❌ AcAPI: Failed to fetch ac-node-id (${response.statusCode})');
    } catch (e) {
      debugPrint('❌ AcAPI: Error fetching ac-node-id: $e');
    }
    return null;
  }

  /// Send a single AC parameter update.
  Future<bool> _putAcParam(Map<String, dynamic> acBody) async {
    if (!await _ensureToken()) {
      debugPrint('❌ AcAPI: No valid token – skipping AC command');
      return false;
    }
    final nodeId = await _fetchNodeId();
    if (nodeId == null) {
      debugPrint('❌ AcAPI: No node ID available – skipping AC command');
      return false;
    }
    try {
      final controlUrl = '$_controlBaseUrl?node_id=$nodeId';
      final response = await http.put(
        Uri.parse(controlUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': _accessToken!,
        },
        body: jsonEncode({'AC': acBody}),
      );
      final ok = response.statusCode == 200;
      debugPrint(
        '❄️ AcAPI: PUT $acBody → ${ok ? "✅" : "❌ ${response.statusCode}"}',
      );
      return ok;
    } catch (e) {
      debugPrint('❌ AcAPI: PUT error: $e');
      return false;
    }
  }

  // ────────── Public control methods ──────────

  /// Set AC power on/off.
  Future<bool> setPower(bool on) => _putAcParam({'Power': on});

  /// Set fan speed: "low", "med", "high".
  Future<bool> setFanSpeed(String speed) => _putAcParam({'Fan Speed': speed});

  /// Set mode: "fan", "cool", "auto".
  Future<bool> setMode(String mode) => _putAcParam({'Mode': mode});

  /// Set temperature (16-31).
  Future<bool> setTemperature(int temp) =>
      _putAcParam({'Temperature': temp.clamp(16, 31)});

  /// Apply a full preset map from Firebase (keys: ac, ac-fan-speed, ac-mode, ac-temp).
  /// Each parameter is sent as a separate API call since the API supports one at a time.
  /// If ac is false (power off), only the power-off command is sent – other params are
  /// skipped to prevent the AC from turning back on.
  Future<(bool, String)> applyPreset(Map<String, dynamic> preset) async {
    debugPrint('❄️ AcAPI: Applying preset: $preset');

    final acPower = preset['ac'];
    final fanSpeed = preset['ac-fan-speed'];
    final acMode = preset['ac-mode'];
    final acTemp = preset['ac-temp'];

    // Determine whether AC should be on or off
    final bool powerOn = acPower is bool ? acPower : acPower == true;

    // Power
    if (acPower != null) {
      final ok = await setPower(powerOn);
      if (!ok) return (false, 'Failed to set AC power');
    }

    // If AC is being turned OFF, skip all other parameters.
    // Sending fan-speed / mode / temp after power-off would turn the AC back on.
    if (!powerOn) {
      debugPrint('❄️ AcAPI: AC power is OFF – skipping fan/mode/temp');
      return (true, 'AC powered off');
    }

    // Fan speed
    if (fanSpeed != null) {
      final ok = await setFanSpeed(fanSpeed.toString());
      if (!ok) return (false, 'Failed to set fan speed');
    }

    // Mode
    if (acMode != null) {
      final ok = await setMode(acMode.toString());
      if (!ok) return (false, 'Failed to set AC mode');
    }

    // Temperature
    if (acTemp != null) {
      final temp = acTemp is int ? acTemp : int.tryParse(acTemp.toString());
      if (temp != null) {
        final ok = await setTemperature(temp);
        if (!ok) return (false, 'Failed to set temperature');
      }
    }

    return (true, 'AC preset applied');
  }

  void dispose() {
    _refreshTimer?.cancel();
    debugPrint('❄️ AcAPI: Disposed');
  }
}
