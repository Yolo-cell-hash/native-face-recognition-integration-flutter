import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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

  /// Per-user automation profiles.
  /// Only listed users get personalization; all others just get unlock_door.
  static final Map<String, Map<String, dynamic>> _userProfiles = {
    'sd': {'light': true, 'party': true},
    'deodatta': {
      'light': true,
      'light intensity': 255,
      'light-hex-value': '35,167,78',
    },
    'parag': {
      'light': true,
      'light intensity': 150,
      'light-hex-value': '255,36,120',
    },
    'jinay': {
      'light': true,
      'light intensity': 69,
      'light-hex-value': '69,69,69',
    },
  };

  /// Apply per-user personalization flags (if a profile exists).
  /// Call this alongside triggerUnlock() when access is granted.
  static Future<(bool, String)> applyPersonalization(String username) async {
    final nameLower = username.toLowerCase();
    final profile = _userProfiles[nameLower];

    if (profile == null) {
      debugPrint(
        '🔥 FirebaseRTDB: No personalization profile for "$nameLower"',
      );
      return (true, 'No profile for $nameLower');
    }

    try {
      debugPrint('🔥 FirebaseRTDB: Applying profile for "$nameLower"');
      for (final entry in profile.entries) {
        final ok = await _setField(entry.key, entry.value);
        debugPrint(
          '🔥 FirebaseRTDB: ${entry.key} = ${entry.value} → ${ok ? "✅" : "❌"}',
        );
        if (!ok) {
          return (false, 'Failed to set ${entry.key}');
        }
      }
      return (true, 'Personalization applied for $nameLower');
    } catch (e) {
      debugPrint('❌ FirebaseRTDB: Personalization error: $e');
      return (false, 'Personalization error: $e');
    }
  }
}
