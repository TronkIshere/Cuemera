// features/scene_analysis/services/light_analyzer.dart
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';

import '../domain/models/scene_profile.dart';
import '../domain/models/subject_profile.dart';

class LightAnalyzer {
  /// Set to `true` for a physical-device verification pass of the
  /// `planes[1]=U, planes[2]=V` assumption in [_estimateColorTone]
  /// (see LIMITATIONS_AND_ROADMAP.md). With this on, point the camera at
  /// a known pure-red target, then a known pure-blue target, and compare
  /// the logged `avgU`/`avgV` against the expected YUV values for each
  /// (pure red: U low/~90, V high/~240; pure blue: U high/~240, V
  /// low/~110, for standard BT.601 full-range). If the logged values are
  /// swapped or don't move as expected, the plane-index assumption is
  /// wrong for this device/format and `_estimateColorTone` needs fixing.
  /// Leave `false` outside of that verification pass — this runs every
  /// analyzed frame and would otherwise flood the log.
  static const bool debugLogColorToneSamples = false;

  /// Set to `true` to log analyzeLight()'s per-frame wall-clock cost via
  /// debugPrint, for sizing Finding B from the camera-pipeline
  /// performance audit against a real device. Leave `false` normally —
  /// this runs every analyzed frame and would otherwise flood the log.
  static const bool debugLogFrameTiming = false;

  /// Wall-clock cost of the most recent analyzeLight() call, in
  /// microseconds. Updated every call regardless of
  /// [debugLogFrameTiming], so a debug UI can read it without needing
  /// log spam turned on.
  int? lastAnalyzeLightMicros;

  SceneProfile analyzeLight(
    dynamic cameraFrame,
    SceneProfile previous, {
    SegmentationMask? segmentationMask,
    SubjectProfile? subject,
  }) {
    final image = cameraFrame as CameraImage?;
    if (image == null) return previous;

    final stopwatch = Stopwatch()..start();

    final brightness = _estimateBrightness(image);
    final lightDirectionDegrees = _estimateLightDirection(image);

    final subjectRatio = _computeSubjectRatio(segmentationMask);
    final backgroundVariance = _computeBackgroundVariance(
      image,
      segmentationMask,
    );

    final backgroundClutterCount = _backgroundClutterScore(backgroundVariance);
    final negativeSpaceScore = _negativeSpaceScore(subjectRatio);
    final symmetryScore = _estimateSymmetry(image, segmentationMask, subject);
    final (hue, warmth) = _estimateColorTone(image);
    final depthEstimate = _depthScore(subjectRatio, backgroundVariance);

    stopwatch.stop();
    lastAnalyzeLightMicros = stopwatch.elapsedMicroseconds;
    if (debugLogFrameTiming) {
      debugPrint(
        '[LightAnalyzer] analyzeLight: ${stopwatch.elapsedMicroseconds}us',
      );
    }

    return previous.copyWith(
      brightness: brightness,
      lightDirectionDegrees: lightDirectionDegrees,
      negativeSpaceScore: negativeSpaceScore,
      symmetryScore: symmetryScore,
      backgroundClutterCount: backgroundClutterCount,
      depthEstimate: depthEstimate,
      liveWarmthScore: warmth,
      liveDominantHue: hue,
    );
  }

  double _estimateBrightness(CameraImage image) {
    final plane = image.planes.first;
    final bytes = plane.bytes;
    if (bytes.isEmpty) return 0.5;

    final sampleStep = (bytes.length / 2000).clamp(1, bytes.length).toInt();
    int sum = 0;
    int count = 0;

    for (var i = 0; i < bytes.length; i += sampleStep) {
      sum += bytes[i];
      count++;
    }

    if (count == 0) return 0.5;
    return (sum / count) / 255.0;
  }

  double? _estimateLightDirection(CameraImage image) {
    final plane = image.planes.first;
    final bytes = plane.bytes;
    final width = image.width;
    final height = image.height;
    final bytesPerRow = plane.bytesPerRow;

    if (bytes.isEmpty || width <= 0 || height <= 0) return null;

    double leftSum = 0, rightSum = 0, topSum = 0, bottomSum = 0;
    int leftCount = 0, rightCount = 0, topCount = 0, bottomCount = 0;

    const stepX = 8;
    const stepY = 8;

    for (var y = 0; y < height; y += stepY) {
      final rowOffset = y * bytesPerRow;
      if (rowOffset >= bytes.length) continue;

      for (var x = 0; x < width; x += stepX) {
        final index = rowOffset + x;
        if (index >= bytes.length) continue;

        final value = bytes[index];

        if (x < width / 2) {
          leftSum += value;
          leftCount++;
        } else {
          rightSum += value;
          rightCount++;
        }

        if (y < height / 2) {
          topSum += value;
          topCount++;
        } else {
          bottomSum += value;
          bottomCount++;
        }
      }
    }

    if (leftCount == 0 || rightCount == 0 || topCount == 0 || bottomCount == 0)
      return null;

    final leftAvg = leftSum / leftCount;
    final rightAvg = rightSum / rightCount;
    final topAvg = topSum / topCount;
    final bottomAvg = bottomSum / bottomCount;

    final horizontalDelta = rightAvg - leftAvg;
    final verticalDelta = topAvg - bottomAvg;

    if (horizontalDelta.abs() < 2 && verticalDelta.abs() < 2) return null;

    final angle = _atan2Degrees(verticalDelta, horizontalDelta);
    return angle;
  }

