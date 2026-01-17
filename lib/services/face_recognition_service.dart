import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'image_preprocessing.dart';
import 'embedding_storage.dart';

/// Face recognition service that handles TFLite model inference.
/// Matches Python: TFLiteFaceNet class and related functions
class FaceRecognitionService {
  static const String _modelPath =
      'assets/models/transfer-learningv4_int8.tflite';
  static const int _inputSize = 128;
  static const double _verificationThreshold = 1.9; // Matching Python threshold
  static const double _samePersonThreshold = 0.92; // For enrollment validation

  Interpreter? _interpreter;
  late FaceDetector _faceDetector;
  bool _isInitialized = false;

  // Quantization parameters (will be read from model)
  double _inputScale = 0;
  int _inputZeroPoint = 0;
  double _outputScale = 0;
  int _outputZeroPoint = 0;
  int _embeddingSize = 0;

  /// Initialize the face recognition service
  Future<bool> initialize() async {
    debugPrint('🧠 FaceRecognition: Initializing service...');

    try {
      // Initialize face detector (ML Kit - alternative to MTCNN)
      debugPrint('🧠 FaceRecognition: Initializing face detector...');
      final options = FaceDetectorOptions(
        enableContours: false,
        enableClassification: false,
        enableTracking: false,
        enableLandmarks: false,
        performanceMode: FaceDetectorMode.fast,
        minFaceSize: 0.1,
      );
      _faceDetector = FaceDetector(options: options);

      // Load TFLite model
      debugPrint(
        '🧠 FaceRecognition: Loading TFLite model from $_modelPath...',
      );
      _interpreter = await Interpreter.fromAsset(_modelPath);

      // Get input/output tensor details
      final inputTensors = _interpreter!.getInputTensors();
      final outputTensors = _interpreter!.getOutputTensors();

      debugPrint('🧠 FaceRecognition: Input tensors: ${inputTensors.length}');
      debugPrint('🧠 FaceRecognition: Output tensors: ${outputTensors.length}');

      if (inputTensors.isNotEmpty) {
        final input = inputTensors[0];
        debugPrint('🧠 FaceRecognition: Input shape: ${input.shape}');
        debugPrint('🧠 FaceRecognition: Input type: ${input.type}');

        // Get quantization parameters
        final inputParams = input.params;
        _inputScale = inputParams.scale;
        _inputZeroPoint = inputParams.zeroPoint;
        debugPrint(
          '🧠 FaceRecognition: Input scale: $_inputScale, zeroPoint: $_inputZeroPoint',
        );
      }

      if (outputTensors.isNotEmpty) {
        final output = outputTensors[0];
        debugPrint('🧠 FaceRecognition: Output shape: ${output.shape}');
        debugPrint('🧠 FaceRecognition: Output type: ${output.type}');
        _embeddingSize = output.shape.last;

        final outputParams = output.params;
        _outputScale = outputParams.scale;
        _outputZeroPoint = outputParams.zeroPoint;
        debugPrint(
          '🧠 FaceRecognition: Output scale: $_outputScale, zeroPoint: $_outputZeroPoint',
        );
        debugPrint('🧠 FaceRecognition: Embedding size: $_embeddingSize');
      }

      _isInitialized = true;
      debugPrint('✅ FaceRecognition: Service initialized successfully');
      return true;
    } catch (e, stackTrace) {
      debugPrint('❌ FaceRecognition: Error initializing: $e');
      debugPrint('❌ FaceRecognition: Stack trace: $stackTrace');
      return false;
    }
  }

  /// Dispose resources
  void dispose() {
    debugPrint('🧠 FaceRecognition: Disposing resources...');
    _interpreter?.close();
    _faceDetector.close();
  }

