import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Anti-spoofing service using MiniFASNetV2 TFLite model.
/// Detects if a face is real or a spoof (photo/screen attack).
///
/// Preprocessing pipeline matches Python implementation:
/// 1. Detect face bounding box
/// 2. Crop with scale 2.7 around face center
/// 3. Resize to 80x80
/// 4. Normalize to [0,1]
/// 5. Run TFLite inference
/// 6. Apply softmax to get probabilities
/// 7. Classify using threshold 0.088
class AntiSpoofingService {
  static const String _modelPath = 'assets/models/minifasnetv2_int8.tflite';
  static const int _inputSize = 80;
  static const double _cropScale = 2.7;
  static const double _spoofThreshold = 0.088;

  Interpreter? _interpreter;
  late FaceDetector _faceDetector;
  bool _isInitialized = false;

  // Quantization parameters (will be read from model)
  double _inputScale = 0;
  int _inputZeroPoint = 0;
  double _outputScale = 0;
  int _outputZeroPoint = 0;

  /// Initialize the anti-spoofing service
  Future<bool> initialize() async {
    debugPrint('🛡️ AntiSpoof: Initializing service...');

    try {
      // Initialize face detector (same as face recognition)
      debugPrint('🛡️ AntiSpoof: Initializing face detector...');
      final options = FaceDetectorOptions(
        enableContours: false,
        enableClassification: false,
        enableTracking: false,
        enableLandmarks: false,
        performanceMode: FaceDetectorMode.fast,
        minFaceSize: 0.1,
      );
      _faceDetector = FaceDetector(options: options);
      debugPrint('✅ AntiSpoof: Face detector initialized');

      // Load TFLite model
      debugPrint('🛡️ AntiSpoof: Loading TFLite model from $_modelPath...');
      _interpreter = await Interpreter.fromAsset(_modelPath);
      debugPrint('✅ AntiSpoof: TFLite model loaded');

      // Get input/output tensor details
      final inputTensors = _interpreter!.getInputTensors();
      final outputTensors = _interpreter!.getOutputTensors();

      debugPrint('🛡️ AntiSpoof: Input tensors: ${inputTensors.length}');
      debugPrint('🛡️ AntiSpoof: Output tensors: ${outputTensors.length}');

      if (inputTensors.isNotEmpty) {
        final input = inputTensors[0];
        debugPrint('🛡️ AntiSpoof: Input shape: ${input.shape}');
        debugPrint('🛡️ AntiSpoof: Input type: ${input.type}');

        // Get quantization parameters
        final inputParams = input.params;
        _inputScale = inputParams.scale;
        _inputZeroPoint = inputParams.zeroPoint;
        debugPrint(
          '🛡️ AntiSpoof: Input scale: $_inputScale, zeroPoint: $_inputZeroPoint',
        );
      }

      if (outputTensors.isNotEmpty) {
        final output = outputTensors[0];
        debugPrint('🛡️ AntiSpoof: Output shape: ${output.shape}');
        debugPrint('🛡️ AntiSpoof: Output type: ${output.type}');

        final outputParams = output.params;
        _outputScale = outputParams.scale;
        _outputZeroPoint = outputParams.zeroPoint;
        debugPrint(
          '🛡️ AntiSpoof: Output scale: $_outputScale, zeroPoint: $_outputZeroPoint',
        );
      }

      _isInitialized = true;
      debugPrint('✅ AntiSpoof: Service initialized successfully');
      debugPrint('🛡️ AntiSpoof: Using threshold: $_spoofThreshold');
      return true;
    } catch (e, stackTrace) {
      debugPrint('❌ AntiSpoof: Error initializing: $e');
      debugPrint('❌ AntiSpoof: Stack trace: $stackTrace');
      return false;
    }
  }

  /// Dispose resources
  void dispose() {
    debugPrint('🛡️ AntiSpoof: Disposing resources...');
    _interpreter?.close();
    _faceDetector.close();
  }

