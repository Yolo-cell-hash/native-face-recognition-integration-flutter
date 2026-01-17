import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import 'package:provider/provider.dart';
import 'package:quickalert/quickalert.dart';
import 'package:flutter/material.dart';
import 'package:vdp_poc_new/screens/landing_screen.dart';
import 'package:vdp_poc_new/screens/onboarding_screen.dart';
import 'package:vdp_poc_new/utils/loader_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WebApi {
  static const String apiKey = 'e8q0y264i3nxjw2pn9p2pxtbo0ub4n3b';
  static const String baseUrl = 'https://hmut-api-gdb2c.binary-labs.in';
  dynamic response = '';
  dynamic tokens;

  // Shared Preferences keys
  static const String _accessTokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _tokenTimestampKey = 'token_timestamp';
  static const String _refreshTokenTimestampKey = 'refresh_token_timestamp';

  Future<void> requestOTP(BuildContext context) async {
    final loaderProvider = Provider.of<LoaderProvider>(context, listen: false);
    String phoneNumber = Provider.of<LoaderProvider>(
      context,
      listen: false,
    ).phoneNumber;

    loaderProvider.showLoader();
    Map<String, String> requestBody = {
      'countryCode': '+91', // Dummy country code
      'phoneNumber': phoneNumber,
    };

    String jsonBody = jsonEncode(requestBody);

    print('Clicked');
    try {
      response = await http.post(
        Uri.parse('$baseUrl/integrators/v1/auth/request-otp'),
        headers: {'Content-Type': 'application/json', 'x-api-key': apiKey},
        body: jsonBody,
      );
      print('Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        Provider.of<LoaderProvider>(context, listen: false).otpSent = true;
      }

      print('Response body: ${response.body}');
    } catch (e) {
      print('Error making POST request: $e');
      // Handle error appropriately, e.g., show a message to the user
    } finally {
      // Ensure spinner is always turned off, even if an error occurs
      loaderProvider.hideLoader();
    }
  }

  Future<void> verifyOTP(BuildContext context, dynamic otp) async {
    final loaderProvider = Provider.of<LoaderProvider>(context, listen: false);
    String phoneNumber = Provider.of<LoaderProvider>(
      context,
      listen: false,
    ).phoneNumber;
    loaderProvider.showLoader();
    Map<String, dynamic> requestBody = {
      'countryCode': '+91',
      'phoneNumber': phoneNumber,
      'otp': otp,
    };

    String jsonBody = jsonEncode(requestBody);

    try {
      response = await http.post(
        Uri.parse('$baseUrl/integrators/v1/auth/verify-otp'),
        headers: {'Content-Type': 'application/json', 'x-api-key': apiKey},
        body: jsonBody,
      );

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      loaderProvider.hideLoader();
      if (response.statusCode == 200) {
        Map<String, dynamic> responseData = jsonDecode(response.body);
        String? extractedAccessToken = responseData['accessToken'];
        String? extractedRefreshToken = responseData['refreshToken'];

        if (extractedAccessToken != null && extractedRefreshToken != null) {
          // Store in provider
          Provider.of<LoaderProvider>(context, listen: false).accessToken =
              extractedAccessToken;

          Provider.of<LoaderProvider>(context, listen: false).refreshToken =
              extractedRefreshToken;

          // Store tokens in shared preferences with timestamp
          await _saveTokensToPreferences(
            extractedAccessToken,
            extractedRefreshToken,
          );

          try {
            FirebaseDatabase database = FirebaseDatabase.instanceFor(
              app: Firebase.app(),
              databaseURL:
                  'https://vdb-poc-default-rtdb.asia-southeast1.firebasedatabase.app/',
            );
            DatabaseReference tokenRef = database.ref("dev_env/accessToken");

            await tokenRef.set(extractedAccessToken);

            DatabaseReference refreshToken = database.ref(
              "dev_env/refresh_token",
            );

            await refreshToken.set(extractedRefreshToken);

            print(
              'Access Token successfully stored in Firebase at /updates/accessToken',
            );
          } catch (e) {
            print('Error storing access token in Firebase: $e');
          }
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const LandingScreen()),
          );

          Provider.of<LoaderProvider>(context, listen: false).otpSent = false;
        } else {
          QuickAlert.show(
            context: context,
            type: QuickAlertType.error,
            title: 'Error',
            text: "Access token not found in response.",
            confirmBtnColor: Colors.red,
          );
        }
      } else {
        QuickAlert.show(
          context: context,
          type: QuickAlertType.error,
          title: 'Error',
          text: "Invalid OTP",
          confirmBtnColor: Colors.red,
        );
      }
    } catch (e) {
      print('Error making POST request: $e');
      loaderProvider.hideLoader();
      QuickAlert.show(
        context: context,
        type: QuickAlertType.error,
        title: 'Error',
        text: e.toString(),
      );
    }
  }

  // Save tokens to shared preferences with current timestamp
  Future<void> _saveTokensToPreferences(
    String accessToken,
    String refreshToken,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentTime = DateTime.now().millisecondsSinceEpoch;

      await prefs.setString(_accessTokenKey, accessToken);
      await prefs.setString(_refreshTokenKey, refreshToken);
      await prefs.setInt(_tokenTimestampKey, currentTime);
      await prefs.setInt(_refreshTokenTimestampKey, currentTime);

      print('Tokens saved to shared preferences successfully');
      print('Access Token Timestamp: $currentTime');
      print('Refresh Token Timestamp: $currentTime');
    } catch (e) {
      print('Error saving tokens to shared preferences: $e');
    }
  }

  // Load tokens from shared preferences and check expiration
  static Future<Map<String, dynamic>> loadTokensFromPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessTokenTimestamp = prefs.getInt(_tokenTimestampKey);
      final refreshTokenTimestamp = prefs.getInt(_refreshTokenTimestampKey);
      String? accessToken = prefs.getString(_accessTokenKey);
      String? refreshToken = prefs.getString(_refreshTokenKey);

      final currentTime = DateTime.now();
      bool refreshTokenExpired = false;
      bool accessTokenExpired = false;

      // Check if refresh token has expired (15 days)
      if (refreshTokenTimestamp != null && refreshToken != null) {
        final savedTime = DateTime.fromMillisecondsSinceEpoch(
          refreshTokenTimestamp,
        );
        final difference = currentTime.difference(savedTime);

        if (difference.inDays >= 15) {
          // Refresh token expired - clear everything
          print('Refresh token expired after 15 days - logging out user');
          await clearAllTokens();
          refreshTokenExpired = true;
          refreshToken = null;
          accessToken = null;
        }
      }

      // Check if access token has expired (1 day) - only if refresh token is valid
      if (!refreshTokenExpired &&
          accessTokenTimestamp != null &&
          accessToken != null) {
        final savedTime = DateTime.fromMillisecondsSinceEpoch(
          accessTokenTimestamp,
        );
        final difference = currentTime.difference(savedTime);

        if (difference.inHours >= 24) {
          // Clear access token after 1 day
          await prefs.remove(_accessTokenKey);
          await prefs.remove(_tokenTimestampKey);
          accessToken = null;
          accessTokenExpired = true;
          print('Access token cleared after 24 hours');
        }
      }

      return {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'refreshTokenExpired': refreshTokenExpired,
        'accessTokenExpired': accessTokenExpired,
      };
    } catch (e) {
      print('Error loading tokens from shared preferences: $e');
      return {
        'accessToken': null,
        'refreshToken': null,
        'refreshTokenExpired': false,
        'accessTokenExpired': false,
      };
    }
  }

  // Clear all tokens from shared preferences and Firebase
  static Future<void> clearAllTokens() async {
    try {
      // Clear from shared preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_accessTokenKey);
      await prefs.remove(_refreshTokenKey);
      await prefs.remove(_tokenTimestampKey);
      await prefs.remove(_refreshTokenTimestampKey);

      print('All tokens cleared from shared preferences');

      // Clear from Firebase
      try {
        FirebaseDatabase database = FirebaseDatabase.instanceFor(
          app: Firebase.app(),
          databaseURL:
              'https://vdb-poc-default-rtdb.asia-southeast1.firebasedatabase.app/',
        );

        DatabaseReference accessTokenRef = database.ref("dev_env/accessToken");
        await accessTokenRef.remove();

        DatabaseReference refreshTokenRef = database.ref(
          "dev_env/refresh_token",
        );
        await refreshTokenRef.remove();

        print('Tokens cleared from Firebase');
      } catch (e) {
        print('Error clearing tokens from Firebase: $e');
      }
    } catch (e) {
      print('Error clearing tokens: $e');
    }
  }

  // Clear only tokens from shared preferences (for manual logout)
  static Future<void> clearTokensFromPreferences() async {
    await clearAllTokens();
  }

  // Logout user and navigate to onboarding
  static Future<void> logoutUser(BuildContext context) async {
    final loaderProvider = Provider.of<LoaderProvider>(context, listen: false);

    // Clear tokens from provider
    loaderProvider.accessToken = '';
    loaderProvider.refreshToken = '';
    loaderProvider.phoneNumber = '';
    loaderProvider.lockID = '';

    // Clear all tokens from storage and Firebase
    await clearAllTokens();

    // Navigate to onboarding screen and clear navigation stack
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => OnboardingScreen()),
        (Route<dynamic> route) => false,
      );

      QuickAlert.show(
        context: context,
        type: QuickAlertType.info,
        title: 'Session Expired',
        text: "Your session has expired. Please login again.",
        confirmBtnColor: Colors.blue,
      );
    }
  }

  Future<void> getLockList(BuildContext context) async {
    {
      String accessToken = Provider.of<LoaderProvider>(
        context,
        listen: false,
      ).accessToken;

      try {
        response = await http.get(
          Uri.parse('$baseUrl/integrators/v1/lock/list'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $accessToken',
          },
        );

        if (response.statusCode == 200) {
          List<dynamic> responseData = jsonDecode(response.body);
          Map<String, dynamic> lockId = responseData[0];
          String? _lockId = lockId['lockId'];
          print(
            'Lock ID is ------------------- $_lockId --------------------------',
          );

          Provider.of<LoaderProvider>(context, listen: false).lockID = _lockId!;
        } else if (response.statusCode == 401) {
          // Unauthorized - token might be expired
          print('Access token expired or invalid');
          await logoutUser(context);
        }

        print('Response status: ${response.statusCode}');
        print('Response body: ${response.body}');
      } catch (e) {
        print('Error making GET request: $e');
      }
    }
  }

  Future<int> unlockDoor(BuildContext context) async {
    final loaderProvider = Provider.of<LoaderProvider>(context, listen: false);
    loaderProvider.showLoader();
    String lockID = Provider.of<LoaderProvider>(context, listen: false).lockID;
    String tokens = Provider.of<LoaderProvider>(
      context,
      listen: false,
    ).accessToken;

    print(lockID);
    Map<String, dynamic> requestBody = {'LOCK_ID': lockID.toString()};

    String jsonBody = jsonEncode(requestBody);

    try {
      response = await http.post(
        Uri.parse('$baseUrl/integrators/v1/lock/${lockID}/unlock-request'),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': apiKey,
          'Authorization': 'Bearer $tokens',
          'LOCK_ID': lockID,
        },
        body: jsonBody,
      );

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        print('Lock Unlocked Successfully !!!');
        loaderProvider.hideLoader();
        return 200;
      } else if (response.statusCode == 401) {
        // Unauthorized - token expired
        loaderProvider.hideLoader();
        await logoutUser(context);
        return 401;
      } else {
        loaderProvider.hideLoader();
        QuickAlert.show(
          context: context,
          type: QuickAlertType.error,
          title: 'Error',
          text: "Failed to open the door",
          confirmBtnColor: Colors.red,
        );
        return response.statusCode;
      }
    } catch (e) {
      print('Error making POST request: $e');
      loaderProvider.hideLoader();
      QuickAlert.show(
        context: context,
        type: QuickAlertType.error,
        title: 'Error',
        text: e.toString(),
        confirmBtnColor: Colors.red,
      );
      return 500;
    }
  }

  Future<void> sendNotification(BuildContext context) async {
    String lockID = Provider.of<LoaderProvider>(context, listen: false).lockID;
    String tokens = Provider.of<LoaderProvider>(
      context,
      listen: false,
    ).accessToken;

    Map<String, dynamic> requestBody = {'LOCK_ID': lockID.toString()};

    String jsonBody = jsonEncode(requestBody);

    try {
      response = await http.post(
        Uri.parse(
          '$baseUrl/integrators/v1/lock/${lockID}/emergency-alert?type=DOORBELL',
        ),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': apiKey,
          'Authorization': 'Bearer $tokens',
          'LOCK_ID': lockID,
        },
        body: jsonBody,
      );

      if (response.statusCode == 200) {
        print('Notification Sent Successfully !!!');
      } else if (response.statusCode == 401) {
        // Unauthorized - token expired
        await logoutUser(context);
      } else {
        print('Notification Could not be sent!!!');
      }
    } catch (e) {
      print('Internal Error Occured - $e');
    }
  }

  Future<void> useRefreshTokenToGetAccessToken(BuildContext context) async {
    String refreshToken = Provider.of<LoaderProvider>(
      context,
      listen: false,
    ).refreshToken;

    if (refreshToken.isEmpty) {
      print('No refresh token available');
      await logoutUser(context);
      return;
    }

    Map<String, dynamic> requestBody = {'refreshToken': refreshToken};
    String jsonBody = jsonEncode(requestBody);

    try {
      response = await http.post(
        Uri.parse('$baseUrl/integrators/v1/auth/generate-token'),
        headers: {'Content-Type': 'application/json', 'x-api-key': apiKey},
        body: jsonBody,
      );

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        Map<String, dynamic> responseData = jsonDecode(response.body);
        String? extractedAccessToken = responseData['accessToken'];

        if (extractedAccessToken != null) {
          Provider.of<LoaderProvider>(context, listen: false).accessToken =
              extractedAccessToken;

          // Update access token in shared preferences with new timestamp
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_accessTokenKey, extractedAccessToken);
          await prefs.setInt(
            _tokenTimestampKey,
            DateTime.now().millisecondsSinceEpoch,
          );

          try {
            FirebaseDatabase database = FirebaseDatabase.instanceFor(
              app: Firebase.app(),
              databaseURL:
                  'https://vdb-poc-default-rtdb.asia-southeast1.firebasedatabase.app/',
            );
            DatabaseReference tokenRef = database.ref("dev_env/accessToken");

            await tokenRef.set(extractedAccessToken);

            print('Access Token successfully refreshed and stored');
          } catch (e) {
            print('Error storing access token in Firebase: $e');
          }
          Provider.of<LoaderProvider>(context, listen: false).otpSent = false;
        } else {
          print('Access Token is empty');
          await logoutUser(context);
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        // Refresh token is invalid or expired
        print('Refresh token is invalid or expired - logging out');
        await logoutUser(context);
      } else {
        print('Failed to get new access token - ${response.statusCode}');
        await logoutUser(context);
      }
    } catch (e) {
      print('Error making POST request: $e');
      await logoutUser(context);
    }
  }
}
