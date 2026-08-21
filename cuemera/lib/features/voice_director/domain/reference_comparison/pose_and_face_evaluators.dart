import 'package:cuemera/features/voice_director/domain/action_plan.dart';
import 'package:cuemera/features/voice_director/models/coaching_decision.dart';

import '../../../../core/confidence/confidence.dart';
import '../../../reference_photo/domain/comparison_math.dart';
import '../../../reference_photo/domain/models/reference_profile.dart';
import '../../../reference_photo/domain/models/tolerance_settings.dart';
import '../../../scene_analysis/domain/models/subject_profile.dart';
import 'attribute_evaluation.dart';

const bool _faceRollDirectionIsMirrored = false;
const bool _shoulderBalanceDirectionIsMirrored = false;
const bool _bodyYawDirectionIsMirrored = false;

AttributeEvaluation? evaluateShoulderAngle(
  SubjectProfile subject,
  ReferenceProfile reference,
  ToleranceSettings tolerance,
) {
  final subjectValue = subject.shoulderAngleDegrees;
  final referenceValue = reference.shoulderAngleDegrees;
  if (subjectValue == null || referenceValue == null) return null;

  final deviation = ComparisonMath.circularDeviation(
    subjectValue,
    referenceValue,
    360.0,
  );
  final signedDiff = ((subjectValue - referenceValue) + 180) % 360 - 180;
  final isSubjectGreater = signedDiff > 0;
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

  final phrase = isSubjectGreater
      ? tieredPhrase(
          normalizedSeverity,
          mild: 'Square your shoulders just a touch',
          moderate: 'Square your shoulders more',
          strong:
              "Really square up your shoulders — they're tilted well off the reference",
        )
      : tieredPhrase(
          normalizedSeverity,
          mild: 'Angle your shoulders slightly, like the reference',
          moderate: 'Angle your shoulders more, like the reference',
          strong:
              "Angle your shoulders a lot more — match the reference's tilt",
        );

  return AttributeEvaluation(
    deviationExceedsThreshold: deviationExceedsThreshold,
    decision: CoachingDecision(
      attribute: CoachingAttribute.shoulderAngle,
      direction: isSubjectGreater
          ? CoachingDirection.decrease
          : CoachingDirection.increase,
      tier: CoachingTier.poseAndFace,
      normalizedSeverity: normalizedSeverity,
      fallbackPhrase: phrase,
      confidence: Confidence.decisionConfidence(
        Confidence(subject.confidenceFor('shoulderAngleDegrees')),
        Confidence(reference.confidenceFor('shoulderAngleDegrees')),
      ).value,
      controllability:
          kAttributeControllability[CoachingAttribute.shoulderAngle]!,
    ),
  );
}

AttributeEvaluation? evaluateFacePitch(
  SubjectProfile subject,
  ReferenceProfile reference,
  ToleranceSettings tolerance,
) {
  final subjectValue = subject.faceAngleXDegrees;
  final referenceValue = reference.faceAngleXDegrees;
  if (subjectValue == null || referenceValue == null) return null;

  final deviation = ComparisonMath.circularDeviation(
    subjectValue,
    referenceValue,
    360.0,
  );
  final signedDiff = ((subjectValue - referenceValue) + 180) % 360 - 180;
  final isSubjectGreater = signedDiff > 0;
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

  final phrase = isSubjectGreater
      ? tieredPhrase(
          normalizedSeverity,
          mild: 'Tilt your chin down just a touch',
          moderate: 'Tilt your head down',
          strong:
              "Tilt your head down a lot more — you're well above the reference angle",
        )
      : tieredPhrase(
          normalizedSeverity,
          mild: 'Lift your chin slightly',
          moderate: 'Tilt your head up',
          strong:
              "Tilt your head up a lot more — you're well below the reference angle",
        );

  return AttributeEvaluation(
    deviationExceedsThreshold: deviationExceedsThreshold,
    decision: CoachingDecision(
      attribute: CoachingAttribute.facePitch,
      direction: isSubjectGreater
          ? CoachingDirection.decrease
          : CoachingDirection.increase,
      tier: CoachingTier.poseAndFace,
      normalizedSeverity: normalizedSeverity,
      fallbackPhrase: phrase,
      confidence:
          1.0, // no landmark-confidence signal wired for this attribute yet
      controllability: kAttributeControllability[CoachingAttribute.facePitch]!,
    ),
  );
}

