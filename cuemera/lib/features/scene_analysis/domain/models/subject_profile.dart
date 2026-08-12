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
    required this.timestamp,
  });

  final double? bodyRatio;
  final double? faceAngleDegrees;
  final double? faceAngleXDegrees;
  final double? faceAngleZDegrees;
  final double? mouthOpenRatio;
  final double? eyeOpenRatio;
  final double? shoulderAngleDegrees;

  // Positive: subject's left shoulder sits lower (larger y) than the right.
  // Negative: right shoulder sits lower. Normalized by shoulder-width in
  // pixels, so it's scale-invariant regardless of distance from camera.
  final double? shoulderBalanceRatio;

  // Shoulder width normalized by torso height (shoulder-midpoint to
  // hip-midpoint distance). Bigger = broader/more spread shoulders
  // relative to torso; smaller = narrower/hunched.
  final double? shoulderSpanRatio;

  // Torso rotation in degrees, derived from ML Kit's experimental
  // shoulder z-depth (less accurate than x/y). Same left/right sign
  // ambiguity as shoulderAngleDegrees/faceAngleZDegrees — unverified on
  // a physical device, see _bodyYawDirectionIsMirrored in
  // ReferenceComparisonEngine.
  final double? bodyYawEstimate;

  final bool? eyesOpen;
  final String? expression;
  final DateTime timestamp;

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
      timestamp: DateTime.now(),
    );
  }
}
