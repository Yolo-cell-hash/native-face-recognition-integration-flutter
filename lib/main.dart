import 'package:flutter/material.dart';
import 'camera_screen.dart';

void main() {
  debugPrint('🚀 App: Starting Godrej Advantis IoT9 application...');
  debugPrint('🚀 App: Launching directly to verification for instant access');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