AttributeEvaluation? evaluateFaceRoll(
  SubjectProfile subject,
  ReferenceProfile reference,
  ToleranceSettings tolerance,
) {
  final subjectValue = subject.faceAngleZDegrees;
  final referenceValue = reference.faceAngleZDegrees;
  if (subjectValue == null || referenceValue == null) return null;

  final deviation = ComparisonMath.circularDeviation(
    subjectValue,
    referenceValue,
    360.0,
  );
  final signedDiff = ((subjectValue - referenceValue) + 180) % 360 - 180;
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

  final subjectTiltedMoreTowardRight = _faceRollDirectionIsMirrored
      ? signedDiff < 0
      : signedDiff > 0;

  final phrase = subjectTiltedMoreTowardRight
      ? tieredPhrase(
          normalizedSeverity,
          mild: 'Straighten your head just a touch',
          moderate: "Straighten your head — it's tilted to the right",
          strong:
              "Straighten your head — it's tilted well to the right compared to the reference",
        )
      : tieredPhrase(
          normalizedSeverity,
          mild: 'Straighten your head just a touch',
          moderate: "Straighten your head — it's tilted to the left",
          strong:
              "Straighten your head — it's tilted well to the left compared to the reference",
        );

  return AttributeEvaluation(
    deviationExceedsThreshold: deviationExceedsThreshold,
    decision: CoachingDecision(
      attribute: CoachingAttribute.faceRoll,
      direction: subjectTiltedMoreTowardRight
          ? CoachingDirection.right
          : CoachingDirection.left,
      tier: CoachingTier.poseAndFace,
      normalizedSeverity: normalizedSeverity,
      fallbackPhrase: phrase,
      confidence:
          1.0, // no landmark-confidence signal wired for this attribute yet
      controllability: kAttributeControllability[CoachingAttribute.faceRoll]!,
    ),
  );
}

AttributeEvaluation? evaluateShoulderBalance(
  SubjectProfile subject,
  ReferenceProfile reference,
  ToleranceSettings tolerance,
) {
  final subjectValue = subject.shoulderBalanceRatio;
  final referenceValue = reference.shoulderBalanceRatio;
  if (subjectValue == null || referenceValue == null) return null;

  final deviation = ComparisonMath.deviation(subjectValue, referenceValue);
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

  final subjectLeftLowerThanReference = _shoulderBalanceDirectionIsMirrored
      ? subjectValue < referenceValue
      : subjectValue > referenceValue;

  final phrase = subjectLeftLowerThanReference
      ? tieredPhrase(
          normalizedSeverity,
          mild: 'Level your shoulders just a touch',
          moderate: 'Lift your left shoulder slightly, like the reference',
          strong:
              "Your left shoulder is a lot lower than the reference — lift it",
        )
      : tieredPhrase(
          normalizedSeverity,
          mild: 'Level your shoulders just a touch',
          moderate: 'Lift your right shoulder slightly, like the reference',
          strong:
              "Your right shoulder is a lot lower than the reference — lift it",
        );

  return AttributeEvaluation(
    deviationExceedsThreshold: deviationExceedsThreshold,
    decision: CoachingDecision(
      attribute: CoachingAttribute.shoulderBalance,
      direction: subjectLeftLowerThanReference
          ? CoachingDirection.left
          : CoachingDirection.right,
      tier: CoachingTier.poseAndFace,
      normalizedSeverity: normalizedSeverity,
      fallbackPhrase: phrase,
      confidence: Confidence.decisionConfidence(
        Confidence(subject.confidenceFor('shoulderBalanceRatio')),
        Confidence(reference.confidenceFor('shoulderBalanceRatio')),
      ).value,
      controllability:
          kAttributeControllability[CoachingAttribute.shoulderBalance]!,
    ),
  );
}

