// features/editorial_score/domain/score_calculator.dart
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
}

EditorialScore calculateReferenceScore(
  SubjectProfile subject,
  SceneProfile scene,
  ReferenceProfile reference,
  ToleranceSettings tolerance,
) {
  final composition = _compositionScore(scene, reference, tolerance);
  final lighting = _lightingScore(scene, reference, tolerance);
  final expression = _expressionScore(subject, reference, tolerance);

  final refBackgroundClutter = reference.backgroundClutterCount;
  int background;
  if (refBackgroundClutter != null) {
    final sceneClutterNormalized = (scene.backgroundClutterCount / 10).clamp(
      0.0,
      1.0,
    );
    final refClutterNormalized = (refBackgroundClutter / 10).clamp(0.0, 1.0);
    final deviation = ComparisonMath.deviation(
      sceneClutterNormalized,
      refClutterNormalized,
    );
    background = ((1.0 - deviation).clamp(0.0, 1.0) * 100).round();
  } else {
    final backgroundRaw =
        1.0 - (scene.backgroundClutterCount / 10).clamp(0.0, 1.0);
    background = (backgroundRaw * 100).round();
  }

  final depthFactor = scene.depthEstimate != null ? 1.0 : 0.7;
  final story = (depthFactor * 75).round();

  final breakdown = {
    'composition': composition,
    'lighting': lighting,
    'expression': expression,
    'background': background,
    'story': story,
  };

  const weights = {
    'composition': 0.2,
    'lighting': 0.2,
    'expression': 0.2,
    'background': 0.2,
    'story': 0.2,
  };

  double weightedSum = 0;
  for (final entry in breakdown.entries) {
    weightedSum += entry.value * (weights[entry.key] ?? 0.2);
  }

  final overall = weightedSum.round().clamp(0, 100);

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

int _compositionScore(
  SceneProfile scene,
  ReferenceProfile reference,
  ToleranceSettings tolerance,
) {
  final refNegativeSpace = reference.negativeSpaceScore;
  final refSymmetry = reference.symmetryScore;
  final refBackgroundClutter = reference.backgroundClutterCount;

  if (refNegativeSpace == null &&
      refSymmetry == null &&
      refBackgroundClutter == null) {
    return ((scene.negativeSpaceScore * 0.5 + scene.symmetryScore * 0.5) * 100)
        .round()
        .clamp(0, 100);
  }

  final thresholdForComposition = ComparisonMath.thresholdForComposition(
    tolerance.compositionTolerance,
  );

  double sum = 0;
  int count = 0;

  if (refNegativeSpace != null) {
    final deviation = ComparisonMath.deviation(
      scene.negativeSpaceScore,
      refNegativeSpace,
    );
    sum += ComparisonMath.similarity(
      deviation,
      thresholdForComposition,
      ComparisonMath.maxDeviationForComposition,
    );
    count++;
  }

  if (refSymmetry != null) {
    final deviation = (refSymmetry - scene.symmetryScore).clamp(0.0, 1.0);
    sum += ComparisonMath.similarity(
      deviation,
      thresholdForComposition,
      ComparisonMath.maxDeviationForComposition,
    );
    count++;
  }

  if (refBackgroundClutter != null) {
    final sceneClutterNormalized = (scene.backgroundClutterCount / 10).clamp(
      0.0,
      1.0,
    );
    final refClutterNormalized = (refBackgroundClutter / 10).clamp(0.0, 1.0);
    final deviation = ComparisonMath.deviation(
      sceneClutterNormalized,
      refClutterNormalized,
    );
    sum += ComparisonMath.similarity(
      deviation,
      thresholdForComposition,
      ComparisonMath.maxDeviationForComposition,
    );
    count++;
  }

  return ((sum / count) * 100).round().clamp(0, 100);
}

int _lightingScore(
  SceneProfile scene,
  ReferenceProfile reference,
  ToleranceSettings tolerance,
) {
  final refBrightness = reference.overallBrightness;

  if (refBrightness == null) {
    final lightingRaw = 1.0 - (scene.brightness - 0.55).abs() * 2;
    return (lightingRaw.clamp(0.0, 1.0) * 100).round();
  }

  final deviation = ComparisonMath.deviation(scene.brightness, refBrightness);
  final thresholdForColor = ComparisonMath.thresholdForColor(
    tolerance.colorTolerance,
  );
  final brightnessSimilarity = ComparisonMath.similarity(
    deviation,
    thresholdForColor,
    ComparisonMath.maxDeviationForColor,
  );

  final refWarmth = reference.warmthScore;
  final sceneWarmth = scene.liveWarmthScore;
  final refHue = reference.dominantHue;
  final sceneHue = scene.liveDominantHue;

  double sum = brightnessSimilarity;
  int count = 1;

  if (refWarmth != null && sceneWarmth != null) {
    final warmthDeviation = ComparisonMath.deviation(sceneWarmth, refWarmth);
    sum += ComparisonMath.similarity(
      warmthDeviation,
      thresholdForColor,
      ComparisonMath.maxDeviationForColor,
    );
    count++;
  }

  if (refHue != null && sceneHue != null) {
    final hueDeviation = ComparisonMath.circularDeviation(
      sceneHue,
      refHue,
      360.0,
    );
    final thresholdForHue = ComparisonMath.thresholdForHue(
      tolerance.colorTolerance,
    );
    sum += ComparisonMath.similarity(
      hueDeviation,
      thresholdForHue,
      ComparisonMath.maxDeviationForHue,
    );
    count++;
  }

  return ((sum / count) * 100).round().clamp(0, 100);
}

int _expressionScore(
  SubjectProfile subject,
  ReferenceProfile reference,
  ToleranceSettings tolerance,
) {
  final refExpression = reference.expression;

  if (refExpression == null) {
    int expression = 60;
    if (subject.expression == 'smiling') expression = 90;
    if (subject.expression == 'serious') expression = 55;
    if (subject.eyesOpen == false) expression = 20;
    return expression;
  }

  final matches = subject.expression == refExpression;
  final deviation = matches ? 0.0 : 1.0;
  final thresholdForExpression = ComparisonMath.thresholdForExpression(
    tolerance.expressionTolerance,
  );
  final similarity = ComparisonMath.similarity(
    deviation,
    thresholdForExpression,
    1.0,
  );

  return (similarity * 100).round().clamp(0, 100);
}
