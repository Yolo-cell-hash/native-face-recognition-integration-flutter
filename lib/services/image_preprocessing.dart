import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// Image preprocessing service that replicates Python preprocessing pipeline.
/// Implements CLAHE and optional MSRCR algorithms.
class ImagePreprocessing {
  // MSRCR parameters (matching Python exactly)
  static const List<double> _sigmaList = [15, 80, 250];
  static const double _G = 5;
  static const double _b = 25;
  static const double _alpha = 125;
  static const double _beta = 46;

  /// Apply full preprocessing pipeline with optional fast mode.
  /// Fast mode: CLAHE only (much faster, good for mobile)
  /// Accurate mode: CLAHE + MSRCR (slower, matches Python exactly)
  static Float32List preprocessImage(
    img.Image image, {
    int targetSize = 128,
    bool useFastMode = true, // Default to fast for mobile
  }) {
    debugPrint('🔧 Preprocessing: Starting pipeline (fast=$useFastMode)...');
    debugPrint('🔧 Preprocessing: Input size: ${image.width}x${image.height}');

    // Step 1: Resize FIRST to reduce computation on smaller image
    debugPrint('🔧 Preprocessing: Resizing to ${targetSize}x$targetSize...');
    final resized = img.copyResize(
      image,
      width: targetSize,
      height: targetSize,
    );

    // Step 2: Apply CLAHE (fast contrast enhancement)
    debugPrint('🔧 Preprocessing: Applying CLAHE...');
    final claheImage = applyClaheSimple(resized);

    // Step 3: Apply brightness normalization (fast alternative to MSRCR)
    img.Image processedImage;
    if (useFastMode) {
      debugPrint('🔧 Preprocessing: Applying fast normalization...');
      processedImage = applyFastNormalization(claheImage);
    } else {
      // Full MSRCR (slow but accurate)
      debugPrint('🔧 Preprocessing: Applying MSRCR (slow)...');
      processedImage = applyMsrcr(claheImage);
    }

    // Step 4: Convert to normalized tensor format
    debugPrint('🔧 Preprocessing: Converting to tensor format...');
    final tensor = imageToTensor(processedImage);

    debugPrint('✅ Preprocessing: Complete. Tensor size: ${tensor.length}');
    return tensor;
  }

