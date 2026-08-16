// features/scene_analysis/domain/models/subject_profile.dart
class SubjectProfile {
  const SubjectProfile({
    this.bodyRatio,
    this.faceAngleDegrees,
    this.faceAngleXDegrees,
    this.faceAngleZDegrees,
    this.mouthOpenRatio,
    this.eyeOpenRatio,
    this.shoulderAngleDegrees,
    this.shoulderBalanceRatio,
    this.shoulderSpanRatio,
    this.bodyYawEstimate,
    this.eyesOpen,
    this.expression,
    this.metricConfidence,
    this.metricTemporalEligibility,
    this.subjectFullyInFrame,
    this.detectorsAgree,
    required this.timestamp,
  });

  final double? bodyRatio;
  final double? faceAngleDegrees;
  final double? faceAngleXDegrees;
  final double? faceAngleZDegrees;
  final double? mouthOpenRatio;
  final double? eyeOpenRatio;
  final double? shoulderAngleDegrees;

  final double? shoulderBalanceRatio;

  final double? shoulderSpanRatio;

  final double? bodyYawEstimate;

  final bool? eyesOpen;
  final String? expression;
  final DateTime timestamp;

  final Map<String, double>? metricConfidence;
  final Map<String, bool>? metricTemporalEligibility;
  final bool? subjectFullyInFrame;
  final bool? detectorsAgree;

  double confidenceFor(String metric) => metricConfidence?[metric] ?? 1.0;

  bool temporallyEligibleFor(String metric) =>
      metricTemporalEligibility?[metric] ?? true;

  static const Object _unset = Object();

  SubjectProfile copyWith({
    Object? bodyRatio = _unset,
    Object? faceAngleDegrees = _unset,
    Object? faceAngleXDegrees = _unset,
    Object? faceAngleZDegrees = _unset,
    Object? mouthOpenRatio = _unset,
    Object? eyeOpenRatio = _unset,
    Object? shoulderAngleDegrees = _unset,
    Object? shoulderBalanceRatio = _unset,
    Object? shoulderSpanRatio = _unset,
    Object? bodyYawEstimate = _unset,
    Object? eyesOpen = _unset,
    Object? expression = _unset,
    Object? metricConfidence = _unset,
    Object? metricTemporalEligibility = _unset,
    Object? subjectFullyInFrame = _unset,
    Object? detectorsAgree = _unset,
  }) {
    return SubjectProfile(
      bodyRatio: identical(bodyRatio, _unset)
          ? this.bodyRatio
          : bodyRatio as double?,
      faceAngleDegrees: identical(faceAngleDegrees, _unset)
          ? this.faceAngleDegrees
          : faceAngleDegrees as double?,
      faceAngleXDegrees: identical(faceAngleXDegrees, _unset)
          ? this.faceAngleXDegrees
          : faceAngleXDegrees as double?,
      faceAngleZDegrees: identical(faceAngleZDegrees, _unset)
          ? this.faceAngleZDegrees
          : faceAngleZDegrees as double?,
      mouthOpenRatio: identical(mouthOpenRatio, _unset)
          ? this.mouthOpenRatio
          : mouthOpenRatio as double?,
      eyeOpenRatio: identical(eyeOpenRatio, _unset)
          ? this.eyeOpenRatio
          : eyeOpenRatio as double?,
      shoulderAngleDegrees: identical(shoulderAngleDegrees, _unset)
          ? this.shoulderAngleDegrees
          : shoulderAngleDegrees as double?,
      shoulderBalanceRatio: identical(shoulderBalanceRatio, _unset)
          ? this.shoulderBalanceRatio
          : shoulderBalanceRatio as double?,
      shoulderSpanRatio: identical(shoulderSpanRatio, _unset)
          ? this.shoulderSpanRatio
          : shoulderSpanRatio as double?,
      bodyYawEstimate: identical(bodyYawEstimate, _unset)
          ? this.bodyYawEstimate
          : bodyYawEstimate as double?,
      eyesOpen: identical(eyesOpen, _unset) ? this.eyesOpen : eyesOpen as bool?,
      expression: identical(expression, _unset)
          ? this.expression
          : expression as String?,
      metricConfidence: identical(metricConfidence, _unset)
          ? this.metricConfidence
          : metricConfidence as Map<String, double>?,
      metricTemporalEligibility: identical(metricTemporalEligibility, _unset)
          ? this.metricTemporalEligibility
          : metricTemporalEligibility as Map<String, bool>?,
      subjectFullyInFrame: identical(subjectFullyInFrame, _unset)
          ? this.subjectFullyInFrame
          : subjectFullyInFrame as bool?,
      detectorsAgree: identical(detectorsAgree, _unset)
          ? this.detectorsAgree
          : detectorsAgree as bool?,
      timestamp: DateTime.now(),
    );
  }
}
