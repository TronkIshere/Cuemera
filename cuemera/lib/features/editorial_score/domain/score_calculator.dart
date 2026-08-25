// features/editorial_score/domain/score_calculator.dart
import '../../../core/analysis/analysis_constants.dart';
import '../../reference_photo/domain/comparison_math.dart';
import '../../reference_photo/domain/models/reference_profile.dart';
import '../../reference_photo/domain/models/tolerance_settings.dart';
import '../../scene_analysis/domain/models/scene_profile.dart';
import '../../scene_analysis/domain/models/subject_profile.dart';

class EditorialScore {
  const EditorialScore({
    required this.overall,
    required this.breakdown,
    this.nextSuggestion,
  });

  final int overall;
  final Map<String, int> breakdown;
  final String? nextSuggestion;

  Map<String, dynamic> toMap() {
    return {
      'overall': overall,
      'breakdown': breakdown,
      'nextSuggestion': nextSuggestion,
    };
  }

  factory EditorialScore.fromMap(Map<String, dynamic> map) {
    return EditorialScore(
      overall: map['overall'] as int,
      breakdown: Map<String, int>.from(map['breakdown'] as Map),
      nextSuggestion: map['nextSuggestion'] as String?,
    );
  }
}

EditorialScore calculateReferenceScore(
  SubjectProfile subject,
  SceneProfile scene,
  ReferenceProfile reference,
  ToleranceSettings tolerance,
) {
  final breakdown = <String, int>{};

  final composition = _compositionScore(scene, reference, tolerance);
  if (composition != null) breakdown['composition'] = composition;

  final lighting = _lightingScore(scene, reference, tolerance);
  if (lighting != null) breakdown['lighting'] = lighting;

  final expression = _expressionScore(subject, reference, tolerance);
  if (expression != null) breakdown['expression'] = expression;

  final background = _backgroundScore(scene, reference, tolerance);
  if (background != null) breakdown['background'] = background;

  final story = _storyScore(scene);
  if (story != null) breakdown['story'] = story;

  if (breakdown.isEmpty) {
    return const EditorialScore(overall: 0, breakdown: {});
  }

  final average = breakdown.values.reduce((a, b) => a + b) / breakdown.length;
  final overall = average.round().clamp(0, 100);

  String? suggestion;
  final lowest = breakdown.entries.reduce((a, b) => a.value < b.value ? a : b);
  if (lowest.value < 60) {
    suggestion = 'Improve ${lowest.key}';
  }

  return EditorialScore(
    overall: overall,
    breakdown: breakdown,
    nextSuggestion: suggestion,
  );
}

int? _storyScore(SceneProfile scene) {
  final depthEstimate = scene.depthEstimate;
  if (depthEstimate == null) return null;
  return (depthEstimate.clamp(0.0, 1.0) * 100).round();
}

int? _backgroundScore(
  SceneProfile scene,
  ReferenceProfile reference,
  ToleranceSettings tolerance,
) {
  final refBackgroundClutter = reference.backgroundClutterCount;
  final sceneClutterNormalized = normalizeClutterCount(
    scene.backgroundClutterCount,
  );

  if (refBackgroundClutter == null) {
    return ((1.0 - sceneClutterNormalized) * 100).round().clamp(0, 100);
  }

  final deviation = ComparisonMath.deviation(
    sceneClutterNormalized,
    normalizeClutterCount(refBackgroundClutter),
  );
  final similarity = ComparisonMath.similarity(
    deviation,
    ComparisonMath.thresholdForComposition(tolerance.compositionTolerance),
    ComparisonMath.maxDeviationForComposition,
  );
  return (similarity * 100).round().clamp(0, 100);
}

int? _compositionScore(
  SceneProfile scene,
  ReferenceProfile reference,
  ToleranceSettings tolerance,
) {
  final refNegativeSpace = reference.negativeSpaceScore;
  final refSymmetry = reference.symmetryScore;

  if (refNegativeSpace == null && refSymmetry == null) return null;

  final thresholdForComposition = ComparisonMath.thresholdForComposition(
    tolerance.compositionTolerance,
  );

  double sum = 0;
  int count = 0;

  if (refNegativeSpace != null) {
    sum += ComparisonMath.similarity(
      ComparisonMath.deviation(scene.negativeSpaceScore, refNegativeSpace),
      thresholdForComposition,
      ComparisonMath.maxDeviationForComposition,
    );
    count++;
  }

  if (refSymmetry != null) {
    sum += ComparisonMath.similarity(
      ComparisonMath.oneSidedDeviation(scene.symmetryScore, refSymmetry),
      thresholdForComposition,
      ComparisonMath.maxDeviationForComposition,
    );
    count++;
  }

  return ((sum / count) * 100).round().clamp(0, 100);
}

int? _lightingScore(
  SceneProfile scene,
  ReferenceProfile reference,
  ToleranceSettings tolerance,
) {
  final refBrightness = reference.overallBrightness;
  if (refBrightness == null) return null;

  final thresholdForColor = ComparisonMath.thresholdForColor(
    tolerance.colorTolerance,
  );

  double sum = ComparisonMath.similarity(
    ComparisonMath.deviation(scene.brightness, refBrightness),
    thresholdForColor,
    ComparisonMath.maxDeviationForColor,
  );
  int count = 1;

  final refWarmth = reference.warmthScore;
  final sceneWarmth = scene.liveWarmthScore;
  if (refWarmth != null && sceneWarmth != null) {
    sum += ComparisonMath.similarity(
      ComparisonMath.deviation(sceneWarmth, refWarmth),
      thresholdForColor,
      ComparisonMath.maxDeviationForColor,
    );
    count++;
  }

  final refHue = reference.dominantHue;
  final sceneHue = scene.liveDominantHue;
  if (refHue != null && sceneHue != null) {
    sum += ComparisonMath.similarity(
      ComparisonMath.circularDeviation(sceneHue, refHue, 360.0),
      ComparisonMath.thresholdForHue(tolerance.colorTolerance),
      ComparisonMath.maxDeviationForHue,
    );
    count++;
  }

  return ((sum / count) * 100).round().clamp(0, 100);
}

int? _expressionScore(
  SubjectProfile subject,
  ReferenceProfile reference,
  ToleranceSettings tolerance,
) {
  final refExpression = reference.expression;
  if (refExpression == null) return null;
  if (subject.expression == null) return null;

  final matches = subject.expression == refExpression;
  final similarity = ComparisonMath.similarity(
    matches ? 0.0 : 1.0,
    ComparisonMath.thresholdForExpression(tolerance.expressionTolerance),
    1.0,
  );

  return (similarity * 100).round().clamp(0, 100);
}
