// features/reference_photo/domain/comparison_math.dart
import 'dart:ui';

class ComparisonMath {
  static double deviation(double subjectValue, double referenceValue) {
    return (subjectValue - referenceValue).abs();
  }

  static double oneSidedDeviation(double subjectValue, double referenceValue) {
    final diff = referenceValue - subjectValue;
    return diff <= 0 ? 0.0 : diff;
  }

  static double? relativeDeviation(double subjectValue, double referenceValue) {
    if (referenceValue == 0) return null;
    return (subjectValue - referenceValue).abs() / referenceValue.abs();
  }

  static double circularDeviation(
    double subjectValue,
    double referenceValue,
    double wraparound,
  ) {
    final diff = (subjectValue - referenceValue).abs() % wraparound;
    return diff > wraparound / 2 ? wraparound - diff : diff;
  }

  static double signedCircularDiff(
    double subjectValue,
    double referenceValue,
    double wraparound,
  ) {
    final half = wraparound / 2;
    return ((subjectValue - referenceValue) + half) % wraparound - half;
  }

  static const double maxDeviationForPose = 90.0;
  static const double maxDeviationForPoseRatio = 1.0;
  static const double maxRelativeDeviationForPoseRatio = 1.0;
  static const double maxDeviationForComposition = 1.0;
  static const double maxDeviationForColor = 1.0;
  static const double maxDeviationForHue = 180.0;

  static double thresholdForPose(double poseTolerance) => poseTolerance * 45.0;
  static double thresholdForPoseRatio(double poseTolerance) =>
      poseTolerance * 0.5;
  static double thresholdForRelativePoseRatio(double poseTolerance) =>
      poseTolerance * 0.5;
  static double thresholdForComposition(double compositionTolerance) =>
      compositionTolerance;
  static double thresholdForExpression(double expressionTolerance) =>
      expressionTolerance;
  static double thresholdForColor(double colorTolerance) => colorTolerance;
  static double thresholdForHue(double colorTolerance) =>
      colorTolerance * maxDeviationForHue;

  static double normalizedSeverity(double deviation, double maxDeviation) {
    if (maxDeviation <= 0) return 0.0;
    return (deviation / maxDeviation).clamp(0.0, 1.0);
  }

  static bool exceedsThreshold(double deviation, double threshold) {
    return deviation > threshold;
  }

  static double similarity(
    double deviation,
    double threshold,
    double maxDeviation,
  ) {
    if (deviation <= threshold) return 1.0;
    final remainingRange = maxDeviation - threshold;
    if (remainingRange <= 0) return 0.0;
    return (1.0 - ((deviation - threshold) / remainingRange)).clamp(0.0, 1.0);
  }

  static double? boundingBoxAspectRatio(List<Offset>? points) {
    if (points == null || points.isEmpty) return null;

    var minX = points.first.dx;
    var maxX = points.first.dx;
    var minY = points.first.dy;
    var maxY = points.first.dy;

    for (final point in points) {
      if (point.dx < minX) minX = point.dx;
      if (point.dx > maxX) maxX = point.dx;
      if (point.dy < minY) minY = point.dy;
      if (point.dy > maxY) maxY = point.dy;
    }

    final width = maxX - minX;
    final height = maxY - minY;
    return width == 0 ? null : height / width;
  }
}
