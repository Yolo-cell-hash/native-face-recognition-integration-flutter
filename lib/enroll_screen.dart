import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image/image.dart' as img;
import 'models/user_model.dart';
import 'services/user_storage_service.dart';
import 'services/face_recognition_service.dart';

class EnrollScreen extends StatefulWidget {
  const EnrollScreen({super.key});

  @override
  State<EnrollScreen> createState() => _EnrollScreenState();
}

class _EnrollScreenState extends State<EnrollScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  String? _errorMessage;
  bool _isCapturing = false;
  bool _isEnrolling = false;
  XFile? _capturedImage;
  final TextEditingController _nameController = TextEditingController();
  final UserStorageService _storage = UserStorageService();

  // Face recognition service
  final FaceRecognitionService _faceRecognition = FaceRecognitionService();
  bool _modelLoaded = false;

  @override
  void initState() {
    super.initState();
    debugPrint('📝 EnrollScreen: initState called');
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
    _initializeFaceRecognition();
  }

  Future<void> _initializeFaceRecognition() async {
    debugPrint('🧠 EnrollScreen: Initializing face recognition service...');
    final success = await _faceRecognition.initialize();
    setState(() {
      _modelLoaded = success;
    });
    if (success) {
      debugPrint('✅ EnrollScreen: Face recognition service ready');
    } else {
      debugPrint(
        '⚠️ EnrollScreen: Face recognition service failed to initialize',
      );
    }
  }

  @override
  void dispose() {
    debugPrint('📝 EnrollScreen: dispose called');
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _nameController.dispose();
    _faceRecognition.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _controller;
    if (cameraController == null || !cameraController.value.isInitialized)
      return;

    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    debugPrint('📝 EnrollScreen: Starting camera initialization...');

    try {
      final cameraPermission = await Permission.camera.status;
      if (cameraPermission.isDenied) {
        final result = await Permission.camera.request();
        if (result.isDenied || result.isPermanentlyDenied) {
          setState(() {
            _errorMessage = 'Camera permission required';
          });
          return;
        }
      }

      _cameras = await availableCameras();
      debugPrint('📝 EnrollScreen: Found ${_cameras?.length ?? 0} cameras');

      if (_cameras == null || _cameras!.isEmpty) {
        setState(() {
          _errorMessage = 'No cameras found';
        });
        return;
      }

      final frontCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras!.first,
      );

      _controller = CameraController(
        frontCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();
      debugPrint('✅ EnrollScreen: Camera initialized');

      if (!mounted) return;

      setState(() {
        _isInitialized = true;
        _errorMessage = null;
      });
    } catch (e, stackTrace) {
      debugPrint('❌ EnrollScreen: Error initializing camera: $e');
      debugPrint('❌ EnrollScreen: Stack trace: $stackTrace');
      setState(() {
        _errorMessage = 'Failed to initialize camera: $e';
      });
    }
  }

  Future<void> _capturePhoto() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isCapturing) {
      return;
    }

    setState(() {
      _isCapturing = true;
    });

    try {
      debugPrint('📝 EnrollScreen: Capturing enrollment photo...');
      final image = await _controller!.takePicture();
      debugPrint('✅ EnrollScreen: Photo captured - ${image.path}');

      setState(() {
        _capturedImage = image;
        _isCapturing = false;
      });
    } catch (e, stackTrace) {
      debugPrint('❌ EnrollScreen: Error capturing photo: $e');
      debugPrint('❌ EnrollScreen: Stack trace: $stackTrace');
      setState(() {
        _isCapturing = false;
      });
    }
  }

  Future<void> _enrollUser() async {
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      debugPrint('⚠️ EnrollScreen: Name is empty');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a name'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_capturedImage == null) {
      debugPrint('⚠️ EnrollScreen: No photo captured');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please capture a photo'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!_faceRecognition.isInitialized) {
      debugPrint('⚠️ EnrollScreen: Face recognition not initialized');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Face recognition model is loading...'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isEnrolling = true;
    });

    try {
      debugPrint('📝 EnrollScreen: Starting enrollment for user: $name');

      // Load and decode image
      debugPrint('🧠 EnrollScreen: Loading image for face recognition...');
      final imageFile = File(_capturedImage!.path);
      final bytes = await imageFile.readAsBytes();
      final decodedImage = img.decodeImage(bytes);

      if (decodedImage == null) {
        throw Exception('Failed to decode image');
      }

      // Check if user is already registered with this face
      debugPrint('🧠 EnrollScreen: Checking if face is already registered...');
      final (isRegistered, existingName) = await _faceRecognition
          .isUserRegistered(decodedImage);

      if (isRegistered && existingName != null) {
        debugPrint(
          '⚠️ EnrollScreen: Face is already registered as: $existingName',
        );
        setState(() {
          _isEnrolling = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'This face is already registered as "$existingName"',
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // Enroll user with face recognition (computes and saves embedding)
      debugPrint('🧠 EnrollScreen: Computing face embedding...');
      final success = await _faceRecognition.enrollUser(name, decodedImage);

      if (!success) {
        throw Exception('Face detection failed - no face found in image');
      }

      // Save photo to permanent location (for display purposes)
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final photoPath = '${directory.path}/user_${timestamp}_photo.jpg';
      await imageFile.copy(photoPath);
      debugPrint('📝 EnrollScreen: Photo saved to: $photoPath');

      // Create user model for UI display
      final user = UserModel(
        id: timestamp.toString(),
        name: name,
        photoPaths: [photoPath],
        enrolledAt: DateTime.now(),
      );

      // Save to storage (for user list display)
      await _storage.addUser(user);
      debugPrint(
        '✅ EnrollScreen: User enrolled successfully with face embedding',
      );

      setState(() {
        _isEnrolling = false;
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text('$name enrolled successfully!')),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );

      // Return to previous screen
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e, stackTrace) {
      debugPrint('❌ EnrollScreen: Error enrolling user: $e');
      debugPrint('❌ EnrollScreen: Stack trace: $stackTrace');

      setState(() {
        _isEnrolling = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Enrollment failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _retake() {
    debugPrint('📝 EnrollScreen: Retaking photo');
    setState(() {
      _capturedImage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            debugPrint('📝 EnrollScreen: Back button pressed');
            Navigator.pop(context);
          },
        ),
        title: const Text(
          'Enroll New User',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_capturedImage != null) {
      return _buildEnrollmentForm();
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, color: Colors.red, size: 64),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _initializeCamera,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (!_isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.blue));
    }

    return _buildCameraView();
  }

  Widget _buildCameraView() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(child: CameraPreview(_controller!)),

        // Corner brackets
        Center(
          child: SizedBox(
            width: 280,
            height: 340,
            child: Stack(
              children: [
                _buildCorner(0, 0, true, true),
                _buildCorner(0, null, true, false),
                _buildCorner(null, 0, false, true),
                _buildCorner(null, null, false, false),
              ],
            ),
          ),
        ),

        // Instructions
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
                colors: [Colors.black.withOpacity(0.8), Colors.transparent],
              ),
            ),
            child: Column(
              children: [
                const Text(
                  'Position your face in the frame',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _isCapturing ? null : _capturePhoto,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: _isCapturing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.camera_alt, size: 24),
                            SizedBox(width: 8),
                            Text(
                              'Capture Photo',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEnrollmentForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Photo preview
          Container(
            height: 400,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.blue, width: 2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.file(File(_capturedImage!.path), fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 20),

          // Name input
          TextField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Enter Name',
              labelStyle: const TextStyle(color: Colors.blue),
              hintText: 'e.g., John Doe',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
              enabledBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: Colors.blue),
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: Colors.blue, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: const Icon(Icons.person, color: Colors.blue),
            ),
          ),
          const SizedBox(height: 20),

          // Enroll button
          ElevatedButton(
            onPressed: _enrollUser,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, size: 24),
                SizedBox(width: 8),
                Text(
                  'Enroll User',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Retake button
          OutlinedButton(
            onPressed: _retake,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.replay, color: Colors.white, size: 24),
                SizedBox(width: 8),
                Text(
                  'Retake Photo',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCorner(double? top, double? right, bool isTop, bool isLeft) {
    return Positioned(
      top: top,
      right: right,
      left: isLeft ? 0 : null,
      bottom: isTop ? null : 0,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          border: Border(
            top: isTop
                ? const BorderSide(color: Colors.white, width: 3)
                : BorderSide.none,
            bottom: !isTop
                ? const BorderSide(color: Colors.white, width: 3)
                : BorderSide.none,
            left: isLeft
                ? const BorderSide(color: Colors.white, width: 3)
                : BorderSide.none,
            right: !isLeft
                ? const BorderSide(color: Colors.white, width: 3)
                : BorderSide.none,
          ),
        ),
      ),
    );
  }
}
