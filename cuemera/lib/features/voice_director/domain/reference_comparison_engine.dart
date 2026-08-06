// features/voice_director/domain/reference_comparison_engine.dart
import '../../reference_photo/domain/comparison_math.dart';
import '../../reference_photo/domain/models/reference_profile.dart';
import '../../reference_photo/domain/models/tolerance_settings.dart';
import '../../scene_analysis/domain/models/scene_profile.dart';
import '../../scene_analysis/domain/models/subject_profile.dart';
import 'priority_engine.dart';

/// Picks a phrase variant scaled to how far off the attribute is.
/// [severity] is 0..10 (see ComparisonMath.normalizedSeverity * 10).
/// Mild/moderate/strong tiers keep the coaching specific to how far off
/// the subject actually is, instead of one fixed sentence regardless of
/// deviation size.
String _tieredPhrase(int severity, List<String> tiers) {
  assert(tiers.length == 3, 'Expected [mild, moderate, strong] phrases');
  if (severity <= 3) return tiers[0];
  if (severity <= 7) return tiers[1];
  return tiers[2];
}

class ReferenceComparisonEngine {
  PriorityAction? evaluate({
    required SubjectProfile subject,
    required SceneProfile scene,
    required ReferenceProfile reference,
    required ToleranceSettings tolerance,
  }) {
    final candidates = <_AttributeEvaluation>[];

    final shoulderEvaluation = _evaluateShoulderAngle(
      subject,
      reference,
      tolerance,
    );
    if (shoulderEvaluation != null) candidates.add(shoulderEvaluation);

    final bodyRatioEvaluation = _evaluateBodyRatio(
      subject,
      reference,
      tolerance,
    );
    if (bodyRatioEvaluation != null) candidates.add(bodyRatioEvaluation);

    final expressionEvaluation = _evaluateExpression(
      subject,
      reference,
      tolerance,
    );
    if (expressionEvaluation != null) candidates.add(expressionEvaluation);

    final negativeSpaceEvaluation = _evaluateNegativeSpace(
      scene,
      reference,
      tolerance,
    );
    if (negativeSpaceEvaluation != null)
      candidates.add(negativeSpaceEvaluation);

    final symmetryEvaluation = _evaluateSymmetry(scene, reference, tolerance);
    if (symmetryEvaluation != null) candidates.add(symmetryEvaluation);

    final brightnessEvaluation = _evaluateBrightness(
      scene,
      reference,
      tolerance,
    );
    if (brightnessEvaluation != null) candidates.add(brightnessEvaluation);

    final backgroundClutterEvaluation = _evaluateBackgroundClutter(
      scene,
      reference,
      tolerance,
    );
    if (backgroundClutterEvaluation != null)
      candidates.add(backgroundClutterEvaluation);

    final exceeding = candidates
        .where((candidate) => candidate.deviationExceedsThreshold)
        .toList();

    if (exceeding.isEmpty) return null;

    exceeding.sort((a, b) => b.severity.compareTo(a.severity));
    final worst = exceeding.first;

    return PriorityAction(
      phrase: worst.phrase,
      severity: worst.severity,
      sourceLayer: 'reference_comparison_engine',
    );
  }

  _AttributeEvaluation? _evaluateShoulderAngle(
    SubjectProfile subject,
    ReferenceProfile reference,
    ToleranceSettings tolerance,
  ) {
    final subjectValue = subject.shoulderAngleDegrees;
    final referenceValue = reference.shoulderAngleDegrees;
    if (subjectValue == null || referenceValue == null) return null;

    final deviation = ComparisonMath.deviation(subjectValue, referenceValue);
    final normalizedSeverity = ComparisonMath.normalizedSeverity(
      deviation,
      ComparisonMath.maxDeviationForPose,
    );
    final thresholdForPose = ComparisonMath.thresholdForPose(
      tolerance.poseTolerance,
    );
    final deviationExceedsThreshold = ComparisonMath.exceedsThreshold(
      deviation,
      thresholdForPose,
    );

    final severity = (normalizedSeverity * 10).round();
    final phrase = subjectValue > referenceValue
        ? _tieredPhrase(severity, const [
            'Square your shoulders just a touch',
            'Square your shoulders more',
            "Square your shoulders a lot more — they're quite off",
          ])
        : _tieredPhrase(severity, const [
            'Angle your shoulders slightly, like the reference',
            'Angle your shoulders like the reference',
            'Angle your shoulders much more, like the reference',
          ]);

    return _AttributeEvaluation(
      severity: severity,
      deviationExceedsThreshold: deviationExceedsThreshold,
      phrase: phrase,
    );
  }

