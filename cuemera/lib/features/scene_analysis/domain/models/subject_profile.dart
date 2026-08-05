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
  final bool? eyesOpen;
  final String? expression;
  final DateTime timestamp;

  SubjectProfile copyWith({
    double? bodyRatio,
    double? faceAngleDegrees,
    double? faceAngleXDegrees,
    double? faceAngleZDegrees,
    double? mouthOpenRatio,
    double? eyeOpenRatio,
    double? shoulderAngleDegrees,
    bool? eyesOpen,
    String? expression,
  }) {
    return SubjectProfile(
      bodyRatio: bodyRatio ?? this.bodyRatio,
      faceAngleDegrees: faceAngleDegrees ?? this.faceAngleDegrees,
      faceAngleXDegrees: faceAngleXDegrees ?? this.faceAngleXDegrees,
      faceAngleZDegrees: faceAngleZDegrees ?? this.faceAngleZDegrees,
      mouthOpenRatio: mouthOpenRatio ?? this.mouthOpenRatio,
      eyeOpenRatio: eyeOpenRatio ?? this.eyeOpenRatio,
      shoulderAngleDegrees: shoulderAngleDegrees ?? this.shoulderAngleDegrees,
      eyesOpen: eyesOpen ?? this.eyesOpen,
      expression: expression ?? this.expression,
      timestamp: DateTime.now(),
    );
  }
}
