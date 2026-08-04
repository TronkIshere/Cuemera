// features/reference_photo/services/reference_image_analyzer.dart
import 'dart:io';
import 'dart:math';

import 'package:cuemera/features/reference_photo/domain/models/reference_profile.dart';
import 'package:flutter/material.dart' show HSLColor, Offset;
import 'package:flutter/painting.dart' show FileImage;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';
import 'package:image/image.dart' as img;
import 'package:palette_generator/palette_generator.dart';

class ReferenceImageAnalyzer {
  Future<ReferenceProfile> analyze(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);

    double? bodyRatio;
    double? shoulderAngleDegrees;
    List<Offset?>? poseLandmarkPoints;
    final poseDetector = PoseDetector(options: PoseDetectorOptions());
    try {
      final poses = await poseDetector.processImage(inputImage);
      if (poses.isNotEmpty) {
        final landmarks = poses.first.landmarks;
        final leftShoulder = landmarks[PoseLandmarkType.leftShoulder];
        final rightShoulder = landmarks[PoseLandmarkType.rightShoulder];
        final leftHip = landmarks[PoseLandmarkType.leftHip];
        final leftAnkle = landmarks[PoseLandmarkType.leftAnkle];
        final nose = landmarks[PoseLandmarkType.nose];

        if (leftShoulder != null && rightShoulder != null) {
          final dy = rightShoulder.y - leftShoulder.y;
          final dx = rightShoulder.x - leftShoulder.x;
          shoulderAngleDegrees = atan2(dy, dx) * 180 / pi;
        }

        if (nose != null && leftHip != null && leftAnkle != null) {
          final upperLength = (leftHip.y - nose.y).abs();
          final lowerLength = (leftAnkle.y - leftHip.y).abs();
          if (lowerLength > 0) bodyRatio = upperLength / lowerLength;
        }

        const landmarkTypesToDraw = [
          PoseLandmarkType.nose,
          PoseLandmarkType.leftEye,
          PoseLandmarkType.rightEye,
          PoseLandmarkType.leftShoulder,
          PoseLandmarkType.rightShoulder,
          PoseLandmarkType.leftElbow,
          PoseLandmarkType.rightElbow,
          PoseLandmarkType.leftWrist,
          PoseLandmarkType.rightWrist,
          PoseLandmarkType.leftHip,
          PoseLandmarkType.rightHip,
          PoseLandmarkType.leftKnee,
          PoseLandmarkType.rightKnee,
          PoseLandmarkType.leftAnkle,
          PoseLandmarkType.rightAnkle,
        ];
        const minLandmarkLikelihood = 0.6;
        final points = <Offset?>[];
        for (final type in landmarkTypesToDraw) {
          final landmark = landmarks[type];
          final isConfident =
              landmark != null && landmark.likelihood >= minLandmarkLikelihood;
          points.add(isConfident ? Offset(landmark.x, landmark.y) : null);
        }
        if (points.any((p) => p != null)) poseLandmarkPoints = points;
      }
    } catch (_) {
    } finally {
      await poseDetector.close();
    }

    double? faceAngleDegrees;
    String? expression;
    List<Offset>? faceContourPoints;
    final faceDetector = FaceDetector(
      options: FaceDetectorOptions(enableClassification: true),
    );
    try {
      final faces = await faceDetector.processImage(inputImage);
      if (faces.isNotEmpty) {
        final face = faces.first;
        faceAngleDegrees = face.headEulerAngleY;
        final smileProb = face.smilingProbability;
        if (smileProb != null) {
          if (smileProb > 0.7) {
            expression = 'smiling';
          } else if (smileProb > 0.3) {
            expression = 'neutral';
          } else {
            expression = 'serious';
          }
        }
        final box = face.boundingBox;
        faceContourPoints = [
          Offset(box.left, box.top),
          Offset(box.right, box.top),
          Offset(box.right, box.bottom),
          Offset(box.left, box.bottom),
        ];
      }
    } catch (_) {
    } finally {
      await faceDetector.close();
    }

    double? negativeSpaceScore;
    double? symmetryScore;
    int? backgroundClutterCount;
    SegmentationMask? mask;
    final segmenter = SelfieSegmenter(
      mode: SegmenterMode.single,
      enableRawSizeMask: true,
    );
    try {
      mask = await segmenter.processImage(inputImage);
    } catch (_) {
    } finally {
      await segmenter.close();
    }

    img.Image? decoded;
    double? imageWidth;
    double? imageHeight;
    try {
      final bytes = await File(imagePath).readAsBytes();
      decoded = img.decodeImage(bytes);
      if (decoded != null) {
        imageWidth = decoded.width.toDouble();
        imageHeight = decoded.height.toDouble();
      }
    } catch (_) {}

    if (mask != null) {
      negativeSpaceScore = _estimateNegativeSpace(mask);
      symmetryScore = _estimateSymmetry(mask, shoulderAngleDegrees);
      if (decoded != null) {
        backgroundClutterCount = _estimateBackgroundClutter(decoded, mask);
      }
    }