  _AttributeEvaluation? _evaluateBodyRatio(
    SubjectProfile subject,
    ReferenceProfile reference,
    ToleranceSettings tolerance,
  ) {
    final subjectValue = subject.bodyRatio;
    final referenceValue = reference.bodyRatio;
    if (subjectValue == null || referenceValue == null) return null;

    final deviation = ComparisonMath.relativeDeviation(
      subjectValue,
      referenceValue,
    );
    if (deviation == null) return null;

    final normalizedSeverity = ComparisonMath.normalizedSeverity(
      deviation,
      ComparisonMath.maxDeviationForPoseRatio,
    );
    final thresholdForPose = ComparisonMath.thresholdForPoseRatio(
      tolerance.poseTolerance,
    );
    final deviationExceedsThreshold = ComparisonMath.exceedsThreshold(
      deviation,
      thresholdForPose,
    );

    final severity = (normalizedSeverity * 10).round();
    final phrase = _tieredPhrase(severity, const [
      'Adjust your framing slightly to match the reference',
      'Match your framing to the reference photo',
      "Reframe quite a bit — you're far from the reference's framing",
    ]);

    return _AttributeEvaluation(
      severity: severity,
      deviationExceedsThreshold: deviationExceedsThreshold,
      phrase: phrase,
    );
  }

  _AttributeEvaluation? _evaluateExpression(
    SubjectProfile subject,
    ReferenceProfile reference,
    ToleranceSettings tolerance,
  ) {
    final subjectValue = subject.expression;
    final referenceValue = reference.expression;
    if (subjectValue == null || referenceValue == null) return null;

    final matches = subjectValue == referenceValue;
    final deviation = matches ? 0.0 : 1.0;
    final thresholdForExpression = ComparisonMath.thresholdForExpression(
      tolerance.expressionTolerance,
    );
    final deviationExceedsThreshold = ComparisonMath.exceedsThreshold(
      deviation,
      thresholdForExpression,
    );

    // Expression match is binary (0.0 or 1.0), so severity only ever lands
    // in the "strong" tier when it doesn't match — one phrase is enough,
    // but kept as a tiered call for consistency with the other evaluators
    // and to make future severity-aware phrasing (e.g. partial-match
    // scoring from a learned classifier) a drop-in change.
    final severity = (deviation * 10).round();
    final phrase = _tieredPhrase(severity, const [
      'Match the expression in your reference photo',
      'Match the expression in your reference photo',
      'Match the expression in your reference photo more closely',
    ]);

    return _AttributeEvaluation(
      severity: severity,
      deviationExceedsThreshold: deviationExceedsThreshold,
      phrase: phrase,
    );
  }

  _AttributeEvaluation? _evaluateNegativeSpace(
    SceneProfile scene,
    ReferenceProfile reference,
    ToleranceSettings tolerance,
  ) {
    final subjectValue = scene.negativeSpaceScore;
    final referenceValue = reference.negativeSpaceScore;
    if (referenceValue == null) return null;

    final deviation = ComparisonMath.deviation(subjectValue, referenceValue);
    final normalizedSeverity = ComparisonMath.normalizedSeverity(
      deviation,
      ComparisonMath.maxDeviationForComposition,
    );
    final thresholdForComposition = ComparisonMath.thresholdForComposition(
      tolerance.compositionTolerance,
    );
    final deviationExceedsThreshold = ComparisonMath.exceedsThreshold(
      deviation,
      thresholdForComposition,
    );

    final severity = (normalizedSeverity * 10).round();
    final phrase = subjectValue > referenceValue
        ? _tieredPhrase(severity, const [
            'Fill the frame a little more, like your reference',
            'Fill the frame more, like your reference',
            'Fill the frame a lot more, like your reference',
          ])
        : _tieredPhrase(severity, const [
            'Give a little more space in the frame, like your reference',
            'Give more space in the frame, like your reference',
            'Give a lot more space in the frame, like your reference',
          ]);

    return _AttributeEvaluation(
      severity: severity,
      deviationExceedsThreshold: deviationExceedsThreshold,
      phrase: phrase,
    );
  }

