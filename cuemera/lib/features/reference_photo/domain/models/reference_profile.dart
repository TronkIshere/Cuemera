// features/reference_photo/domain/models/reference_profile.dart
class ReferenceProfile {
  const ReferenceProfile({
    required this.imagePath,
    this.bodyRatio,
    this.faceAngleDegrees,
    this.shoulderAngleDegrees,
    this.expression,
    this.negativeSpaceScore,
    this.symmetryScore,
    this.backgroundClutterCount,
    this.dominantHue,
    this.warmthScore,
    this.overallBrightness,
  });

  final String imagePath;
  final double? bodyRatio;
  final double? faceAngleDegrees;
  final double? shoulderAngleDegrees;
  final String? expression;
  final double? negativeSpaceScore;
  final double? symmetryScore;
  final int? backgroundClutterCount;
  final double? dominantHue;
  final double? warmthScore;
  final double? overallBrightness;

  ReferenceProfile copyWith({
    String? imagePath,
    double? bodyRatio,
    double? faceAngleDegrees,
    double? shoulderAngleDegrees,
    String? expression,
    double? negativeSpaceScore,
    double? symmetryScore,
    int? backgroundClutterCount,
    double? dominantHue,
    double? warmthScore,
    double? overallBrightness,
  }) {
    return ReferenceProfile(
      imagePath: imagePath ?? this.imagePath,
      bodyRatio: bodyRatio ?? this.bodyRatio,
      faceAngleDegrees: faceAngleDegrees ?? this.faceAngleDegrees,
      shoulderAngleDegrees: shoulderAngleDegrees ?? this.shoulderAngleDegrees,
      expression: expression ?? this.expression,
      negativeSpaceScore: negativeSpaceScore ?? this.negativeSpaceScore,
      symmetryScore: symmetryScore ?? this.symmetryScore,
      backgroundClutterCount:
          backgroundClutterCount ?? this.backgroundClutterCount,
      dominantHue: dominantHue ?? this.dominantHue,
      warmthScore: warmthScore ?? this.warmthScore,
      overallBrightness: overallBrightness ?? this.overallBrightness,
    );
  }
}
