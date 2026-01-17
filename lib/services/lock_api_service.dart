import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Simplified Lock API Service for Godrej Advantis IoT9
/// Handles OTP authentication, token management, and lock unlock.
class LockApiService {
  static const String apiKey = 'e8q0y264i3nxjw2pn9p2pxtbo0ub4n3b';
  static const String baseUrl = 'https://hmut-api-gdb2c.binary-labs.in';

  // SharedPreferences keys
  static const String _accessTokenKey = 'lock_access_token';
  static const String _refreshTokenKey = 'lock_refresh_token';
  static const String _tokenTimestampKey = 'lock_token_timestamp';
  static const String _refreshTokenTimestampKey =
      'lock_refresh_token_timestamp';
  static const String _phoneNumberKey = 'lock_phone_number';
  static const String _lockIdKey = 'lock_id';
  static const String _isConfiguredKey = 'lock_is_configured';

  // In-memory state
  String _accessToken = '';
  String _refreshToken = '';
  String _lockId = '';
  String _phoneNumber = '';
  bool _isConfigured = false;

  // Singleton
  static final LockApiService _instance = LockApiService._internal();
  factory LockApiService() => _instance;
  LockApiService._internal();

  // Getters
  bool get isConfigured =>
      _isConfigured && _accessToken.isNotEmpty && _lockId.isNotEmpty;
  String get phoneNumber => _phoneNumber;
  String get lockId => _lockId;
  bool get hasValidToken => _accessToken.isNotEmpty;

  /// Initialize service by loading saved tokens
  Future<void> initialize() async {
    debugPrint('🔐 LockAPI: Initializing...');
    await _loadFromPreferences();

    // Check if access token needs refresh
    if (_refreshToken.isNotEmpty && _accessToken.isEmpty) {
      debugPrint('🔐 LockAPI: Access token expired, attempting refresh...');
      await refreshAccessToken();
    }

    debugPrint(
      '🔐 LockAPI: Initialized - configured: $_isConfigured, hasToken: ${_accessToken.isNotEmpty}',
    );
  }

  /// Load saved state from SharedPreferences
  Future<void> _loadFromPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _phoneNumber = prefs.getString(_phoneNumberKey) ?? '';
      _lockId = prefs.getString(_lockIdKey) ?? '';
      _isConfigured = prefs.getBool(_isConfiguredKey) ?? false;

      final accessTokenTimestamp = prefs.getInt(_tokenTimestampKey);
      final refreshTokenTimestamp = prefs.getInt(_refreshTokenTimestampKey);

      _accessToken = prefs.getString(_accessTokenKey) ?? '';
      _refreshToken = prefs.getString(_refreshTokenKey) ?? '';

      final now = DateTime.now();

      // Check if refresh token expired (15 days)
      if (refreshTokenTimestamp != null && _refreshToken.isNotEmpty) {
        final savedTime = DateTime.fromMillisecondsSinceEpoch(
          refreshTokenTimestamp,
        );
        if (now.difference(savedTime).inDays >= 15) {
          debugPrint('🔐 LockAPI: Refresh token expired');
          await clearAllTokens();
          return;
        }
      }

