import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'ac_api_service.dart';

/// Lightweight Firebase RTDB service using REST API.
/// Sets /unlock_door to true on access granted.
class FirebaseRtdbService {
  static const String _dbUrl =
      'https://vdb-poc-default-rtdb.asia-southeast1.firebasedatabase.app';

  /// Set /automation-flags/unlock_door to true
  static Future<(bool, String)> triggerUnlock() async {
    try {
      final url = Uri.parse('$_dbUrl/automation-flags/unlock_door.json');
      final response = await http.put(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(true),
      );

      if (response.statusCode == 200) {
        debugPrint('🔥 FirebaseRTDB: unlock_door set to true');
        return (true, 'Firebase unlock triggered');
      } else {
        debugPrint(
          '❌ FirebaseRTDB: Failed (${response.statusCode}): ${response.body}',
        );
        return (false, 'Firebase error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ FirebaseRTDB: Error: $e');
      return (false, 'Firebase error: $e');
    }
  }

  // ────────── Per-user personalization ──────────

  /// Helper: PUT a single field under /automation-flags/
  static Future<bool> _setField(String field, dynamic value) async {
    final url = Uri.parse('$_dbUrl/automation-flags/$field.json');
    final response = await http.put(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(value),
    );
    return response.statusCode == 200;
  }

  /// Fetch preset for a user from /presets/{username} in Firebase RTDB.
  /// Returns null if the user has no preset entry.
  static Future<Map<String, dynamic>?> _fetchUserPreset(String username) async {
    final url = Uri.parse('$_dbUrl/presets/$username.json');
    final response = await http.get(url);
    if (response.statusCode == 200 && response.body != 'null') {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    }
    return null;
  }

  /// Apply per-user personalization flags by reading from /presets/{username}.
  /// If the user exists in /presets, each key-value pair is written to
  /// /automation-flags. If the user is not listed, personalization is skipped.
  /// Call this alongside triggerUnlock() when access is granted.
  static Future<(bool, String)> applyPersonalization(String username) async {
    final nameLower = username.toLowerCase();

    try {
      // Fetch the user's preset from Firebase /presets/{username}
      final preset = await _fetchUserPreset(nameLower);

      if (preset == null || preset.isEmpty) {
        debugPrint(
          '🔥 FirebaseRTDB: No preset found for "$nameLower" – skipping personalization',
        );
        return (true, 'No preset for $nameLower');
      }

      debugPrint(
        '🔥 FirebaseRTDB: Preset found for "$nameLower" – applying ${preset.length} fields',
      );

      // Write each preset parameter to /automation-flags
      for (final entry in preset.entries) {
        final ok = await _setField(entry.key, entry.value);
        debugPrint(
          '🔥 FirebaseRTDB: ${entry.key} = ${entry.value} → ${ok ? "✅" : "❌"}',
        );
        if (!ok) {
          return (false, 'Failed to set ${entry.key}');
        }
      }

      // Update /automation-flags/profile with the matched username
      final profileOk = await _setField('profile', nameLower);
      debugPrint(
        '🔥 FirebaseRTDB: profile = $nameLower → ${profileOk ? "✅" : "❌"}',
      );

      // Update dev_env/ack with access granted message
      final ackUrl = Uri.parse('$_dbUrl/dev_env/ack.json');
      final ackResponse = await http.put(
        ackUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode('Success-Access granted to $nameLower'),
      );
      final ackOk = ackResponse.statusCode == 200;
      debugPrint('🔥 FirebaseRTDB: dev_env/ack → ${ackOk ? "✅" : "❌"}');

      // ────────── AC control from preset ──────────
      // Check if preset has any AC keys and forward to AC API
      final acKeys = ['ac', 'ac-fan-speed', 'ac-mode', 'ac-temp'];
      final hasAcPreset = acKeys.any((k) => preset.containsKey(k));
      if (hasAcPreset) {
        debugPrint('❄️ FirebaseRTDB: AC keys found in preset – applying via AC API');
        final (acOk, acMsg) = await AcApiService().applyPreset(preset);
        debugPrint('❄️ FirebaseRTDB: AC result: $acOk – $acMsg');
      }

      return (true, 'Personalization applied for $nameLower');
    } catch (e) {
      debugPrint('❌ FirebaseRTDB: Personalization error: $e');
      return (false, 'Personalization error: $e');
    }
  }
}
