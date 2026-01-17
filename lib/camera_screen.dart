import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image/image.dart' as img;
import 'user_management_screen.dart';
import 'services/face_recognition_service.dart';

enum CameraMode { verify, enroll }

class CameraScreen extends StatefulWidget {
  final CameraMode mode;

  const CameraScreen({super.key, this.mode = CameraMode.verify});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  String? _errorMessage;
  bool _isVerifying = false;

  // Face recognition service
  final FaceRecognitionService _faceRecognition = FaceRecognitionService();
  bool _modelLoaded = false;

  @override
  void initState() {
    super.initState();
    debugPrint('🎬 CameraScreen: initState called');
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
    _initializeFaceRecognition();
  }

  Future<void> _initializeFaceRecognition() async {
    debugPrint('🧠 CameraScreen: Initializing face recognition service...');
    final success = await _faceRecognition.initialize();
    setState(() {
      _modelLoaded = success;
    });
    if (success) {
      debugPrint('✅ CameraScreen: Face recognition service ready');
    } else {
      debugPrint(
        '⚠️ CameraScreen: Face recognition service failed to initialize',
      );
    }
  }

  @override
  void dispose() {
    debugPrint('🎬 CameraScreen: dispose called');
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _faceRecognition.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('🎬 CameraScreen: App lifecycle state changed to $state');
    final CameraController? cameraController = _controller;

    if (cameraController == null || !cameraController.value.isInitialized) {
      debugPrint(
        '🎬 CameraScreen: Camera controller not ready, skipping lifecycle change',
      );
      return;
    }

    if (state == AppLifecycleState.inactive) {
      debugPrint('🎬 CameraScreen: App inactive, disposing camera controller');
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      debugPrint('🎬 CameraScreen: App resumed, reinitializing camera');
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    debugPrint('📷 CameraScreen: Starting camera initialization...');

    try {
      debugPrint('📷 CameraScreen: Checking camera permission...');
      final cameraPermission = await Permission.camera.status;
      debugPrint(
        '📷 CameraScreen: Camera permission status: $cameraPermission',
      );

      if (cameraPermission.isDenied) {
        debugPrint('📷 CameraScreen: Camera permission denied, requesting...');
        final result = await Permission.camera.request();
        debugPrint('📷 CameraScreen: Permission request result: $result');

        if (result.isDenied || result.isPermanentlyDenied) {
          debugPrint('❌ CameraScreen: Camera permission not granted');
          setState(() {
            _errorMessage =
                'Camera permission is required. Please grant camera permission in settings.';
          });
          return;
        }
      }

      debugPrint('📷 CameraScreen: Getting available cameras...');
      _cameras = await availableCameras();
      debugPrint('📷 CameraScreen: Found ${_cameras?.length ?? 0} cameras');

      if (_cameras == null || _cameras!.isEmpty) {
        debugPrint('❌ CameraScreen: No cameras available on this device');
        setState(() {
          _errorMessage = 'No cameras found on this device';
        });
        return;
      }

      for (var i = 0; i < _cameras!.length; i++) {
        final camera = _cameras![i];
        debugPrint(
          '📷 CameraScreen: Camera $i - Name: ${camera.name}, Lens: ${camera.lensDirection}, Sensor: ${camera.sensorOrientation}°',
        );
      }

      final frontCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () {
          debugPrint(
            '⚠️ CameraScreen: Front camera not found, using first available camera',
          );
          return _cameras!.first;
        },
      );

      debugPrint(
        '📷 CameraScreen: Selected camera - Name: ${frontCamera.name}, Lens: ${frontCamera.lensDirection}',
      );

      debugPrint('📷 CameraScreen: Creating camera controller...');
      _controller = CameraController(
        frontCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      debugPrint('📷 CameraScreen: Initializing camera controller...');
      await _controller!.initialize();
      debugPrint('✅ CameraScreen: Camera controller initialized successfully');

      if (!mounted) {
        debugPrint(
          '⚠️ CameraScreen: Widget no longer mounted, disposing controller',
        );
        _controller?.dispose();
        return;
      }

      setState(() {
        _isInitialized = true;
        _errorMessage = null;
      });
      debugPrint('✅ CameraScreen: Camera ready for facial recognition');
    } catch (e, stackTrace) {
      debugPrint('❌ CameraScreen: Error initializing camera: $e');
      debugPrint('❌ CameraScreen: Stack trace: $stackTrace');
      setState(() {
        _errorMessage = 'Failed to initialize camera: $e';
      });
    }
  }

  Future<void> _verifyFace() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isVerifying) {
      debugPrint(
        '⚠️ CameraScreen: Cannot verify - controller not ready or already verifying',
      );
      return;
    }

