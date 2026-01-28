import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'camera_screen.dart';
import 'services/widget_service.dart';
import 'services/app_settings_service.dart';

void main() async {
  debugPrint('🚀 App: Starting Godrej Advantis IoT9 application...');

  // Ensure Flutter binding is initialized
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('🚀 App: Flutter binding initialized');

  // Initialize app settings (threshold, demo mode)
  await AppSettingsService().initialize();
  debugPrint('🚀 App: App settings initialized');

  // Initialize widget service
  await WidgetService.initialize();
  debugPrint('🚀 App: Widget service initialized');

  // Check if launched from widget
  final launchedFromWidget = await WidgetService.wasLaunchedFromWidget();
  if (launchedFromWidget) {
    debugPrint('🚀 App: App was launched from home widget');
  }

  debugPrint('🚀 App: Launching directly to verification for instant access');
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late AppLinks _appLinks;

  @override
  void initState() {
    super.initState();
    debugPrint('🚀 App: Initializing MyApp state');

    // Add lifecycle observer
    WidgetsBinding.instance.addObserver(this);
    debugPrint('🚀 App: Lifecycle observer added');

    // Initialize deep link handling
    _initDeepLinks();
  }

  @override
  void dispose() {
    debugPrint('🚀 App: Disposing MyApp state');
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('🚀 App: Lifecycle state changed to: $state');

    switch (state) {
      case AppLifecycleState.resumed:
        debugPrint('🚀 App: App resumed - updating widget to ready state');
        WidgetService.updateWidgetReady();
        break;
      case AppLifecycleState.paused:
        debugPrint('🚀 App: App paused');
        break;
      case AppLifecycleState.inactive:
        debugPrint('🚀 App: App inactive');
        break;
      case AppLifecycleState.detached:
        debugPrint('🚀 App: App detached');
        break;
      case AppLifecycleState.hidden:
        debugPrint('🚀 App: App hidden');
        break;
    }
  }

  /// Initialize deep link handling for widget clicks
  void _initDeepLinks() async {
    debugPrint('🔗 DeepLink: Initializing deep link handling...');

    try {
      _appLinks = AppLinks();

      // Handle initial link if app was opened from widget
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        debugPrint('🔗 DeepLink: App opened with initial URI: $initialUri');
        _handleDeepLink(initialUri);
      } else {
        debugPrint('🔗 DeepLink: No initial URI detected');
      }

      // Listen for incoming links while app is running
      _appLinks.uriLinkStream.listen(
        (uri) {
          debugPrint('🔗 DeepLink: Received deep link URI: $uri');
          _handleDeepLink(uri);
        },
        onError: (error) {
          debugPrint('❌ DeepLink: Error handling deep link: $error');
        },
      );

      debugPrint('✅ DeepLink: Deep link handling initialized successfully');
    } catch (e) {
      debugPrint('❌ DeepLink: Failed to initialize deep links: $e');
    }
  }

  /// Handle deep link URIs from widget clicks
  void _handleDeepLink(Uri uri) {
    debugPrint('🔗 DeepLink: Processing deep link: $uri');
    debugPrint(
      '🔗 DeepLink: Scheme: ${uri.scheme}, Host: ${uri.host}, Path: ${uri.path}',
    );

    // Widget click will use edgebasedai://verify
    if (uri.scheme == 'edgebasedai' && uri.host == 'verify') {
      debugPrint('🔗 DeepLink: Widget verify action detected');
      debugPrint(
        '🔗 DeepLink: Camera screen should already be showing as home screen',
      );
      // The app already opens to CameraScreen, so no navigation needed
      // Just update widget status
      WidgetService.updateWidgetReady();
    } else {
      debugPrint('🔗 DeepLink: Unknown deep link format');
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('🚀 App: Building MyApp widget');
    return MaterialApp(
      title: 'Godrej Advantis IoT9',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const CameraScreen(mode: CameraMode.verify),
    );
  }
}
