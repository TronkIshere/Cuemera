// features/voice_director/domain/reference_comparison_engine.dart
import 'package:cuemera/features/voice_director/domain/priority_engine.dart';

import '../../reference_photo/domain/models/reference_profile.dart';
import '../../reference_photo/domain/models/tolerance_settings.dart';
import '../../scene_analysis/domain/models/scene_profile.dart';
import '../../scene_analysis/domain/models/subject_profile.dart';

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

    final deviation = (subjectValue - referenceValue).abs();
    final normalizedSeverity = (deviation / 90.0).clamp(0.0, 1.0);
    final thresholdForPose = tolerance.poseTolerance * 45.0;
    final deviationExceedsThreshold = deviation > thresholdForPose;

    final phrase = subjectValue > referenceValue
        ? 'Square your shoulders more'
        : 'Angle your shoulders like the reference';

    return _AttributeEvaluation(
      severity: (normalizedSeverity * 10).round(),
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
    if (referenceValue == 0) return null;

    final deviation = (subjectValue - referenceValue).abs() / referenceValue;
    final normalizedSeverity = deviation.clamp(0.0, 1.0);
    final thresholdForPose = tolerance.poseTolerance * 0.5;
    final deviationExceedsThreshold = deviation > thresholdForPose;

    return _AttributeEvaluation(
      severity: (normalizedSeverity * 10).round(),
      deviationExceedsThreshold: deviationExceedsThreshold,
      phrase: 'Match your framing to the reference photo',
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
    final normalizedSeverity = matches ? 0.0 : 1.0;
    final thresholdForExpression = tolerance.expressionTolerance;
    final deviationExceedsThreshold =
        normalizedSeverity > thresholdForExpression;

    return _AttributeEvaluation(
      severity: (normalizedSeverity * 10).round(),
      deviationExceedsThreshold: deviationExceedsThreshold,
      phrase: 'Match the expression in your reference photo',
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

    final deviation = (subjectValue - referenceValue).abs();
    final normalizedSeverity = deviation.clamp(0.0, 1.0);
    final thresholdForComposition = tolerance.compositionTolerance;
    final deviationExceedsThreshold = deviation > thresholdForComposition;

    final phrase = subjectValue > referenceValue
        ? 'Fill the frame more, like your reference'
        : 'Give more space in the frame, like your reference';

    return _AttributeEvaluation(
      severity: (normalizedSeverity * 10).round(),
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
    final normalizedSeverity = deviation;
    final thresholdForComposition = tolerance.compositionTolerance;
    final deviationExceedsThreshold = deviation > thresholdForComposition;

    return _AttributeEvaluation(
      severity: (normalizedSeverity * 10).round(),
      deviationExceedsThreshold: deviationExceedsThreshold,
      phrase: 'Center yourself like the reference',
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

    final deviation = (subjectValue - referenceValue).abs();
    final normalizedSeverity = deviation.clamp(0.0, 1.0);
    final thresholdForColor = tolerance.colorTolerance;
    final deviationExceedsThreshold = deviation > thresholdForColor;

    final phrase = subjectValue > referenceValue
        ? 'Move to softer light, like your reference'
        : 'Find more light, like your reference';

    return _AttributeEvaluation(
      severity: (normalizedSeverity * 10).round(),
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