AttributeEvaluation? evaluateShoulderSpan(
  SubjectProfile subject,
  ReferenceProfile reference,
  ToleranceSettings tolerance,
) {
  final subjectValue = subject.shoulderSpanRatio;
  final referenceValue = reference.shoulderSpanRatio;
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

  final subjectBroaderThanReference = subjectValue > referenceValue;
  final phrase = subjectBroaderThanReference
      ? tieredPhrase(
          normalizedSeverity,
          mild: 'Relax your shoulders just a touch',
          moderate: 'Relax your shoulders, like the reference',
          strong:
              "Your shoulders are a lot broader than the reference — relax them in",
        )
      : tieredPhrase(
          normalizedSeverity,
          mild: 'Open your shoulders slightly',
          moderate: 'Open your shoulders more, like the reference',
          strong:
              "Your shoulders are a lot narrower than the reference — open them up",
        );

  return AttributeEvaluation(
    deviationExceedsThreshold: deviationExceedsThreshold,
    decision: CoachingDecision(
      attribute: CoachingAttribute.shoulderSpan,
      direction: subjectBroaderThanReference
          ? CoachingDirection.decrease
          : CoachingDirection.increase,
      tier: CoachingTier.poseAndFace,
      normalizedSeverity: normalizedSeverity,
      fallbackPhrase: phrase,
      confidence: Confidence.decisionConfidence(
        Confidence(subject.confidenceFor('shoulderSpanRatio')),
        Confidence(reference.confidenceFor('shoulderSpanRatio')),
      ).value,
      controllability:
          kAttributeControllability[CoachingAttribute.shoulderSpan]!,
    ),
  );
}

AttributeEvaluation? evaluateBodyYaw(
  SubjectProfile subject,
  ReferenceProfile reference,
  ToleranceSettings tolerance,
) {
  final subjectValue = subject.bodyYawEstimate;
  final referenceValue = reference.bodyYawEstimate;
  if (subjectValue == null || referenceValue == null) return null;

  final deviation = ComparisonMath.circularDeviation(
    subjectValue,
    referenceValue,
    360.0,
  );
  final signedDiff = ((subjectValue - referenceValue) + 180) % 360 - 180;
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

  final subjectTurnedMoreTowardRight = _bodyYawDirectionIsMirrored
      ? signedDiff < 0
      : signedDiff > 0;

  final phrase = subjectTurnedMoreTowardRight
      ? tieredPhrase(
          normalizedSeverity,
          mild: 'Turn your body slightly to your left',
          moderate: 'Turn your body more to your left, like the reference',
          strong:
              "Turn your body a lot more to your left — your torso is angled well past the reference",
        )
      : tieredPhrase(
          normalizedSeverity,
          mild: 'Turn your body slightly to your right',
          moderate: 'Turn your body more to your right, like the reference',
          strong:
              "Turn your body a lot more to your right — your torso is angled well past the reference",
        );

  return AttributeEvaluation(
    deviationExceedsThreshold: deviationExceedsThreshold,
    decision: CoachingDecision(
      attribute: CoachingAttribute.bodyYaw,
      direction: subjectTurnedMoreTowardRight
          ? CoachingDirection.left
          : CoachingDirection.right,
      tier: CoachingTier.poseAndFace,
      normalizedSeverity: normalizedSeverity,
      fallbackPhrase: phrase,
      confidence: Confidence.decisionConfidence(
        Confidence(subject.confidenceFor('bodyYawEstimate')),
        Confidence(reference.confidenceFor('bodyYawEstimate')),
      ).value,
      controllability: kAttributeControllability[CoachingAttribute.bodyYaw]!,
    ),
  );
}