    double? overallBrightness;
    if (decoded != null) {
      overallBrightness = _estimateBrightness(decoded);
    }

    double? dominantHue;
    double? warmthScore;
    try {
      final paletteGenerator = await PaletteGenerator.fromImageProvider(
        FileImage(File(imagePath)),
      );
      final dominantColor = paletteGenerator.dominantColor?.color;
      if (dominantColor != null) {
        final hsl = HSLColor.fromColor(dominantColor);
        dominantHue = hsl.hue;
        warmthScore = ((cos((dominantHue - 60) * pi / 180) + 1) / 2).clamp(
          0.0,
          1.0,
        );
      }
    } catch (_) {}

    return ReferenceProfile(
      imagePath: imagePath,
      bodyRatio: bodyRatio,
      faceAngleDegrees: faceAngleDegrees,
      shoulderAngleDegrees: shoulderAngleDegrees,
      expression: expression,
      negativeSpaceScore: negativeSpaceScore,
      symmetryScore: symmetryScore,
      backgroundClutterCount: backgroundClutterCount,
      dominantHue: dominantHue,
      warmthScore: warmthScore,
      overallBrightness: overallBrightness,
      poseLandmarkPoints: poseLandmarkPoints,
      faceContourPoints: faceContourPoints,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
    );
  }

  double? _estimateNegativeSpace(SegmentationMask mask) {
    final confidences = mask.confidences;
    if (confidences.isEmpty) return null;

    int subjectPixels = 0;
    for (final confidence in confidences) {
      if (confidence > 0.5) subjectPixels++;
    }

    final total = confidences.length;
    if (total == 0) return null;

    final subjectRatio = subjectPixels / total;
    return (1.0 - subjectRatio).clamp(0.0, 1.0);
  }

  double? _estimateSymmetry(
    SegmentationMask mask,
    double? shoulderAngleDegrees,
  ) {
    if (shoulderAngleDegrees != null) {
      final angle = shoulderAngleDegrees.abs();
      return (1.0 - (angle / 45.0)).clamp(0.0, 1.0);
    }

    final confidences = mask.confidences;
    final width = mask.width;
    final height = mask.height;
    if (confidences.isEmpty || width <= 0 || height <= 0) return null;

    int leftSubject = 0;
    int rightSubject = 0;

    for (var y = 0; y < height; y += 4) {
      for (var x = 0; x < width; x += 4) {
        final index = y * width + x;
        if (index >= confidences.length) continue;

        if (confidences[index] > 0.5) {
          if (x < width / 2) {
            leftSubject++;
          } else {
            rightSubject++;
          }
        }
      }
    }

    final total = leftSubject + rightSubject;
    if (total == 0) return null;

    final balance = 1.0 - ((leftSubject - rightSubject).abs() / total);
    return balance.clamp(0.0, 1.0);
  }

  int? _estimateBackgroundClutter(img.Image decoded, SegmentationMask mask) {
    final width = decoded.width;
    final height = decoded.height;
    final confidences = mask.confidences;
    final maskWidth = mask.width;
    final maskHeight = mask.height;
    if (width <= 0 || height <= 0 || confidences.isEmpty) return null;

    const stepX = 6;
    const stepY = 6;

    double varianceSum = 0;
    int sampleCount = 0;
    int? previousValue;

    final scaleX = maskWidth / width;
    final scaleY = maskHeight / height;

    for (var y = 0; y < height; y += stepY) {
      for (var x = 0; x < width; x += stepX) {
        final maskX = (x * scaleX).floor();
        final maskY = (y * scaleY).floor();
        final maskIndex = maskY * maskWidth + maskX;

        bool isBackground = true;
        if (maskIndex >= 0 && maskIndex < confidences.length) {
          if (confidences[maskIndex] > 0.5) isBackground = false;
        }

        if (!isBackground) {
          previousValue = null;
          continue;
        }

        final pixel = decoded.getPixel(x, y);
        final luma = (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b)
            .round();

        if (previousValue != null) {
          final diff = (luma - previousValue).abs();
          varianceSum += diff;
          sampleCount++;
        }
        previousValue = luma;
      }
      previousValue = null;
    }

    if (sampleCount == 0) return null;

    final avgVariance = varianceSum / sampleCount;
    final clutterScore = (avgVariance / 12.0).clamp(0.0, 10.0);
    return clutterScore.round();
  }

  double? _estimateBrightness(img.Image decoded) {
    final width = decoded.width;
    final height = decoded.height;
    if (width <= 0 || height <= 0) return null;

    const stepX = 4;
    const stepY = 4;
    int sum = 0;
    int count = 0;

    for (var y = 0; y < height; y += stepY) {
      for (var x = 0; x < width; x += stepX) {
        final pixel = decoded.getPixel(x, y);
        final luma = (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b);
        sum += luma.round();
        count++;
      }
    }

    if (count == 0) return null;
    return (sum / count) / 255.0;
  }
}
