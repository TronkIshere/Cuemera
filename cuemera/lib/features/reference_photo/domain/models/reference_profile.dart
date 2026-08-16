// features/reference_photo/domain/models/reference_profile.dart
import 'dart:ui' show Offset;

class ReferenceProfile {
  const ReferenceProfile({
    required this.imagePath,
    this.bodyRatio,
    this.faceAngleDegrees,
    this.faceAngleXDegrees,
    this.faceAngleZDegrees,
    this.shoulderAngleDegrees,
    this.shoulderBalanceRatio,
    this.shoulderSpanRatio,
    this.bodyYawEstimate,
    this.expression,
    this.smilingProbability,
    this.leftEyeOpenProbability,
    this.rightEyeOpenProbability,
    this.negativeSpaceScore,
    this.symmetryScore,
    this.backgroundClutterCount,
    this.dominantHue,
    this.warmthScore,
    this.overallBrightness,
    this.mouthOpenRatio,
    this.eyeOpenRatio,
    this.poseLandmarkPoints,
    this.faceContourPoints,
    this.faceOvalPoints,
    this.leftEyeContour,
    this.rightEyeContour,
    this.leftEyebrowTopContour,
    this.rightEyebrowTopContour,
    this.upperLipTopContour,
    this.upperLipBottomContour,
    this.lowerLipTopContour,
    this.lowerLipBottomContour,
    this.noseBridgeContour,
    this.noseBottomContour,
    this.imageWidth,
    this.imageHeight,
    this.metricConfidence,
  });

  final String imagePath;
  final double? bodyRatio;
  final double? faceAngleDegrees;
  final double? faceAngleXDegrees;
  final double? faceAngleZDegrees;
  final double? shoulderAngleDegrees;

  final double? shoulderBalanceRatio;
  final double? shoulderSpanRatio;
  final double? bodyYawEstimate;

  final String? expression;
  final double? smilingProbability;
  final double? leftEyeOpenProbability;
  final double? rightEyeOpenProbability;
  final double? negativeSpaceScore;
  final double? symmetryScore;
  final int? backgroundClutterCount;
  final double? dominantHue;
  final double? warmthScore;
  final double? overallBrightness;
  final double? mouthOpenRatio;
  final double? eyeOpenRatio;
  final List<Offset?>? poseLandmarkPoints;

  final List<Offset>? faceContourPoints;

  final List<Offset>? faceOvalPoints;
  final List<Offset>? leftEyeContour;
  final List<Offset>? rightEyeContour;
  final List<Offset>? leftEyebrowTopContour;
  final List<Offset>? rightEyebrowTopContour;
  final List<Offset>? upperLipTopContour;
  final List<Offset>? upperLipBottomContour;
  final List<Offset>? lowerLipTopContour;
  final List<Offset>? lowerLipBottomContour;
  final List<Offset>? noseBridgeContour;
  final List<Offset>? noseBottomContour;

  final double? imageWidth;
  final double? imageHeight;

  /// Per-metric confidence in [0, 1], keyed by field name — same idiom as
  /// SubjectProfile.metricConfidence, populated by
  /// ReferenceImageAnalyzer from core/pose/landmark_gate.dart's per-landmark
  /// trust. A metric with no entry has no known confidence signal yet.
  final Map<String, double>? metricConfidence;

  double confidenceFor(String metric) => metricConfidence?[metric] ?? 1.0;