  /// Detect and crop face from image
  /// Matches Python: detect_and_crop_face(image)
  Future<img.Image?> detectAndCropFace(img.Image image) async {
    debugPrint('👤 FaceRecognition: Detecting face in image...');

    try {
      // Save temp image for ML Kit
      final tempDir = Directory.systemTemp;
      final tempFile = File(
        '${tempDir.path}/temp_face_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await tempFile.writeAsBytes(img.encodeJpg(image));

      final inputImage = InputImage.fromFilePath(tempFile.path);
      final faces = await _faceDetector.processImage(inputImage);

      // Clean up temp file
      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      if (faces.isEmpty) {
        debugPrint('👤 FaceRecognition: No face detected');
        return null;
      }

      // Get first face bounding box
      final face = faces.first;
      final boundingBox = face.boundingBox;

      debugPrint(
        '👤 FaceRecognition: Face detected at (${boundingBox.left}, ${boundingBox.top}) '
        'size: ${boundingBox.width}x${boundingBox.height}',
      );

      // Crop face (matching Python: image[y1:y2, x1:x2])
      final x1 = boundingBox.left.toInt().clamp(0, image.width - 1);
      final y1 = boundingBox.top.toInt().clamp(0, image.height - 1);
      final x2 = boundingBox.right.toInt().clamp(0, image.width);
      final y2 = boundingBox.bottom.toInt().clamp(0, image.height);

      final croppedFace = img.copyCrop(
        image,
        x: x1,
        y: y1,
        width: x2 - x1,
        height: y2 - y1,
      );

      debugPrint(
        '✅ FaceRecognition: Face cropped: ${croppedFace.width}x${croppedFace.height}',
      );
      return croppedFace;
    } catch (e, stackTrace) {
      debugPrint('❌ FaceRecognition: Error detecting face: $e');
      debugPrint('❌ FaceRecognition: Stack trace: $stackTrace');
      return null;
    }
  }

  /// Compute embedding for a face image
  /// Matches Python: compute_embedding(model, image, transform, device)
  Future<List<double>?> computeEmbedding(img.Image faceImage) async {
    if (!_isInitialized || _interpreter == null) {
      debugPrint('❌ FaceRecognition: Service not initialized');
      return null;
    }

    debugPrint('🧠 FaceRecognition: Computing embedding...');

    try {
      // Preprocess image (CLAHE + MSRCR + resize + normalize)
      final preprocessed = ImagePreprocessing.preprocessImage(
        faceImage,
        targetSize: _inputSize,
      );

      // Convert to proper input format
      // Input shape: (1, 128, 128, 3)
      final inputShape = _interpreter!.getInputTensor(0).shape;
      debugPrint('🧠 FaceRecognition: Expected input shape: $inputShape');

      // Prepare input tensor
      Object input;
      if (_inputScale > 0) {
        // Quantized model - convert to int8
        debugPrint('🧠 FaceRecognition: Applying int8 quantization...');
        final quantized = Int8List(preprocessed.length);
        for (int i = 0; i < preprocessed.length; i++) {
          final value = (preprocessed[i] / _inputScale) + _inputZeroPoint;
          quantized[i] = value.round().clamp(-128, 127);
        }
        input = quantized.reshape([1, _inputSize, _inputSize, 3]);
      } else {
        // Float model
        input = preprocessed.reshape([1, _inputSize, _inputSize, 3]);
      }

      // Prepare output tensor
      final outputShape = _interpreter!.getOutputTensor(0).shape;
      debugPrint('🧠 FaceRecognition: Expected output shape: $outputShape');

      Object output;
      if (_outputScale > 0) {
        // Quantized output
        output = List.filled(_embeddingSize, 0).reshape([1, _embeddingSize]);
      } else {
        output = List<double>.filled(
          _embeddingSize,
          0,
        ).reshape([1, _embeddingSize]);
      }

      // Run inference
      debugPrint('🧠 FaceRecognition: Running inference...');
      _interpreter!.run(input, output);

      // Extract embedding and dequantize if needed
      List<double> embedding;
      if (_outputScale > 0) {
        // Dequantize output
        debugPrint('🧠 FaceRecognition: Dequantizing output...');
        final rawOutput = (output as List)[0] as List;
        embedding = rawOutput.map((v) {
          return ((v as num).toDouble() - _outputZeroPoint) * _outputScale;
        }).toList();
      } else {
        embedding = ((output as List)[0] as List)
            .map((v) => (v as num).toDouble())
            .toList();
      }

      debugPrint(
        '✅ FaceRecognition: Embedding computed, dimension: ${embedding.length}',
      );
      return embedding;
    } catch (e, stackTrace) {
      debugPrint('❌ FaceRecognition: Error computing embedding: $e');
      debugPrint('❌ FaceRecognition: Stack trace: $stackTrace');
      return null;
    }
  }

  /// Calculate Euclidean distance between two embeddings
  /// Matches Python: pairwise_distance(..., p=2)
  static double calculateDistance(
    List<double> embedding1,
    List<double> embedding2,
  ) {
    if (embedding1.length != embedding2.length) {
      debugPrint('⚠️ FaceRecognition: Embedding dimensions mismatch');
      return double.infinity;
    }

    double sum = 0;
    for (int i = 0; i < embedding1.length; i++) {
      final diff = embedding1[i] - embedding2[i];
      sum += diff * diff;
    }
    return math.sqrt(sum);
  }

  /// Identify person from captured image
  /// Matches Python: identify_person(model, captured_image, dataset_embeddings, transform, device, threshold=1.4)
  Future<(String?, double)> identifyPerson(img.Image capturedImage) async {
    debugPrint('🔍 FaceRecognition: Identifying person...');

    // Detect and crop face
    final croppedFace = await detectAndCropFace(capturedImage);
    if (croppedFace == null) {
      debugPrint('❌ FaceRecognition: No face detected in image');
      return (null, double.infinity);
    }

    // Compute embedding
    final embedding = await computeEmbedding(croppedFace);
    if (embedding == null) {
      debugPrint('❌ FaceRecognition: Failed to compute embedding');
      return (null, double.infinity);
    }

    // Load stored embeddings
    final storedEmbeddings = await EmbeddingStorage.loadAllEmbeddings();
    if (storedEmbeddings.isEmpty) {
      debugPrint('⚠️ FaceRecognition: No enrolled users found');
      return (null, double.infinity);
    }

    // Compare with all stored embeddings
    String? identifiedPerson;
    double minDistance = double.infinity;

    for (final entry in storedEmbeddings.entries) {
      final personName = entry.key;
      final personEmbeddings = entry.value;

      // Find minimum distance to any of this person's embeddings
      for (final storedEmbedding in personEmbeddings) {
        final distance = calculateDistance(embedding, storedEmbedding);
        debugPrint(
          '🔍 FaceRecognition: Distance to $personName: ${distance.toStringAsFixed(4)}',
        );

        if (distance < minDistance) {
          minDistance = distance;
          identifiedPerson = personName;
        }
      }
    }

    // Check threshold
    if (minDistance < _verificationThreshold) {
      debugPrint(
        '✅ FaceRecognition: Match found: $identifiedPerson (distance: ${minDistance.toStringAsFixed(4)})',
      );
      return (identifiedPerson, minDistance);
    } else {
      debugPrint(
        '❌ FaceRecognition: No match found (min distance: ${minDistance.toStringAsFixed(4)})',
      );
      return (null, minDistance);
    }
  }

  /// Check if user is already registered
  /// Matches Python: is_user_registered(model, captured_images, dataset_embeddings, transform, device, threshold=1.4)
  Future<(bool, String?)> isUserRegistered(img.Image capturedImage) async {
    debugPrint('🔍 FaceRecognition: Checking if user is already registered...');

    final (identifiedPerson, distance) = await identifyPerson(capturedImage);

    if (identifiedPerson != null) {
      debugPrint(
        '⚠️ FaceRecognition: User is already registered as $identifiedPerson (distance: ${distance.toStringAsFixed(4)})',
      );
      return (true, identifiedPerson);
    }

    return (false, null);
  }

  /// Enroll a new user
  Future<bool> enrollUser(String userName, img.Image capturedImage) async {
    debugPrint('📝 FaceRecognition: Enrolling user: $userName');

    try {
      // Detect and crop face
      final croppedFace = await detectAndCropFace(capturedImage);
      if (croppedFace == null) {
        debugPrint('❌ FaceRecognition: No face detected for enrollment');
        return false;
      }

      // Check if already registered
      final (isRegistered, existingName) = await isUserRegistered(
        capturedImage,
      );
      if (isRegistered) {
        debugPrint(
          '⚠️ FaceRecognition: User is already registered as $existingName',
        );
        return false;
      }

      // Compute embedding
      final embedding = await computeEmbedding(croppedFace);
      if (embedding == null) {
        debugPrint(
          '❌ FaceRecognition: Failed to compute embedding for enrollment',
        );
        return false;
      }

      // Save embedding
      await EmbeddingStorage.saveEmbedding(userName, embedding);
      debugPrint('✅ FaceRecognition: User $userName enrolled successfully');
      return true;
    } catch (e, stackTrace) {
      debugPrint('❌ FaceRecognition: Error enrolling user: $e');
      debugPrint('❌ FaceRecognition: Stack trace: $stackTrace');
      return false;
    }
  }

  /// Verify a face and return result
  Future<(bool, String?, double)> verifyFace(img.Image capturedImage) async {
    debugPrint('🔐 FaceRecognition: Verifying face...');

    final (identifiedPerson, distance) = await identifyPerson(capturedImage);

    if (identifiedPerson != null) {
      debugPrint(
        '✅ FaceRecognition: Verification successful - $identifiedPerson',
      );
      return (true, identifiedPerson, distance);
    } else {
      debugPrint('❌ FaceRecognition: Verification failed');
      return (false, null, distance);
    }
  }

  bool get isInitialized => _isInitialized;
}