  double _atan2Degrees(double y, double x) {
    var degrees = math.atan2(y, x) * 180 / math.pi;
    if (degrees < 0) degrees += 360;
    return degrees;
  }

  double? _computeSubjectRatio(SegmentationMask? mask) {
    if (mask == null) return null;

    final confidences = mask.confidences;
    if (confidences.isEmpty) return null;

    int subjectPixels = 0;
    for (final confidence in confidences) {
      if (confidence > 0.5) subjectPixels++;
    }

    return subjectPixels / confidences.length;
  }

  double _negativeSpaceScore(double? subjectRatio) {
    if (subjectRatio == null) return 0.0;
    return (1.0 - subjectRatio).clamp(0.0, 1.0);
  }

  double _estimateSymmetry(
    CameraImage image,
    SegmentationMask? mask,
    SubjectProfile? subject,
  ) {
    if (subject?.shoulderAngleDegrees != null) {
      final angle = subject!.shoulderAngleDegrees!.abs();
      return (1.0 - (angle / 45.0)).clamp(0.0, 1.0);
    }

    if (mask == null) return 0.5;

    final confidences = mask.confidences;
    final width = mask.width;
    final height = mask.height;
    if (confidences.isEmpty || width <= 0 || height <= 0) return 0.5;

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
    if (total == 0) return 0.5;

    final balance = 1.0 - ((leftSubject - rightSubject).abs() / total);
    return balance.clamp(0.0, 1.0);
  }

  double? _computeBackgroundVariance(
    CameraImage image,
    SegmentationMask? mask,
  ) {
    final plane = image.planes.first;
    final bytes = plane.bytes;
    final width = image.width;
    final height = image.height;
    final bytesPerRow = plane.bytesPerRow;

    if (bytes.isEmpty || width <= 0 || height <= 0) return null;

    List<double>? confidences;
    int maskWidth = width;
    if (mask != null) {
      confidences = mask.confidences;
      maskWidth = mask.width;
    }

    const stepX = 6;
    const stepY = 6;

    double varianceSum = 0;
    int sampleCount = 0;

    int? previousValue;

    for (var y = 0; y < height; y += stepY) {
      final rowOffset = y * bytesPerRow;
      if (rowOffset >= bytes.length) continue;

      for (var x = 0; x < width; x += stepX) {
        final index = rowOffset + x;
        if (index >= bytes.length) continue;

        bool isBackground = true;
        if (confidences != null) {
          final maskIndex = y * maskWidth + x;
          if (maskIndex < confidences.length && confidences[maskIndex] > 0.5) {
            isBackground = false;
          }
        }

        if (!isBackground) continue;

        final value = bytes[index];
        if (previousValue != null) {
          final diff = (value - previousValue).abs();
          varianceSum += diff;
          sampleCount++;
        }
        previousValue = value;
      }
      previousValue = null;
    }

    if (sampleCount == 0) return null;
    return varianceSum / sampleCount;
  }

  int _backgroundClutterScore(double? variance) {
    if (variance == null) return 0;
    final clutterScore = (variance / 12.0).clamp(0.0, 10.0);
    return clutterScore.round();
  }

  double? _depthScore(double? subjectRatio, double? backgroundVariance) {
    if (subjectRatio == null) return null;

    final avgVariance = backgroundVariance ?? 0.0;
    final normalizedVariance = (avgVariance / 20.0).clamp(0.0, 1.0);
    final sharpnessDepthSignal = 1.0 - normalizedVariance;

    return ((subjectRatio + sharpnessDepthSignal) / 2.0).clamp(0.0, 1.0);
  }

  (double?, double?) _estimateColorTone(CameraImage image) {
    if (image.planes.length < 3) return (null, null);

    final uBytes = image.planes[1].bytes;
    final vBytes = image.planes[2].bytes;
    if (uBytes.isEmpty || vBytes.isEmpty) return (null, null);

    final uSampleStep = (uBytes.length / 2000).clamp(1, uBytes.length).toInt();
    int uSum = 0;
    int uCount = 0;
    for (var i = 0; i < uBytes.length; i += uSampleStep) {
      uSum += uBytes[i];
      uCount++;
    }

    final vSampleStep = (vBytes.length / 2000).clamp(1, vBytes.length).toInt();
    int vSum = 0;
    int vCount = 0;
    for (var i = 0; i < vBytes.length; i += vSampleStep) {
      vSum += vBytes[i];
      vCount++;
    }

    if (uCount == 0 || vCount == 0) return (null, null);

    final avgU = uSum / uCount;
    final avgV = vSum / vCount;

    final centeredU = avgU - 128;
    final centeredV = avgV - 128;

    final normalizedWarmth = (centeredV / 128).clamp(-1.0, 1.0);
    final warmth = (((normalizedWarmth + 1.0) / 2.0)).clamp(0.0, 1.0);

    final hue = _atan2Degrees(centeredV, centeredU);

    if (debugLogColorToneSamples) {
      debugPrint(
        '[LightAnalyzer] colorTone sample — '
        'avgU: ${avgU.toStringAsFixed(1)}, '
        'avgV: ${avgV.toStringAsFixed(1)}, '
        'hue: ${hue.toStringAsFixed(1)}, '
        'warmth: ${warmth.toStringAsFixed(2)}',
      );
    }

    return (hue, warmth);
  }
}
