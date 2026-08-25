import 'package:cuemera/features/voice_director/domain/action_plan.dart';
import 'package:cuemera/features/voice_director/models/coaching_decision.dart';

import '../../../../core/analysis/analysis_constants.dart';
import '../../../reference_photo/domain/comparison_math.dart';
import '../../../reference_photo/domain/models/reference_profile.dart';
import '../../../reference_photo/domain/models/tolerance_settings.dart';
import '../../../scene_analysis/domain/models/scene_profile.dart';
import 'attribute_evaluation.dart';

AttributeEvaluation? evaluateNegativeSpace(
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

  final phrase = subjectValue > referenceValue
      ? tieredPhrase(
          normalizedSeverity,
          mild: 'Fill the frame just a touch more',
          moderate: 'Fill the frame more, like your reference',
          strong:
              "There's a lot more empty space around you than the reference — fill the frame more",
        )
      : tieredPhrase(
          normalizedSeverity,
          mild: 'Give a touch more space in the frame',
          moderate: 'Give more space in the frame, like your reference',
          strong:
              "You're filling the frame a lot more than the reference — give more space around you",
        );

  return AttributeEvaluation(
    deviationExceedsThreshold: deviationExceedsThreshold,
    decision: CoachingDecision(
      attribute: CoachingAttribute.negativeSpace,
      direction: subjectValue > referenceValue
          ? CoachingDirection.decrease
          : CoachingDirection.increase,
      tier: CoachingTier.composition,
      normalizedSeverity: normalizedSeverity,
      fallbackPhrase: phrase,
      confidence:
          1.0, // no landmark-confidence signal wired for this attribute yet
      controllability:
          kAttributeControllability[CoachingAttribute.negativeSpace]!,
    ),
  );
}

AttributeEvaluation? evaluateSymmetry(
  SceneProfile scene,
  ReferenceProfile reference,
  ToleranceSettings tolerance,
) {
  final subjectValue = scene.symmetryScore;
  final referenceValue = reference.symmetryScore;
  if (referenceValue == null) return null;

  final deviation = ComparisonMath.oneSidedDeviation(
    subjectValue,
    referenceValue,
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

  final phrase = tieredPhrase(
    normalizedSeverity,
    mild: 'Center yourself just a touch more',
    moderate: 'Center yourself more, like the reference',
    strong: "You're quite off-center — center yourself to match the reference",
  );

  return AttributeEvaluation(
    deviationExceedsThreshold: deviationExceedsThreshold,
    decision: CoachingDecision(
      attribute: CoachingAttribute.symmetry,
      direction: CoachingDirection.none, // single-direction by design
      tier: CoachingTier.composition,
      normalizedSeverity: normalizedSeverity,
      fallbackPhrase: phrase,
      confidence:
          1.0, // no landmark-confidence signal wired for this attribute yet
      controllability: kAttributeControllability[CoachingAttribute.symmetry]!,
    ),
  );
}

AttributeEvaluation? evaluateSubjectPosition(
  SceneProfile scene,
  ReferenceProfile reference,
  ToleranceSettings tolerance,
) {
  final subjectValue = scene.subjectHorizontalPosition;
  final referenceValue = reference.subjectHorizontalPosition;
  if (subjectValue == null || referenceValue == null) return null;

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

  final phrase = subjectValue > referenceValue
      ? tieredPhrase(
          normalizedSeverity,
          mild: 'Shift slightly left in the frame',
          moderate: 'Move left in the frame, like your reference',
          strong:
              "You're positioned well to the right of the reference — move left in the frame",
        )
      : tieredPhrase(
          normalizedSeverity,
          mild: 'Shift slightly right in the frame',
          moderate: 'Move right in the frame, like your reference',
          strong:
              "You're positioned well to the left of the reference — move right in the frame",
        );

  return AttributeEvaluation(
    deviationExceedsThreshold: deviationExceedsThreshold,
    decision: CoachingDecision(
      attribute: CoachingAttribute.subjectPosition,
      direction: subjectValue > referenceValue
          ? CoachingDirection.left
          : CoachingDirection.right,
      tier: CoachingTier.composition,
      normalizedSeverity: normalizedSeverity,
      fallbackPhrase: phrase,
      confidence:
          1.0, // no landmark-confidence signal wired for this attribute yet
      controllability:
          kAttributeControllability[CoachingAttribute.subjectPosition]!,
    ),
  );
}

AttributeEvaluation? evaluateBackgroundClutter(
  SceneProfile scene,
  ReferenceProfile reference,
  ToleranceSettings tolerance,
) {
  final referenceValue = reference.backgroundClutterCount;
  if (referenceValue == null) return null;

  final subjectValue = normalizeClutterCount(scene.backgroundClutterCount);
  final normalizedReferenceValue = normalizeClutterCount(referenceValue);

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

  final phrase = subjectValue > normalizedReferenceValue
      ? tieredPhrase(
          normalizedSeverity,
          mild: 'Clean up the background just a touch, like your reference',
          moderate: 'Clean up the background, like your reference',
          strong:
              "Your background is a lot busier than the reference — clean it up",
        )
      : tieredPhrase(
          normalizedSeverity,
          mild: 'Add a touch of background interest, like your reference',
          moderate: 'Add some background interest, like your reference',
          strong:
              "Your background is a lot plainer than the reference — add some interest",
        );

  return AttributeEvaluation(
    deviationExceedsThreshold: deviationExceedsThreshold,
    decision: CoachingDecision(
      attribute: CoachingAttribute.backgroundClutter,
      direction: subjectValue > normalizedReferenceValue
          ? CoachingDirection.decrease
          : CoachingDirection.increase,
      tier: CoachingTier.composition,
      normalizedSeverity: normalizedSeverity,
      fallbackPhrase: phrase,
      confidence:
          1.0, // no landmark-confidence signal wired for this attribute yet
      controllability:
          kAttributeControllability[CoachingAttribute.backgroundClutter]!,
    ),
  );
}