  _AttributeEvaluation? _evaluateSymmetry(
    SceneProfile scene,
    ReferenceProfile reference,
    ToleranceSettings tolerance,
  ) {
    final subjectValue = scene.symmetryScore;
    final referenceValue = reference.symmetryScore;
    if (referenceValue == null) return null;

    final deviation = (referenceValue - subjectValue).clamp(0.0, 1.0);
    final normalizedSeverity = ComparisonMath.normalizedSeverity(
      deviation,
      ComparisonMath.maxDeviationForComposition,
    );
    final thresholdForComposition = ComparisonMath.thresholdForComposition(
      tolerance.compositionTolerance,
    );
    final deviationExceedsThreshold = ComparisonMath.exceedsThreshold(
      deviation,
      thresholdForComposition,
    );

    final severity = (normalizedSeverity * 10).round();
    final phrase = _tieredPhrase(severity, const [
      'Center yourself a bit more, like the reference',
      'Center yourself like the reference',
      "Center yourself a lot more — you're quite off to one side",
    ]);

    return _AttributeEvaluation(
      severity: severity,
      deviationExceedsThreshold: deviationExceedsThreshold,
      phrase: phrase,
    );
  }

  _AttributeEvaluation? _evaluateBrightness(
    SceneProfile scene,
    ReferenceProfile reference,
    ToleranceSettings tolerance,
  ) {
    final subjectValue = scene.brightness;
    final referenceValue = reference.overallBrightness;
    if (referenceValue == null) return null;

    final deviation = ComparisonMath.deviation(subjectValue, referenceValue);
    final normalizedSeverity = ComparisonMath.normalizedSeverity(
      deviation,
      ComparisonMath.maxDeviationForColor,
    );
    final thresholdForColor = ComparisonMath.thresholdForColor(
      tolerance.colorTolerance,
    );
    final deviationExceedsThreshold = ComparisonMath.exceedsThreshold(
      deviation,
      thresholdForColor,
    );

    final severity = (normalizedSeverity * 10).round();
    final phrase = subjectValue > referenceValue
        ? _tieredPhrase(severity, const [
            'Move to slightly softer light, like your reference',
            'Move to softer light, like your reference',
            'Move to much softer light, like your reference',
          ])
        : _tieredPhrase(severity, const [
            'Find a little more light, like your reference',
            'Find more light, like your reference',
            'Find a lot more light, like your reference',
          ]);

    return _AttributeEvaluation(
      severity: severity,
      deviationExceedsThreshold: deviationExceedsThreshold,
      phrase: phrase,
    );
  }

  _AttributeEvaluation? _evaluateBackgroundClutter(
    SceneProfile scene,
    ReferenceProfile reference,
    ToleranceSettings tolerance,
  ) {
    final referenceValue = reference.backgroundClutterCount;
    if (referenceValue == null) return null;

    final subjectValue = (scene.backgroundClutterCount / 10).clamp(0.0, 1.0);
    final normalizedReferenceValue = (referenceValue / 10).clamp(0.0, 1.0);

    final deviation = ComparisonMath.deviation(
      subjectValue,
      normalizedReferenceValue,
    );
    final normalizedSeverity = ComparisonMath.normalizedSeverity(
      deviation,
      ComparisonMath.maxDeviationForComposition,
    );
    final thresholdForComposition = ComparisonMath.thresholdForComposition(
      tolerance.compositionTolerance,
    );
    final deviationExceedsThreshold = ComparisonMath.exceedsThreshold(
      deviation,
      thresholdForComposition,
    );

    final severity = (normalizedSeverity * 10).round();
    final phrase = subjectValue > normalizedReferenceValue
        ? _tieredPhrase(severity, const [
            'Tidy the background a little, like your reference',
            'Clean up the background, like your reference',
            'Clean up the background a lot, like your reference',
          ])
        : _tieredPhrase(severity, const [
            'Add a touch of background interest, like your reference',
            'Add some background interest, like your reference',
            'Add a lot more background interest, like your reference',
          ]);

    return _AttributeEvaluation(
      severity: severity,
      deviationExceedsThreshold: deviationExceedsThreshold,
      phrase: phrase,
    );
  }
}

class _AttributeEvaluation {
  const _AttributeEvaluation({
    required this.severity,
    required this.deviationExceedsThreshold,
    required this.phrase,
  });

  final int severity;
  final bool deviationExceedsThreshold;
  final String phrase;
}
