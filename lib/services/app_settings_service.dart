import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Singleton service for app-wide settings (anti-spoof threshold, demo mode)
/// Accessed via double-tap on Godrej branding → API config panel
class AppSettingsService {
  static final AppSettingsService _instance = AppSettingsService._internal();
  factory AppSettingsService() => _instance;
  AppSettingsService._internal();

  static const String _keyThreshold = 'spoof_threshold';
  static const String _keyRecogThreshold = 'recognition_threshold';
  static const String _keyDemoMode = 'demo_mode';
  static const double _defaultThreshold = 0.088;
  static const double _defaultRecogThreshold = 1.9;

  SharedPreferences? _prefs;
  double _spoofThreshold = _defaultThreshold;
  double _recogThreshold = _defaultRecogThreshold;
  bool _demoMode = false;

  /// Initialize the service (call once at app start)
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    _spoofThreshold = _prefs?.getDouble(_keyThreshold) ?? _defaultThreshold;
    _recogThreshold =
        _prefs?.getDouble(_keyRecogThreshold) ?? _defaultRecogThreshold;
    _demoMode = _prefs?.getBool(_keyDemoMode) ?? false;
    debugPrint(
      '⚙️ AppSettings: Loaded - spoofT: $_spoofThreshold, recogT: $_recogThreshold, demoMode: $_demoMode',
    );
  }

  /// Anti-spoof threshold (0.001 to 0.500)
  double get spoofThreshold => _spoofThreshold;

  set spoofThreshold(double value) {
    _spoofThreshold = value.clamp(0.001, 0.500);
    _prefs?.setDouble(_keyThreshold, _spoofThreshold);
    debugPrint('⚙️ AppSettings: Threshold set to $_spoofThreshold');
  }

  /// Face recognition threshold (0.5 to 3.0)
  double get recogThreshold => _recogThreshold;

  set recogThreshold(double value) {
    _recogThreshold = value.clamp(0.5, 3.0);
    _prefs?.setDouble(_keyRecogThreshold, _recogThreshold);
    debugPrint('⚙️ AppSettings: Recognition threshold set to $_recogThreshold');
  }

  /// Demo mode - when true, only shows "ACCESS GRANTED" or "ACCESS DENIED"
  bool get demoMode => _demoMode;

  set demoMode(bool value) {
    _demoMode = value;
    _prefs?.setBool(_keyDemoMode, _demoMode);
    debugPrint(
      '⚙️ AppSettings: Demo mode ${_demoMode ? "ENABLED" : "DISABLED"}',
    );
  }

  /// Reset to defaults
  void resetToDefaults() {
    spoofThreshold = _defaultThreshold;
    recogThreshold = _defaultRecogThreshold;
    demoMode = false;
    debugPrint('⚙️ AppSettings: Reset to defaults');
  }
}
