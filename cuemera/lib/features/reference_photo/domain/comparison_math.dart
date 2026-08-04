// features/reference_photo/domain/comparison_math.dart
class ComparisonMath {
  static double deviation(double subjectValue, double referenceValue) {
    return (subjectValue - referenceValue).abs();
  }

  static double? relativeDeviation(double subjectValue, double referenceValue) {
    if (referenceValue == 0) return null;
    return (subjectValue - referenceValue).abs() / referenceValue;
  }

  static const double maxDeviationForPose = 90.0;
  static const double maxDeviationForPoseRatio = 1.0;
  static const double maxDeviationForComposition = 1.0;
  static const double maxDeviationForColor = 1.0;

  static double thresholdForPose(double poseTolerance) => poseTolerance * 45.0;
  static double thresholdForPoseRatio(double poseTolerance) =>
      poseTolerance * 0.5;
  static double thresholdForComposition(double compositionTolerance) =>
      compositionTolerance;
  static double thresholdForExpression(double expressionTolerance) =>
      expressionTolerance;
  static double thresholdForColor(double colorTolerance) => colorTolerance;

  static double normalizedSeverity(double deviation, double maxDeviation) {
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
}