  /// Detect face and get bounding box
  /// Returns (x, y, width, height) or null if no face found
  Future<List<int>?> detectFaceBbox(img.Image image) async {
    debugPrint('🛡️ AntiSpoof: Detecting face bounding box...');
    debugPrint('🛡️ AntiSpoof: Image size: ${image.width}x${image.height}');

    try {
      // Save temp image for ML Kit
      final tempDir = Directory.systemTemp;
      final tempFile = File(
        '${tempDir.path}/temp_spoof_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await tempFile.writeAsBytes(img.encodeJpg(image));
      debugPrint('🛡️ AntiSpoof: Temp file created: ${tempFile.path}');

      final inputImage = InputImage.fromFilePath(tempFile.path);
      final faces = await _faceDetector.processImage(inputImage);
      debugPrint('🛡️ AntiSpoof: Detected ${faces.length} face(s)');

      // Clean up temp file
      if (await tempFile.exists()) {
        await tempFile.delete();
        debugPrint('🛡️ AntiSpoof: Temp file deleted');
      }

      if (faces.isEmpty) {
        debugPrint('🛡️ AntiSpoof: No face detected');
        return null;
      }

      // Get first face bounding box
      final face = faces.first;
      final boundingBox = face.boundingBox;

      final x = boundingBox.left.toInt().clamp(0, image.width - 1);
      final y = boundingBox.top.toInt().clamp(0, image.height - 1);
      final w = boundingBox.width.toInt().clamp(1, image.width - x);
      final h = boundingBox.height.toInt().clamp(1, image.height - y);

      debugPrint('🛡️ AntiSpoof: Face bbox: x=$x, y=$y, w=$w, h=$h');

      return [x, y, w, h];
    } catch (e, stackTrace) {
      debugPrint('❌ AntiSpoof: Error detecting face: $e');
      debugPrint('❌ AntiSpoof: Stack trace: $stackTrace');
      return null;
    }
  }

  /// Crop face with scale factor around center
  /// Matches Python: crop_face_scaled(img_bgr, bbox_xywh, scale=2.7)
  img.Image? cropFaceScaled(img.Image image, List<int> bboxXywh) {
    debugPrint('🛡️ AntiSpoof: Cropping face with scale $_cropScale...');

    final h = image.height;
    final w = image.width;
    final x = bboxXywh[0];
    final y = bboxXywh[1];
    final bw = bboxXywh[2];
    final bh = bboxXywh[3];

    // Calculate center and scaled crop region
    final cx = x + bw / 2.0;
    final cy = y + bh / 2.0;
    final side = math.max(bw, bh) * _cropScale;

    debugPrint('🛡️ AntiSpoof: Face center: ($cx, $cy), side: $side');

    int x1 = (cx - side / 2.0).round();
    int y1 = (cy - side / 2.0).round();
    int x2 = (cx + side / 2.0).round();
    int y2 = (cy + side / 2.0).round();

    // Clamp to image bounds
    x1 = x1.clamp(0, w);
    y1 = y1.clamp(0, h);
    x2 = x2.clamp(0, w);
    y2 = y2.clamp(0, h);

    debugPrint('🛡️ AntiSpoof: Crop region: x1=$x1, y1=$y1, x2=$x2, y2=$y2');

    if ((x2 - x1) < 2 || (y2 - y1) < 2) {
      debugPrint('❌ AntiSpoof: Crop region too small');
      return null;
    }

    final cropped = img.copyCrop(
      image,
      x: x1,
      y: y1,
      width: x2 - x1,
      height: y2 - y1,
    );

    debugPrint('✅ AntiSpoof: Cropped to ${cropped.width}x${cropped.height}');
    return cropped;
  }

  /// Preprocess cropped face for model input
  /// Matches Python: resize to 80x80, normalize to [0,1]
  Float32List preprocessForModel(img.Image croppedFace) {
    debugPrint('🛡️ AntiSpoof: Preprocessing for model...');
    debugPrint(
      '🛡️ AntiSpoof: Input crop size: ${croppedFace.width}x${croppedFace.height}',
    );

    // Resize to 80x80
    final resized = img.copyResize(
      croppedFace,
      width: _inputSize,
      height: _inputSize,
      interpolation: img.Interpolation.linear,
    );
    debugPrint('🛡️ AntiSpoof: Resized to ${resized.width}x${resized.height}');

    // Convert to float32 normalized [0,1] in NHWC format (H, W, C)
    final tensor = Float32List(_inputSize * _inputSize * 3);

    for (int y = 0; y < _inputSize; y++) {
      for (int x = 0; x < _inputSize; x++) {
        final pixel = resized.getPixel(x, y);
        final idx = (y * _inputSize + x) * 3;
        // BGR order to match Python cv2 (model trained with BGR)
        tensor[idx + 0] = pixel.b / 255.0;
        tensor[idx + 1] = pixel.g / 255.0;
        tensor[idx + 2] = pixel.r / 255.0;
      }
    }

    debugPrint('✅ AntiSpoof: Preprocessed tensor size: ${tensor.length}');

    // Debug: print first few values
    debugPrint(
      '🛡️ AntiSpoof: First 6 tensor values: [${tensor[0].toStringAsFixed(4)}, ${tensor[1].toStringAsFixed(4)}, ${tensor[2].toStringAsFixed(4)}, ${tensor[3].toStringAsFixed(4)}, ${tensor[4].toStringAsFixed(4)}, ${tensor[5].toStringAsFixed(4)}]',
    );

    return tensor;
  }

  /// Softmax for 2 classes
  /// Matches Python: softmax_2(x0, x1)
  (double, double) softmax2(double x0, double x1) {
    // Stable softmax
    final m = math.max(x0, x1);
    final e0 = math.exp(x0 - m);
    final e1 = math.exp(x1 - m);
    final s = e0 + e1;
    return (e0 / s, e1 / s);
  }

  /// Run TFLite inference
  /// Matches Python: run_tflite(interpreter, in_details, out_details, crop_bgr_80)
  Future<(double, double)?> runInference(Float32List preprocessed) async {
    if (!_isInitialized || _interpreter == null) {
      debugPrint('❌ AntiSpoof: Service not initialized');
      return null;
    }

    debugPrint('🛡️ AntiSpoof: Running TFLite inference...');

    try {
      // Prepare input tensor
      Object input;
      if (_inputScale > 0) {
        // Quantized model - convert to int8
        debugPrint('🛡️ AntiSpoof: Applying int8 quantization to input...');
        debugPrint(
          '🛡️ AntiSpoof: Input scale: $_inputScale, zeroPoint: $_inputZeroPoint',
        );

        final quantized = Int8List(preprocessed.length);
        for (int i = 0; i < preprocessed.length; i++) {
          final value = (preprocessed[i] / _inputScale) + _inputZeroPoint;
          quantized[i] = value.round().clamp(-128, 127);
        }

        // Debug: print first few quantized values
        debugPrint(
          '🛡️ AntiSpoof: First 6 quantized values: [${quantized[0]}, ${quantized[1]}, ${quantized[2]}, ${quantized[3]}, ${quantized[4]}, ${quantized[5]}]',
        );

        input = quantized.reshape([1, _inputSize, _inputSize, 3]);
      } else {
        // Float model
        debugPrint('🛡️ AntiSpoof: Using float32 input...');
        input = preprocessed.reshape([1, _inputSize, _inputSize, 3]);
      }

      // Prepare output tensor - shape [1, 2]
      List<List<int>> output;
      if (_outputScale > 0) {
        output = List.generate(1, (_) => List<int>.filled(2, 0));
      } else {
        output = List.generate(1, (_) => List<int>.filled(2, 0));
      }

      // Run inference
      debugPrint('🛡️ AntiSpoof: Invoking interpreter...');
      _interpreter!.run(input, output);
      debugPrint('🛡️ AntiSpoof: Inference complete');

      // Get raw output
      final rawOutput = output[0];
      debugPrint('🛡️ AntiSpoof: Raw output: $rawOutput');

      // Dequantize output if needed
      double logit0, logit1;
      if (_outputScale > 0) {
        debugPrint('🛡️ AntiSpoof: Dequantizing output...');
        debugPrint(
          '🛡️ AntiSpoof: Output scale: $_outputScale, zeroPoint: $_outputZeroPoint',
        );
        logit0 = (rawOutput[0] - _outputZeroPoint) * _outputScale;
        logit1 = (rawOutput[1] - _outputZeroPoint) * _outputScale;
      } else {
        logit0 = rawOutput[0].toDouble();
        logit1 = rawOutput[1].toDouble();
      }

      debugPrint('🛡️ AntiSpoof: Logits: [$logit0, $logit1]');

      // Apply softmax
      final (pReal, pSpoof) = softmax2(logit0, logit1);
      debugPrint(
        '🛡️ AntiSpoof: Probabilities - p_real: ${pReal.toStringAsFixed(4)}, p_spoof: ${pSpoof.toStringAsFixed(4)}',
      );

      return (pReal, pSpoof);
    } catch (e, stackTrace) {
      debugPrint('❌ AntiSpoof: Error during inference: $e');
      debugPrint('❌ AntiSpoof: Stack trace: $stackTrace');
      return null;
    }
  }

  /// Check if face is real (not a spoof)
  /// Returns: (isReal, pSpoof, errorMessage)
  /// isReal = true means the face passed liveness check
  Future<(bool, double, String?)> checkLiveness(img.Image image) async {
    debugPrint('🛡️ AntiSpoof: ========== LIVENESS CHECK START ==========');
    debugPrint('🛡️ AntiSpoof: Image size: ${image.width}x${image.height}');

    if (!_isInitialized) {
      debugPrint('❌ AntiSpoof: Service not initialized');
      return (false, 0.0, 'Anti-spoofing service not initialized');
    }

    try {
      // Step 1: Detect face
      debugPrint('🛡️ AntiSpoof: Step 1 - Detecting face...');
      final bbox = await detectFaceBbox(image);
      if (bbox == null) {
        debugPrint('❌ AntiSpoof: No face detected for liveness check');
        return (false, 0.0, 'No face detected');
      }

      // Step 2: Crop with scale
      debugPrint(
        '🛡️ AntiSpoof: Step 2 - Cropping face with scale $_cropScale...',
      );
      final cropped = cropFaceScaled(image, bbox);
      if (cropped == null) {
        debugPrint('❌ AntiSpoof: Failed to crop face');
        return (false, 0.0, 'Failed to crop face');
      }

      // Step 3: Preprocess
      debugPrint('🛡️ AntiSpoof: Step 3 - Preprocessing...');
      final preprocessed = preprocessForModel(cropped);

      // Step 4: Run inference
      debugPrint('🛡️ AntiSpoof: Step 4 - Running inference...');
      final result = await runInference(preprocessed);
      if (result == null) {
        debugPrint('❌ AntiSpoof: Inference failed');
        return (false, 0.0, 'Liveness inference failed');
      }

      final (pReal, pSpoof) = result;

      // Step 5: Apply threshold
      debugPrint(
        '🛡️ AntiSpoof: Step 5 - Applying threshold $_spoofThreshold...',
      );
      final isSpoof = pSpoof >= _spoofThreshold;
      final isReal = !isSpoof;

      debugPrint('🛡️ AntiSpoof: ========== LIVENESS CHECK RESULT ==========');
      debugPrint('🛡️ AntiSpoof: p_spoof: ${pSpoof.toStringAsFixed(4)}');
      debugPrint('🛡️ AntiSpoof: threshold: $_spoofThreshold');
      debugPrint(
        '🛡️ AntiSpoof: Result: ${isReal ? "✅ REAL FACE" : "❌ SPOOF DETECTED"}',
      );
      debugPrint(
        '🛡️ AntiSpoof: =============================================',
      );

      return (isReal, pSpoof, null);
    } catch (e, stackTrace) {
      debugPrint('❌ AntiSpoof: Error during liveness check: $e');
      debugPrint('❌ AntiSpoof: Stack trace: $stackTrace');
      return (false, 0.0, 'Liveness check error: $e');
    }
  }

  bool get isInitialized => _isInitialized;
}