      // Check if access token expired (24 hours)
      if (accessTokenTimestamp != null && _accessToken.isNotEmpty) {
        final savedTime = DateTime.fromMillisecondsSinceEpoch(
          accessTokenTimestamp,
        );
        if (now.difference(savedTime).inHours >= 24) {
          debugPrint('🔐 LockAPI: Access token expired');
          _accessToken = '';
          await prefs.remove(_accessTokenKey);
          await prefs.remove(_tokenTimestampKey);
        }
      }
    } catch (e) {
      debugPrint('❌ LockAPI: Error loading preferences: $e');
    }
  }

  /// Save tokens to SharedPreferences
  Future<void> _saveTokens(String accessToken, String refreshToken) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;

      _accessToken = accessToken;
      _refreshToken = refreshToken;

      await prefs.setString(_accessTokenKey, accessToken);
      await prefs.setString(_refreshTokenKey, refreshToken);
      await prefs.setInt(_tokenTimestampKey, now);
      await prefs.setInt(_refreshTokenTimestampKey, now);

      debugPrint('✅ LockAPI: Tokens saved');
    } catch (e) {
      debugPrint('❌ LockAPI: Error saving tokens: $e');
    }
  }

  /// Save configuration
  Future<void> saveConfiguration(String phoneNumber, String lockId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _phoneNumber = phoneNumber;
      _lockId = lockId;
      _isConfigured = true;

      await prefs.setString(_phoneNumberKey, phoneNumber);
      await prefs.setString(_lockIdKey, lockId);
      await prefs.setBool(_isConfiguredKey, true);

      debugPrint('✅ LockAPI: Configuration saved');
    } catch (e) {
      debugPrint('❌ LockAPI: Error saving configuration: $e');
    }
  }

  /// Clear all tokens
  Future<void> clearAllTokens() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_accessTokenKey);
      await prefs.remove(_refreshTokenKey);
      await prefs.remove(_tokenTimestampKey);
      await prefs.remove(_refreshTokenTimestampKey);

      _accessToken = '';
      _refreshToken = '';

      debugPrint('✅ LockAPI: Tokens cleared');
    } catch (e) {
      debugPrint('❌ LockAPI: Error clearing tokens: $e');
    }
  }

  /// Request OTP for phone number
  Future<(bool, String)> requestOTP(String phoneNumber) async {
    debugPrint('🔐 LockAPI: Requesting OTP for $phoneNumber...');

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/integrators/v1/auth/request-otp'),
        headers: {'Content-Type': 'application/json', 'x-api-key': apiKey},
        body: jsonEncode({'countryCode': '+91', 'phoneNumber': phoneNumber}),
      );

      debugPrint('🔐 LockAPI: OTP request status: ${response.statusCode}');

      if (response.statusCode == 200) {
        _phoneNumber = phoneNumber;
        return (true, 'OTP sent successfully');
      } else {
        return (false, 'Failed to send OTP: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ LockAPI: OTP request error: $e');
      return (false, 'Error: $e');
    }
  }

  /// Verify OTP and get tokens
  Future<(bool, String)> verifyOTP(String otp) async {
    debugPrint('🔐 LockAPI: Verifying OTP...');

    if (_phoneNumber.isEmpty) {
      return (false, 'Phone number not set');
    }

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/integrators/v1/auth/verify-otp'),
        headers: {'Content-Type': 'application/json', 'x-api-key': apiKey},
        body: jsonEncode({
          'countryCode': '+91',
          'phoneNumber': _phoneNumber,
          'otp': otp,
        }),
      );

      debugPrint('🔐 LockAPI: Verify OTP status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final accessToken = data['accessToken'] as String?;
        final refreshToken = data['refreshToken'] as String?;

        if (accessToken != null && refreshToken != null) {
          await _saveTokens(accessToken, refreshToken);
          return (true, 'OTP verified successfully');
        } else {
          return (false, 'Tokens not found in response');
        }
      } else {
        return (false, 'Invalid OTP');
      }
    } catch (e) {
      debugPrint('❌ LockAPI: Verify OTP error: $e');
      return (false, 'Error: $e');
    }
  }

  /// Refresh access token using refresh token
  Future<bool> refreshAccessToken() async {
    if (_refreshToken.isEmpty) {
      debugPrint('🔐 LockAPI: No refresh token available');
      return false;
    }

    debugPrint('🔐 LockAPI: Refreshing access token...');

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/integrators/v1/auth/generate-token'),
        headers: {'Content-Type': 'application/json', 'x-api-key': apiKey},
        body: jsonEncode({'refreshToken': _refreshToken}),
      );

      debugPrint('🔐 LockAPI: Refresh token status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final accessToken = data['accessToken'] as String?;

        if (accessToken != null) {
          _accessToken = accessToken;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_accessTokenKey, accessToken);
          await prefs.setInt(
            _tokenTimestampKey,
            DateTime.now().millisecondsSinceEpoch,
          );
          debugPrint('✅ LockAPI: Access token refreshed');
          return true;
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        debugPrint('🔐 LockAPI: Refresh token invalid, clearing tokens');
        await clearAllTokens();
      }
      return false;
    } catch (e) {
      debugPrint('❌ LockAPI: Refresh token error: $e');
      return false;
    }
  }

  /// Get lock list and store first lock ID
  Future<(bool, String)> fetchLockList() async {
    if (_accessToken.isEmpty) {
      return (false, 'Not authenticated');
    }

    debugPrint('🔐 LockAPI: Fetching lock list...');

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/integrators/v1/lock/list'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_accessToken',
        },
      );

      debugPrint('🔐 LockAPI: Lock list status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final List<dynamic> locks = jsonDecode(response.body);
        if (locks.isNotEmpty) {
          _lockId = locks[0]['lockId'] as String;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_lockIdKey, _lockId);
          debugPrint('✅ LockAPI: Lock ID: $_lockId');
          return (true, 'Lock found: $_lockId');
        } else {
          return (false, 'No locks found');
        }
      } else if (response.statusCode == 401) {
        // Try refresh token
        if (await refreshAccessToken()) {
          return fetchLockList();
        }
        return (false, 'Authentication expired');
      } else {
        return (false, 'Failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ LockAPI: Fetch lock list error: $e');
      return (false, 'Error: $e');
    }
  }

  /// Unlock the door
  Future<(bool, String)> unlockDoor() async {
    if (_accessToken.isEmpty) {
      // Try to refresh
      if (!await refreshAccessToken()) {
        return (false, 'Not authenticated - please configure API');
      }
    }

    if (_lockId.isEmpty) {
      return (false, 'Lock ID not configured');
    }

    debugPrint('🔓 LockAPI: Unlocking door...');
    debugPrint('🔓 LockAPI: Lock ID: $_lockId');
    debugPrint('🔓 LockAPI: Token: ${_accessToken.substring(0, 20)}...');

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/integrators/v1/lock/$_lockId/unlock-request'),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': apiKey,
          'Authorization': 'Bearer $_accessToken',
          'LOCK_ID': _lockId,
        },
        body: jsonEncode({'LOCK_ID': _lockId}),
      );

      debugPrint('🔓 LockAPI: Unlock status: ${response.statusCode}');
      debugPrint('🔓 LockAPI: Response body: ${response.body}');

      if (response.statusCode == 200) {
        debugPrint('✅ LockAPI: Door unlocked!');
        return (true, 'Door unlocked successfully!');
      } else if (response.statusCode == 401) {
        // Try refresh and retry
        debugPrint('🔓 LockAPI: 401 - trying refresh token...');
        if (await refreshAccessToken()) {
          return unlockDoor();
        }
        return (false, 'Authentication expired: ${response.body}');
      } else {
        // Parse error message from response if available
        try {
          final errorData = jsonDecode(response.body);
          final errorMessage =
              errorData['responseCode'] ??
              errorData['message'] ??
              errorData['error'] ??
              response.body;
          debugPrint('❌ LockAPI: Error message: $errorMessage');
          return (false, 'Lock Error: $errorMessage');
        } catch (_) {
          return (
            false,
            'Unlock failed (${response.statusCode}): ${response.body}',
          );
        }
      }
    } catch (e) {
      debugPrint('❌ LockAPI: Unlock error: $e');
      return (false, 'Error: $e');
    }
  }
}
