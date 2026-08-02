// features/scene_analysis/domain/models/subject_profile.dart
class SubjectProfile {
  const SubjectProfile({
    this.bodyRatio,
    this.faceAngleDegrees,
    this.shoulderAngleDegrees,
    this.eyesOpen,
    this.expression,
    required this.timestamp,
  });

  final double? bodyRatio;
  final double? faceAngleDegrees;
  final double? shoulderAngleDegrees;
  final bool? eyesOpen;
  final String? expression;
  final DateTime timestamp;

  SubjectProfile copyWith({
    double? bodyRatio,
    double? faceAngleDegrees,
    double? shoulderAngleDegrees,
    bool? eyesOpen,
    String? expression,
  }) {
    return SubjectProfile(
      bodyRatio: bodyRatio ?? this.bodyRatio,
      faceAngleDegrees: faceAngleDegrees ?? this.faceAngleDegrees,
      shoulderAngleDegrees: shoulderAngleDegrees ?? this.shoulderAngleDegrees,
      eyesOpen: eyesOpen ?? this.eyesOpen,
      expression: expression ?? this.expression,
      timestamp: DateTime.now(),
    );
  }
}