  ReferenceProfile copyWith({
    String? imagePath,
    double? bodyRatio,
    double? faceAngleDegrees,
    double? faceAngleXDegrees,
    double? faceAngleZDegrees,
    double? shoulderAngleDegrees,
    double? shoulderBalanceRatio,
    double? shoulderSpanRatio,
    double? bodyYawEstimate,
    String? expression,
    double? smilingProbability,
    double? leftEyeOpenProbability,
    double? rightEyeOpenProbability,
    double? negativeSpaceScore,
    double? symmetryScore,
    int? backgroundClutterCount,
    double? dominantHue,
    double? warmthScore,
    double? overallBrightness,
    double? mouthOpenRatio,
    double? eyeOpenRatio,
    List<Offset?>? poseLandmarkPoints,
    List<Offset>? faceContourPoints,
    List<Offset>? faceOvalPoints,
    List<Offset>? leftEyeContour,
    List<Offset>? rightEyeContour,
    List<Offset>? leftEyebrowTopContour,
    List<Offset>? rightEyebrowTopContour,
    List<Offset>? upperLipTopContour,
    List<Offset>? upperLipBottomContour,
    List<Offset>? lowerLipTopContour,
    List<Offset>? lowerLipBottomContour,
    List<Offset>? noseBridgeContour,
    List<Offset>? noseBottomContour,
    double? imageWidth,
    double? imageHeight,
    Map<String, double>? metricConfidence,
  }) {
    return ReferenceProfile(
      imagePath: imagePath ?? this.imagePath,
      bodyRatio: bodyRatio ?? this.bodyRatio,
      faceAngleDegrees: faceAngleDegrees ?? this.faceAngleDegrees,
      faceAngleXDegrees: faceAngleXDegrees ?? this.faceAngleXDegrees,
      faceAngleZDegrees: faceAngleZDegrees ?? this.faceAngleZDegrees,
      shoulderAngleDegrees: shoulderAngleDegrees ?? this.shoulderAngleDegrees,
      shoulderBalanceRatio: shoulderBalanceRatio ?? this.shoulderBalanceRatio,
      shoulderSpanRatio: shoulderSpanRatio ?? this.shoulderSpanRatio,
      bodyYawEstimate: bodyYawEstimate ?? this.bodyYawEstimate,
      expression: expression ?? this.expression,
      smilingProbability: smilingProbability ?? this.smilingProbability,
      leftEyeOpenProbability:
          leftEyeOpenProbability ?? this.leftEyeOpenProbability,
      rightEyeOpenProbability:
          rightEyeOpenProbability ?? this.rightEyeOpenProbability,
      negativeSpaceScore: negativeSpaceScore ?? this.negativeSpaceScore,
      symmetryScore: symmetryScore ?? this.symmetryScore,
      backgroundClutterCount:
          backgroundClutterCount ?? this.backgroundClutterCount,
      dominantHue: dominantHue ?? this.dominantHue,
      warmthScore: warmthScore ?? this.warmthScore,
      overallBrightness: overallBrightness ?? this.overallBrightness,
      mouthOpenRatio: mouthOpenRatio ?? this.mouthOpenRatio,
      eyeOpenRatio: eyeOpenRatio ?? this.eyeOpenRatio,
      poseLandmarkPoints: poseLandmarkPoints ?? this.poseLandmarkPoints,
      faceContourPoints: faceContourPoints ?? this.faceContourPoints,
      faceOvalPoints: faceOvalPoints ?? this.faceOvalPoints,
      leftEyeContour: leftEyeContour ?? this.leftEyeContour,
      rightEyeContour: rightEyeContour ?? this.rightEyeContour,
      leftEyebrowTopContour:
          leftEyebrowTopContour ?? this.leftEyebrowTopContour,
      rightEyebrowTopContour:
          rightEyebrowTopContour ?? this.rightEyebrowTopContour,
      upperLipTopContour: upperLipTopContour ?? this.upperLipTopContour,
      upperLipBottomContour:
          upperLipBottomContour ?? this.upperLipBottomContour,
      lowerLipTopContour: lowerLipTopContour ?? this.lowerLipTopContour,
      lowerLipBottomContour:
          lowerLipBottomContour ?? this.lowerLipBottomContour,
      noseBridgeContour: noseBridgeContour ?? this.noseBridgeContour,
      noseBottomContour: noseBottomContour ?? this.noseBottomContour,
      imageWidth: imageWidth ?? this.imageWidth,
      imageHeight: imageHeight ?? this.imageHeight,
      metricConfidence: metricConfidence ?? this.metricConfidence,
    );
  }
}
