// features/scene_analysis/services/light_analyzer.dart
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';

import '../domain/models/scene_profile.dart';
import '../domain/models/subject_profile.dart';

class LightAnalyzer {
  static const bool debugLogColorToneSamples = false;
  static const bool debugLogFrameTiming = false;
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
    final maskStats = _analyzeMask(segmentationMask);
    final lumaStats = _analyzeLumaPlane(image, segmentationMask);

    final subjectRatio = maskStats?.subjectRatio;
    final backgroundVariance = lumaStats.backgroundVariance;

    final backgroundClutterCount = _backgroundClutterScore(backgroundVariance);
    final negativeSpaceScore = _negativeSpaceScore(subjectRatio);
    final symmetryScore = _estimateSymmetry(maskStats, subject);
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
      lightDirectionDegrees: lumaStats.lightDirectionDegrees,
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
    final width = image.width;
    final height = image.height;
    final bytesPerRow = plane.bytesPerRow;
    if (bytes.isEmpty || width <= 0 || height <= 0) return 0.5;

    final step = math.sqrt((width * height) / 2000).round().clamp(1, width);

    int sum = 0;
    int count = 0;

    for (var y = 0; y < height; y += step) {
      final rowOffset = y * bytesPerRow;
      if (rowOffset >= bytes.length) continue;
      for (var x = 0; x < width; x += step) {
        final index = rowOffset + x;
        if (index >= bytes.length) continue;
        sum += bytes[index];
        count++;
      }
    }

    if (count == 0) return 0.5;
    return (sum / count) / 255.0;
  }

  double _atan2Degrees(double y, double x) {
    var degrees = math.atan2(y, x) * 180 / math.pi;
    if (degrees < 0) degrees += 360;
    return degrees;
  }

  double _negativeSpaceScore(double? subjectRatio) {
    if (subjectRatio == null) return 0.0;
    return (1.0 - subjectRatio).clamp(0.0, 1.0);
  }

  double _estimateSymmetry(_MaskStats? maskStats, SubjectProfile? subject) {
    final shoulderAngle = subject?.shoulderAngleDegrees;
    if (shoulderAngle != null) {
      return (1.0 - (shoulderAngle.abs() / 45.0)).clamp(0.0, 1.0);
    }

    if (maskStats == null) return 0.5;

    final left = maskStats.leftSubjectPixels;
    final right = maskStats.rightSubjectPixels;
    final total = left + right;
    if (total == 0) return 0.5;

    return (1.0 - ((left - right).abs() / total)).clamp(0.0, 1.0);
  }

  _MaskStats? _analyzeMask(SegmentationMask? mask) {
    if (mask == null) return null;

    final confidences = mask.confidences;
    final width = mask.width;
    final height = mask.height;
    if (confidences.isEmpty || width <= 0 || height <= 0) return null;

    const step = 4;
    final halfWidth = width / 2;

    int subjectPixels = 0;
    int sampledPixels = 0;
    int leftSubjectPixels = 0;
    int rightSubjectPixels = 0;

    for (var y = 0; y < height; y += step) {
      final rowOffset = y * width;
      for (var x = 0; x < width; x += step) {
        final index = rowOffset + x;
        if (index >= confidences.length) continue;

        sampledPixels++;
        if (confidences[index] <= 0.5) continue;

        subjectPixels++;
        if (x < halfWidth) {
          leftSubjectPixels++;
        } else {
          rightSubjectPixels++;
        }
      }
    }

    if (sampledPixels == 0) return null;

    return _MaskStats(
      subjectRatio: subjectPixels / sampledPixels,
      leftSubjectPixels: leftSubjectPixels,
      rightSubjectPixels: rightSubjectPixels,
    );
  }

  _LumaStats _analyzeLumaPlane(CameraImage image, SegmentationMask? mask) {
    final plane = image.planes.first;
    final bytes = plane.bytes;
    final width = image.width;
    final height = image.height;
    final bytesPerRow = plane.bytesPerRow;

    const empty = _LumaStats(
      lightDirectionDegrees: null,
      backgroundVariance: null,
    );
    if (bytes.isEmpty || width <= 0 || height <= 0) return empty;

    final maskConfidences = mask?.confidences ?? const <double>[];
    final maskWidth = mask?.width ?? 0;
    final maskHeight = mask?.height ?? 0;
    final useMask =
        maskConfidences.isNotEmpty && maskWidth > 0 && maskHeight > 0;
    final maskScaleX = useMask ? maskWidth / width : 0.0;
    final maskScaleY = useMask ? maskHeight / height : 0.0;

    const step = 6;
    final halfWidth = width / 2;
    final halfHeight = height / 2;

    double leftSum = 0, rightSum = 0, topSum = 0, bottomSum = 0;
    int leftCount = 0, rightCount = 0, topCount = 0, bottomCount = 0;
    double varianceSum = 0;
    int varianceSamples = 0;
    int? previousBackgroundValue;

    for (var y = 0; y < height; y += step) {
      final rowOffset = y * bytesPerRow;
      if (rowOffset >= bytes.length) continue;

      final isTopHalf = y < halfHeight;
      final maskRowOffset = useMask ? (y * maskScaleY).floor() * maskWidth : 0;

      for (var x = 0; x < width; x += step) {
        final index = rowOffset + x;
        if (index >= bytes.length) continue;

        final value = bytes[index];

        if (x < halfWidth) {
          leftSum += value;
          leftCount++;
        } else {
          rightSum += value;
          rightCount++;
        }
        if (isTopHalf) {
          topSum += value;
          topCount++;
        } else {
          bottomSum += value;
          bottomCount++;
        }

        if (useMask) {
          final maskIndex = maskRowOffset + (x * maskScaleX).floor();
          if (maskIndex >= 0 &&
              maskIndex < maskConfidences.length &&
              maskConfidences[maskIndex] > 0.5) {
            continue;
          }
        }

        if (previousBackgroundValue != null) {
          varianceSum += (value - previousBackgroundValue).abs();
          varianceSamples++;
        }
        previousBackgroundValue = value;
      }
      previousBackgroundValue = null;
    }

    double? lightDirectionDegrees;
    if (leftCount > 0 && rightCount > 0 && topCount > 0 && bottomCount > 0) {
      final horizontalDelta = rightSum / rightCount - leftSum / leftCount;
      final verticalDelta = topSum / topCount - bottomSum / bottomCount;
      if (horizontalDelta.abs() >= 2 || verticalDelta.abs() >= 2) {
        lightDirectionDegrees = _atan2Degrees(verticalDelta, horizontalDelta);
      }
    }

    return _LumaStats(
      lightDirectionDegrees: lightDirectionDegrees,
      backgroundVariance: varianceSamples == 0
          ? null
          : varianceSum / varianceSamples,
    );
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

class _LumaStats {
  const _LumaStats({
    required this.lightDirectionDegrees,
    required this.backgroundVariance,
  });

  final double? lightDirectionDegrees;
  final double? backgroundVariance;
}

class _MaskStats {
  const _MaskStats({
    required this.subjectRatio,
    required this.leftSubjectPixels,
    required this.rightSubjectPixels,
  });

  final double subjectRatio;
  final int leftSubjectPixels;
  final int rightSubjectPixels;
}