  /// Fast simplified CLAHE (only luminance channel, no tiles)
  static img.Image applyClaheSimple(img.Image image) {
    final width = image.width;
    final height = image.height;
    final result = img.Image(width: width, height: height);

    // Calculate histogram
    final histogram = List<int>.filled(256, 0);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = image.getPixel(x, y);
        final luminance = (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b)
            .toInt()
            .clamp(0, 255);
        histogram[luminance]++;
      }
    }

    // Calculate CDF
    final cdf = List<int>.filled(256, 0);
    cdf[0] = histogram[0];
    for (int i = 1; i < 256; i++) {
      cdf[i] = cdf[i - 1] + histogram[i];
    }

    // Normalize CDF
    final cdfMin = cdf.firstWhere((v) => v > 0, orElse: () => 0);
    final cdfMax = cdf[255];
    final cdfRange = cdfMax - cdfMin;

    // Apply equalization
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();

        // Scale each channel proportionally
        if (cdfRange > 0) {
          final lum = (0.299 * r + 0.587 * g + 0.114 * b).toInt().clamp(0, 255);
          final newLum = ((cdf[lum] - cdfMin) * 255 / cdfRange).round();
          final scale = lum > 0 ? newLum / lum : 1.0;

          result.setPixelRgba(
            x,
            y,
            (r * scale).clamp(0, 255).toInt(),
            (g * scale).clamp(0, 255).toInt(),
            (b * scale).clamp(0, 255).toInt(),
            255,
          );
        } else {
          result.setPixelRgba(x, y, r, g, b, 255);
        }
      }
    }

    return result;
  }

  /// Fast brightness/contrast normalization (alternative to MSRCR)
  static img.Image applyFastNormalization(img.Image image) {
    final width = image.width;
    final height = image.height;
    final result = img.Image(width: width, height: height);

    // Calculate min/max for normalization
    int minVal = 255, maxVal = 0;
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = image.getPixel(x, y);
        final lum = ((pixel.r + pixel.g + pixel.b) / 3).toInt();
        if (lum < minVal) minVal = lum;
        if (lum > maxVal) maxVal = lum;
      }
    }

    final range = maxVal - minVal;
    if (range == 0) return image;

    // Normalize to full range with slight gamma correction
    const gamma = 0.9; // Slight brightening
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();

        // Normalize and apply gamma
        final nr = (math.pow((r - minVal) / range, gamma) * 255)
            .clamp(0, 255)
            .toInt();
        final ng = (math.pow((g - minVal) / range, gamma) * 255)
            .clamp(0, 255)
            .toInt();
        final nb = (math.pow((b - minVal) / range, gamma) * 255)
            .clamp(0, 255)
            .toInt();

        result.setPixelRgba(x, y, nr, ng, nb, 255);
      }
    }

    return result;
  }

  /// Apply CLAHE (Contrast Limited Adaptive Histogram Equalization)
  /// Matches Python: apply_clahe(image) with clipLimit=2.0, tileGridSize=(8,8)
  static img.Image applyClahe(
    img.Image image, {
    double clipLimit = 2.0,
    int tileGridSize = 8,
  }) {
    debugPrint(
      '🔧 CLAHE: Processing with clipLimit=$clipLimit, tileGridSize=$tileGridSize',
    );

    final width = image.width;
    final height = image.height;
    final result = img.Image(width: width, height: height);

    // Process each channel separately (matching Python cv2.split behavior)
    final redChannel = Uint8List(width * height);
    final greenChannel = Uint8List(width * height);
    final blueChannel = Uint8List(width * height);

    // Extract channels
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = image.getPixel(x, y);
        final idx = y * width + x;
        redChannel[idx] = pixel.r.toInt();
        greenChannel[idx] = pixel.g.toInt();
        blueChannel[idx] = pixel.b.toInt();
      }
    }

    // Apply CLAHE to each channel
    final claheRed = _applyClaheToChannel(
      redChannel,
      width,
      height,
      clipLimit,
      tileGridSize,
    );
    final claheGreen = _applyClaheToChannel(
      greenChannel,
      width,
      height,
      clipLimit,
      tileGridSize,
    );
    final claheBlue = _applyClaheToChannel(
      blueChannel,
      width,
      height,
      clipLimit,
      tileGridSize,
    );

    // Merge channels back
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final idx = y * width + x;
        result.setPixelRgba(
          x,
          y,
          claheRed[idx],
          claheGreen[idx],
          claheBlue[idx],
          255,
        );
      }
    }

    return result;
  }

  /// Apply CLAHE to a single channel
  static Uint8List _applyClaheToChannel(
    Uint8List channel,
    int width,
    int height,
    double clipLimit,
    int tileGridSize,
  ) {
    final result = Uint8List(width * height);
    final tileWidth = (width / tileGridSize).ceil();
    final tileHeight = (height / tileGridSize).ceil();

    // Process each tile
    for (int ty = 0; ty < tileGridSize; ty++) {
      for (int tx = 0; tx < tileGridSize; tx++) {
        final startX = tx * tileWidth;
        final startY = ty * tileHeight;
        final endX = math.min(startX + tileWidth, width);
        final endY = math.min(startY + tileHeight, height);

        // Calculate histogram for this tile
        final histogram = List<int>.filled(256, 0);
        int pixelCount = 0;

        for (int y = startY; y < endY; y++) {
          for (int x = startX; x < endX; x++) {
            histogram[channel[y * width + x]]++;
            pixelCount++;
          }
        }

        // Clip histogram based on clipLimit
        if (pixelCount > 0) {
          final clipThreshold = (clipLimit * pixelCount / 256).ceil();
          int excess = 0;

          for (int i = 0; i < 256; i++) {
            if (histogram[i] > clipThreshold) {
              excess += histogram[i] - clipThreshold;
              histogram[i] = clipThreshold;
            }
          }

          // Redistribute excess
          final redistribute = excess ~/ 256;
          for (int i = 0; i < 256; i++) {
            histogram[i] += redistribute;
          }
        }

        // Calculate CDF
        final cdf = List<int>.filled(256, 0);
        cdf[0] = histogram[0];
        for (int i = 1; i < 256; i++) {
          cdf[i] = cdf[i - 1] + histogram[i];
        }

        // Normalize CDF
        final cdfMin = cdf.firstWhere((v) => v > 0, orElse: () => 0);
        final cdfMax = cdf[255];

        // Apply equalization to this tile
        for (int y = startY; y < endY; y++) {
          for (int x = startX; x < endX; x++) {
            final idx = y * width + x;
            final value = channel[idx];
            if (cdfMax > cdfMin) {
              result[idx] = ((cdf[value] - cdfMin) * 255 ~/ (cdfMax - cdfMin))
                  .clamp(0, 255);
            } else {
              result[idx] = value;
            }
          }
        }
      }
    }

    return result;
  }

  /// Apply MSRCR (Multi-Scale Retinex with Color Restoration)
  /// Matches Python: apply_msrcr(image) exactly
  static img.Image applyMsrcr(img.Image image) {
    debugPrint(
      '🔧 MSRCR: Applying Multi-Scale Retinex with Color Restoration...',
    );

    final width = image.width;
    final height = image.height;

    // Convert to float64 arrays (matching Python: img = np.float64(image) + 1.0)
    final imgR = List<double>.filled(width * height, 0);
    final imgG = List<double>.filled(width * height, 0);
    final imgB = List<double>.filled(width * height, 0);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = image.getPixel(x, y);
        final idx = y * width + x;
        imgR[idx] = pixel.r.toDouble() + 1.0;
        imgG[idx] = pixel.g.toDouble() + 1.0;
        imgB[idx] = pixel.b.toDouble() + 1.0;
      }
    }

    // Calculate retinex for each sigma and sum
    final retinexR = List<double>.filled(width * height, 0);
    final retinexG = List<double>.filled(width * height, 0);
    final retinexB = List<double>.filled(width * height, 0);

    for (final sigma in _sigmaList) {
      final blurR = _gaussianBlur(imgR, width, height, sigma);
      final blurG = _gaussianBlur(imgG, width, height, sigma);
      final blurB = _gaussianBlur(imgB, width, height, sigma);

      for (int i = 0; i < width * height; i++) {
        // retinex = log10(img) - log10(blur)
        retinexR[i] += _safeLog10(imgR[i]) - _safeLog10(blurR[i]);
        retinexG[i] += _safeLog10(imgG[i]) - _safeLog10(blurG[i]);
        retinexB[i] += _safeLog10(imgB[i]) - _safeLog10(blurB[i]);
      }
    }

    // Average retinex across scales
    for (int i = 0; i < width * height; i++) {
      retinexR[i] /= _sigmaList.length;
      retinexG[i] /= _sigmaList.length;
      retinexB[i] /= _sigmaList.length;
    }

    // Color restoration
    final colorR = List<double>.filled(width * height, 0);
    final colorG = List<double>.filled(width * height, 0);
    final colorB = List<double>.filled(width * height, 0);

    for (int i = 0; i < width * height; i++) {
      final imgSum = imgR[i] + imgG[i] + imgB[i];
      colorR[i] = _beta * (_safeLog10(_alpha * imgR[i]) - _safeLog10(imgSum));
      colorG[i] = _beta * (_safeLog10(_alpha * imgG[i]) - _safeLog10(imgSum));
      colorB[i] = _beta * (_safeLog10(_alpha * imgB[i]) - _safeLog10(imgSum));
    }

    // Final MSRCR: G * (retinex * color + b)
    final result = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final i = y * width + x;
        final r = (_G * (retinexR[i] * colorR[i] + _b)).clamp(0, 255).toInt();
        final g = (_G * (retinexG[i] * colorG[i] + _b)).clamp(0, 255).toInt();
        final b = (_G * (retinexB[i] * colorB[i] + _b)).clamp(0, 255).toInt();
        result.setPixelRgba(x, y, r, g, b, 255);
      }
    }

    return result;
  }

  /// Gaussian blur implementation
  /// Matches Python: cv2.GaussianBlur(img, (0, 0), sigma)
  static List<double> _gaussianBlur(
    List<double> channel,
    int width,
    int height,
    double sigma,
  ) {
    // Calculate kernel size based on sigma (OpenCV convention)
    final kSize = ((sigma * 6).ceil() | 1); // Must be odd
    final halfK = kSize ~/ 2;

    // Generate 1D Gaussian kernel
    final kernel = List<double>.filled(kSize, 0);
    double sum = 0;
    for (int i = 0; i < kSize; i++) {
      final x = i - halfK;
      kernel[i] = math.exp(-(x * x) / (2 * sigma * sigma));
      sum += kernel[i];
    }
    // Normalize
    for (int i = 0; i < kSize; i++) {
      kernel[i] /= sum;
    }

    // Separable convolution: horizontal pass
    final temp = List<double>.filled(width * height, 0);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        double value = 0;
        for (int k = 0; k < kSize; k++) {
          final nx = (x + k - halfK).clamp(0, width - 1);
          value += channel[y * width + nx] * kernel[k];
        }
        temp[y * width + x] = value;
      }
    }

    // Vertical pass
    final result = List<double>.filled(width * height, 0);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        double value = 0;
        for (int k = 0; k < kSize; k++) {
          final ny = (y + k - halfK).clamp(0, height - 1);
          value += temp[ny * width + x] * kernel[k];
        }
        result[y * width + x] = value;
      }
    }

    return result;
  }

  /// Safe log10 to avoid log(0)
  static double _safeLog10(double value) {
    return math.log(math.max(value, 1e-10)) / math.ln10;
  }

  /// Convert image to tensor format (H, W, C) normalized to [0, 1]
  /// Matches Python: transforms.ToTensor() which normalizes to [0,1]
  static Float32List imageToTensor(img.Image image) {
    final width = image.width;
    final height = image.height;
    // Output format: (H, W, C) as expected by TFLite
    final tensor = Float32List(height * width * 3);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = image.getPixel(x, y);
        final idx = (y * width + x) * 3;
        // Normalize to [0, 1] like PyTorch ToTensor()
        tensor[idx + 0] = pixel.r / 255.0;
        tensor[idx + 1] = pixel.g / 255.0;
        tensor[idx + 2] = pixel.b / 255.0;
      }
    }

    return tensor;
  }

  /// Convert camera image bytes to img.Image
  static img.Image? bytesToImage(
    Uint8List bytes,
    int width,
    int height, {
    bool isBgr = true,
  }) {
    try {
      // Try to decode as JPEG first
      final decoded = img.decodeImage(bytes);
      if (decoded != null) {
        return decoded;
      }
    } catch (e) {
      debugPrint(
        '🔧 Preprocessing: Could not decode as standard format, trying raw conversion',
      );
    }

    // If decoding fails, assume raw RGB/BGR format
    if (bytes.length >= width * height * 3) {
      final image = img.Image(width: width, height: height);
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final idx = (y * width + x) * 3;
          if (isBgr) {
            // BGR to RGB
            image.setPixelRgba(
              x,
              y,
              bytes[idx + 2],
              bytes[idx + 1],
              bytes[idx],
              255,
            );
          } else {
            image.setPixelRgba(
              x,
              y,
              bytes[idx],
              bytes[idx + 1],
              bytes[idx + 2],
              255,
            );
          }
        }
      }
      return image;
    }

    return null;
  }
}
