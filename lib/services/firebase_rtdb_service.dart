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
}
