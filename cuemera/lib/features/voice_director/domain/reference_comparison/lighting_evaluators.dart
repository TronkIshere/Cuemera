import 'package:cuemera/features/voice_director/domain/action_plan.dart';
import 'package:cuemera/features/voice_director/models/coaching_decision.dart';

import '../../../reference_photo/domain/comparison_math.dart';
import '../../../reference_photo/domain/models/reference_profile.dart';
import '../../../reference_photo/domain/models/tolerance_settings.dart';
import '../../../scene_analysis/domain/models/scene_profile.dart';
import 'attribute_evaluation.dart';

AttributeEvaluation? evaluateBrightness(
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

  final phrase = subjectValue > referenceValue
      ? tieredPhrase(
          normalizedSeverity,
          mild: 'Move to slightly softer light, like your reference',
          moderate: 'Move to softer light, like your reference',
          strong:
              "You're in much brighter light than the reference — move somewhere softer",
        )
      : tieredPhrase(
          normalizedSeverity,
          mild: 'Find a touch more light, like your reference',
          moderate: 'Find more light, like your reference',
          strong:
              "You're in much dimmer light than the reference — find somewhere brighter",
        );

  return AttributeEvaluation(
    deviationExceedsThreshold: deviationExceedsThreshold,
    decision: CoachingDecision(
      attribute: CoachingAttribute.brightness,
      direction: subjectValue > referenceValue
          ? CoachingDirection.decrease
          : CoachingDirection.increase,
      tier: CoachingTier.lighting,
      normalizedSeverity: normalizedSeverity,
      fallbackPhrase: phrase,
      confidence:
          1.0, // no landmark-confidence signal wired for this attribute yet
      controllability: kAttributeControllability[CoachingAttribute.brightness]!,
    ),
  );
}

AttributeEvaluation? evaluateWarmth(
  SceneProfile scene,
  ReferenceProfile reference,
  ToleranceSettings tolerance,
) {
  final subjectValue = scene.liveWarmthScore;
  final referenceValue = reference.warmthScore;
  if (subjectValue == null || referenceValue == null) return null;

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

  final phrase = subjectValue < referenceValue
      ? tieredPhrase(
          normalizedSeverity,
          mild: 'Find slightly warmer tones, like your reference',
          moderate: 'Find warmer tones, like your reference',
          strong:
              "Your tones are a lot cooler than the reference — find much warmer light",
        )
      : tieredPhrase(
          normalizedSeverity,
          mild: 'Cool down the tones just a touch, like your reference',
          moderate: 'Cool down the tones, like your reference',
          strong:
              "Your tones are a lot warmer than the reference — find much cooler light",
        );

  return AttributeEvaluation(
    deviationExceedsThreshold: deviationExceedsThreshold,
    decision: CoachingDecision(
      attribute: CoachingAttribute.warmth,
      direction: subjectValue < referenceValue
          ? CoachingDirection.increase
          : CoachingDirection.decrease,
      tier: CoachingTier.lighting,
      normalizedSeverity: normalizedSeverity,
      fallbackPhrase: phrase,
      confidence:
          1.0, // no landmark-confidence signal wired for this attribute yet
      controllability: kAttributeControllability[CoachingAttribute.warmth]!,
    ),
  );
}

AttributeEvaluation? evaluateHue(
  SceneProfile scene,
  ReferenceProfile reference,
  ToleranceSettings tolerance,
) {
  final subjectValue = scene.liveDominantHue;
  final referenceValue = reference.dominantHue;
  if (subjectValue == null || referenceValue == null) return null;

  final deviation = ComparisonMath.circularDeviation(
    subjectValue,
    referenceValue,
    360.0,
  );
  final normalizedSeverity = ComparisonMath.normalizedSeverity(
    deviation,
    ComparisonMath.maxDeviationForHue,
  );
  final thresholdForHue = ComparisonMath.thresholdForHue(
    tolerance.colorTolerance,
  );
  final deviationExceedsThreshold = ComparisonMath.exceedsThreshold(
    deviation,
    thresholdForHue,
  );

  final phrase = tieredPhrase(
    normalizedSeverity,
    mild: 'Your color tone is slightly off from the reference',
    moderate: 'Match the color tone of your reference more closely',
    strong:
        "Your color tone is quite different from the reference — try to match it",
  );

  return AttributeEvaluation(
    deviationExceedsThreshold: deviationExceedsThreshold,
    decision: CoachingDecision(
      attribute: CoachingAttribute.hue,
      direction: CoachingDirection.none, // single-direction by design
      tier: CoachingTier.lighting,
      normalizedSeverity: normalizedSeverity,
      fallbackPhrase: phrase,
      confidence:
          1.0, // no landmark-confidence signal wired for this attribute yet
      controllability: kAttributeControllability[CoachingAttribute.hue]!,
    ),
  );
}