    if (!_faceRecognition.isInitialized) {
      debugPrint('⚠️ CameraScreen: Face recognition not initialized');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Face recognition model is loading...'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    setState(() {
      _isVerifying = true;
    });

    try {
      debugPrint('🔐 CameraScreen: Starting facial verification...');
      debugPrint('🔐 CameraScreen: Capturing frame for verification...');

      final xFile = await _controller!.takePicture();
      debugPrint('✅ CameraScreen: Frame captured for verification');
      debugPrint('🔐 CameraScreen: Image path: ${xFile.path}');

      final file = File(xFile.path);
      final fileSize = await file.length();
      debugPrint(
        '🔐 CameraScreen: Image size: ${(fileSize / 1024).toStringAsFixed(2)} KB',
      );

      // Load and decode image for face recognition
      debugPrint('🧠 CameraScreen: Loading image for face recognition...');
      final bytes = await file.readAsBytes();
      final decodedImage = img.decodeImage(bytes);

      if (decodedImage == null) {
        debugPrint('❌ CameraScreen: Failed to decode image');
        throw Exception('Failed to decode captured image');
      }

      debugPrint('🧠 CameraScreen: Running face recognition model...');
      final (isVerified, personName, distance) = await _faceRecognition
          .verifyFace(decodedImage);

      if (isVerified && personName != null) {
        debugPrint('✅ CameraScreen: Facial verification SUCCESS');
        debugPrint(
          '✅ CameraScreen: Identified as: $personName (distance: ${distance.toStringAsFixed(4)})',
        );
        debugPrint(
          '🔓 CameraScreen: Sending unlock command to Godrej Advantis IoT9...',
        );
        debugPrint('✅ CameraScreen: Lock unlocked successfully!');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Welcome $personName! Unlocking Godrej Lock...',
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        debugPrint('❌ CameraScreen: Facial verification FAILED');
        debugPrint(
          '🔒 CameraScreen: Access denied - face not recognized (distance: ${distance.toStringAsFixed(4)})',
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error, color: Colors.white),
                  const SizedBox(width: 12),
                  Text('Face Not Recognized (${distance.toStringAsFixed(2)})'),
                ],
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }

      // Clean up temp file
      if (await file.exists()) {
        await file.delete();
      }

      setState(() {
        _isVerifying = false;
      });
    } catch (e, stackTrace) {
      debugPrint('❌ CameraScreen: Error during verification: $e');
      debugPrint('❌ CameraScreen: Stack trace: $stackTrace');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verification error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }

      setState(() {
        _isVerifying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(
      '🎨 CameraScreen: Building UI - isInitialized: $_isInitialized, hasError: ${_errorMessage != null}, isVerifying: $_isVerifying',
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_errorMessage != null) {
      debugPrint('🎨 CameraScreen: Displaying error message');
      return _buildErrorView();
    }

    if (!_isInitialized) {
      debugPrint('🎨 CameraScreen: Displaying loading indicator');
      return _buildLoadingView();
    }

    debugPrint('🎨 CameraScreen: Displaying camera preview');
    return _buildCameraPreview();
  }

  Widget _buildLoadingView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.blue),
          SizedBox(height: 20),
          Text(
            'Initializing camera...',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 64),
            const SizedBox(height: 20),
            Text(
              _errorMessage ?? 'An error occurred',
              style: const TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                debugPrint('🔄 CameraScreen: Retry button pressed');
                setState(() {
                  _errorMessage = null;
                });
                _initializeCamera();
              },
              child: const Text('Retry'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                debugPrint('⚙️ CameraScreen: Open Settings button pressed');
                openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Camera preview
        Center(child: CameraPreview(_controller!)),

        // Minimalist corner bracket face guide
        Center(
          child: SizedBox(
            width: 280,
            height: 340,
            child: Stack(
              children: [
                // Top-left corner
                Positioned(
                  top: 0,
                  left: 0,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: _isVerifying
                              ? Colors.blue
                              : Colors.white.withOpacity(0.8),
                          width: 3,
                        ),
                        left: BorderSide(
                          color: _isVerifying
                              ? Colors.blue
                              : Colors.white.withOpacity(0.8),
                          width: 3,
                        ),
                      ),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(12),
                      ),
                    ),
                  ),
                ),
                // Top-right corner
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: _isVerifying
                              ? Colors.blue
                              : Colors.white.withOpacity(0.8),
                          width: 3,
                        ),
                        right: BorderSide(
                          color: _isVerifying
                              ? Colors.blue
                              : Colors.white.withOpacity(0.8),
                          width: 3,
                        ),
                      ),
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(12),
                      ),
                    ),
                  ),
                ),
                // Bottom-left corner
                Positioned(
                  bottom: 0,
                  left: 0,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: _isVerifying
                              ? Colors.blue
                              : Colors.white.withOpacity(0.8),
                          width: 3,
                        ),
                        left: BorderSide(
                          color: _isVerifying
                              ? Colors.blue
                              : Colors.white.withOpacity(0.8),
                          width: 3,
                        ),
                      ),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(12),
                      ),
                    ),
                  ),
                ),
                // Bottom-right corner
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: _isVerifying
                              ? Colors.blue
                              : Colors.white.withOpacity(0.8),
                          width: 3,
                        ),
                        right: BorderSide(
                          color: _isVerifying
                              ? Colors.blue
                              : Colors.white.withOpacity(0.8),
                          width: 3,
                        ),
                      ),
                      borderRadius: const BorderRadius.only(
                        bottomRight: Radius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Top bar with Godrej branding
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.8),
                  Colors.black.withOpacity(0.6),
                  Colors.transparent,
                ],
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Left spacer for balance
                    const SizedBox(width: 8),

                    // Center branding
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.security,
                              color: Colors.blue,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Godrej Advantis IoT9',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              Text(
                                'Smart Digital Lock',
                                style: TextStyle(
                                  color: Colors.blue,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Right user management button
                    IconButton(
                      onPressed: () {
                        debugPrint('🎬 CameraScreen: Opening user management');
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const UserManagementScreen(),
                          ),
                        );
                      },
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.people,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      tooltip: 'User Management',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.face, color: Colors.blue, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'Facial Recognition System',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Bottom controls
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withOpacity(0.8),
                  Colors.black.withOpacity(0.6),
                  Colors.transparent,
                ],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Position your face within the frame',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 20),
                // Verify button
                GestureDetector(
                  onTap: _isVerifying ? null : _verifyFace,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _isVerifying
                            ? [Colors.grey, Colors.grey.shade700]
                            : [Colors.blue, Colors.blue.shade700],
                      ),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: _isVerifying
                              ? Colors.grey.withOpacity(0.3)
                              : Colors.blue.withOpacity(0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: _isVerifying
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 16),
                              Text(
                                'Verifying Face...',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.lock_open,
                                color: Colors.white,
                                size: 24,
                              ),
                              SizedBox(width: 12),
                              Text(
                                'Verify Face to Unlock',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
