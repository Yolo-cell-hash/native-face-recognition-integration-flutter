import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

/// Service to manage home widget updates and interactions
/// Handles widget data synchronization and click callbacks
class WidgetService {
  static const String _widgetGroupId = 'group.com.gnb.edge_based_ai';
  static const String _lastVerificationKey = 'last_verification_time';
  static const String _verificationStatusKey = 'verification_status';
  static const String _userNameKey = 'widget_user_name';

  /// Initialize the widget service
  /// Must be called during app startup
  static Future<void> initialize() async {
    debugPrint('🔷 WidgetService: Initializing home widget service...');

    try {
      // Set the app group ID for iOS (not used on Android but harmless)
      await HomeWidget.setAppGroupId(_widgetGroupId);
      debugPrint('🔷 WidgetService: App group ID set to $_widgetGroupId');

      // Register callback for widget interactions
      HomeWidget.widgetClicked.listen(_handleWidgetClick);
      debugPrint('🔷 WidgetService: Widget click listener registered');

      // Initialize with default data
      await _initializeWidgetData();
      debugPrint('✅ WidgetService: Widget service initialized successfully');
    } catch (e) {
      debugPrint('❌ WidgetService: Failed to initialize widget service: $e');
    }
  }

  /// Initialize widget with default values
  static Future<void> _initializeWidgetData() async {
    debugPrint('🔷 WidgetService: Initializing widget data...');

    try {
      await HomeWidget.saveWidgetData<String>(
        _verificationStatusKey,
        'Tap to verify',
      );
      await HomeWidget.saveWidgetData<String>(_lastVerificationKey, 'Never');
      await HomeWidget.updateWidget(
        name: 'HomeWidgetProvider',
        androidName: 'HomeWidgetProvider',
      );
      debugPrint('✅ WidgetService: Widget data initialized');
    } catch (e) {
      debugPrint('❌ WidgetService: Failed to initialize widget data: $e');
    }
  }

  /// Handle widget click events
  static void _handleWidgetClick(Uri? uri) {
    debugPrint('🔷 WidgetService: Widget clicked!');
    if (uri != null) {
      debugPrint('🔷 WidgetService: Click URI: $uri');
      // The deep link will be handled by the app_links listener in main.dart
    } else {
      debugPrint('🔷 WidgetService: Click URI is null, using default behavior');
    }
  }

  /// Update widget with verification success
  static Future<void> updateVerificationSuccess(String userName) async {
    debugPrint(
      '🔷 WidgetService: Updating widget with successful verification for $userName',
    );

    try {
      final now = DateTime.now();
      final timeString = _formatTime(now);

      await HomeWidget.saveWidgetData<String>(
        _verificationStatusKey,
        'Verified ✓',
      );
      await HomeWidget.saveWidgetData<String>(
        _lastVerificationKey,
        'Last: $timeString',
      );
      await HomeWidget.saveWidgetData<String>(_userNameKey, userName);

      // Update the widget UI
      final updateResult = await HomeWidget.updateWidget(
        name: 'HomeWidgetProvider',
        androidName: 'HomeWidgetProvider',
      );

      debugPrint(
        '✅ WidgetService: Widget updated successfully (result: $updateResult)',
      );
      debugPrint(
        '🔷 WidgetService: Status: Verified ✓, User: $userName, Time: $timeString',
      );
    } catch (e) {
      debugPrint('❌ WidgetService: Failed to update widget: $e');
    }
  }

  /// Update widget with verification failure
  static Future<void> updateVerificationFailed() async {
    debugPrint('🔷 WidgetService: Updating widget with failed verification');

    try {
      final now = DateTime.now();
      final timeString = _formatTime(now);

      await HomeWidget.saveWidgetData<String>(
        _verificationStatusKey,
        'Failed ✗',
      );
      await HomeWidget.saveWidgetData<String>(
        _lastVerificationKey,
        'Last attempt: $timeString',
      );

      // Update the widget UI
      final updateResult = await HomeWidget.updateWidget(
        name: 'HomeWidgetProvider',
        androidName: 'HomeWidgetProvider',
      );

      debugPrint(
        '✅ WidgetService: Widget updated with failure (result: $updateResult)',
      );
    } catch (e) {
      debugPrint('❌ WidgetService: Failed to update widget: $e');
    }
  }

  /// Update widget to ready state (after app opens)
  static Future<void> updateWidgetReady() async {
    debugPrint('🔷 WidgetService: Updating widget to ready state');

    try {
      await HomeWidget.saveWidgetData<String>(_verificationStatusKey, 'Ready');

      // Update the widget UI
      final updateResult = await HomeWidget.updateWidget(
        name: 'HomeWidgetProvider',
        androidName: 'HomeWidgetProvider',
      );

      debugPrint(
        '✅ WidgetService: Widget updated to ready state (result: $updateResult)',
      );
    } catch (e) {
      debugPrint('❌ WidgetService: Failed to update widget: $e');
    }
  }

  /// Format time for display
  static String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// Get widget launch URI for deep linking
  static Uri getWidgetLaunchUri() {
    return Uri.parse('edgebasedai://verify');
  }

  /// Check if app was launched from widget
  static Future<bool> wasLaunchedFromWidget() async {
    try {
      final uri = await HomeWidget.initiallyLaunchedFromHomeWidget();
      final launched = uri != null;
      debugPrint('🔷 WidgetService: App launched from widget: $launched');
      if (launched) {
        debugPrint('🔷 WidgetService: Launch URI: $uri');
      }
      return launched;
    } catch (e) {
      debugPrint('❌ WidgetService: Error checking widget launch: $e');
      return false;
    }
  }
}