AttributeEvaluation? evaluateBodyRatio(
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

  final phrase = tieredPhrase(
    normalizedSeverity,
    mild: "Your framing's a touch different from the reference",
    moderate: 'Adjust your framing to better match the reference proportions',
    strong:
        'Your framing is quite different from the reference — reframe to match',
  );

  return AttributeEvaluation(
    deviationExceedsThreshold: deviationExceedsThreshold,
    decision: CoachingDecision(
      attribute: CoachingAttribute.bodyRatio,
      direction: CoachingDirection.none, // single-direction by design
      tier: CoachingTier.poseAndFace,
      normalizedSeverity: normalizedSeverity,
      fallbackPhrase: phrase,
      confidence: Confidence.decisionConfidence(
        Confidence(subject.confidenceFor('bodyRatio')),
        Confidence(reference.confidenceFor('bodyRatio')),
      ).value,
      controllability: kAttributeControllability[CoachingAttribute.bodyRatio]!,
    ),
  );
}

AttributeEvaluation? evaluateMouthOpen(
  SubjectProfile subject,
  ReferenceProfile reference,
  ToleranceSettings tolerance,
) {
  final subjectValue = subject.mouthOpenRatio;
  final referenceValue = reference.mouthOpenRatio;
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

  final phrase = subjectValue > referenceValue
      ? tieredPhrase(
          normalizedSeverity,
          mild: 'Close your mouth just slightly',
          moderate: 'Close your mouth a bit more, like the reference',
          strong:
              "Your mouth is a lot more open than the reference — close it more",
        )
      : tieredPhrase(
          normalizedSeverity,
          mild: 'Open your mouth just slightly, like the reference',
          moderate: 'Open your mouth more, like the reference',
          strong:
              "Your mouth is a lot more closed than the reference — open it more",
        );

  return AttributeEvaluation(
    deviationExceedsThreshold: deviationExceedsThreshold,
    decision: CoachingDecision(
      attribute: CoachingAttribute.mouthOpen,
      direction: subjectValue > referenceValue
          ? CoachingDirection.decrease
          : CoachingDirection.increase,
      tier: CoachingTier.poseAndFace,
      normalizedSeverity: normalizedSeverity,
      fallbackPhrase: phrase,
      confidence:
          1.0, // no landmark-confidence signal wired for this attribute yet
      controllability: kAttributeControllability[CoachingAttribute.mouthOpen]!,
    ),
  );
}

AttributeEvaluation? evaluateEyeOpen(
  SubjectProfile subject,
  ReferenceProfile reference,
  ToleranceSettings tolerance,
) {
  final subjectValue = subject.eyeOpenRatio;
  final referenceValue = reference.eyeOpenRatio;
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

  final phrase = subjectValue > referenceValue
      ? tieredPhrase(
          normalizedSeverity,
          mild: 'Relax your eyes just a touch',
          moderate: 'Ease your eyes to match the reference',
          strong:
              "Your eyes are much more open than the reference — relax them more",
        )
      : tieredPhrase(
          normalizedSeverity,
          mild: 'Open your eyes just a touch more',
          moderate: 'Open your eyes more, like the reference',
          strong:
              "Your eyes are much more closed than the reference — open them more",
        );

  return AttributeEvaluation(
    deviationExceedsThreshold: deviationExceedsThreshold,
    decision: CoachingDecision(
      attribute: CoachingAttribute.eyeOpen,
      direction: subjectValue > referenceValue
          ? CoachingDirection.decrease
          : CoachingDirection.increase,
      tier: CoachingTier.poseAndFace,
      normalizedSeverity: normalizedSeverity,
      fallbackPhrase: phrase,
      confidence:
          1.0, // no landmark-confidence signal wired for this attribute yet
      controllability: kAttributeControllability[CoachingAttribute.eyeOpen]!,
    ),
  );
}

AttributeEvaluation? evaluateExpression(
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

  final phrase = "Try a more '$referenceValue' expression, like the reference";

  return AttributeEvaluation(
    deviationExceedsThreshold: deviationExceedsThreshold,
    decision: CoachingDecision(
      attribute: CoachingAttribute.expression,
      direction: CoachingDirection.none,
      tier: CoachingTier.poseAndFace,
      normalizedSeverity: deviation,
      fallbackPhrase: phrase,
      confidence:
          1.0, // no landmark-confidence signal wired for this attribute yet
      controllability: kAttributeControllability[CoachingAttribute.expression]!,
      targetExpression: referenceValue,
    ),
  );
}
