import 'dart:math' as math;

import 'package:cuemera/features/voice_director/domain/action_plan.dart';
import 'package:cuemera/features/voice_director/models/coaching_decision.dart';

import '../../../../core/confidence/confidence.dart';
import '../../../reference_photo/domain/comparison_math.dart';
import '../../../reference_photo/domain/models/reference_profile.dart';
import '../../../reference_photo/domain/models/tolerance_settings.dart';
import '../../../scene_analysis/domain/models/subject_profile.dart';
import 'attribute_evaluation.dart';

/// Shared RNG for picking among equivalent phrase variants, so the same
/// coaching cue doesn't read the exact same sentence every time it fires.
final math.Random _phraseRandom = math.Random();

String _pick(List<String> options) =>
    options[_phraseRandom.nextInt(options.length)];

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
  final signedDiff = ComparisonMath.signedCircularDiff(
    subjectValue,
    referenceValue,
    360.0,
  );
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
    mild: _pick(_kSquareShouldersMildPhrases),
    moderate: _pick(_kSquareShouldersModeratePhrases),
    strong: _pick(_kSquareShouldersStrongPhrases),
  )
      : tieredPhrase(
    normalizedSeverity,
    mild: _pick(_kAngleShouldersMildPhrases),
    moderate: _pick(_kAngleShouldersModeratePhrases),
    strong: _pick(_kAngleShouldersStrongPhrases),
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
  final signedDiff = ComparisonMath.signedCircularDiff(
    subjectValue,
    referenceValue,
    360.0,
  );
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
    mild: _pick(_kChinDownMildPhrases),
    moderate: _pick(_kChinDownModeratePhrases),
    strong: _pick(_kChinDownStrongPhrases),
  )
      : tieredPhrase(
    normalizedSeverity,
    mild: _pick(_kChinUpMildPhrases),
    moderate: _pick(_kChinUpModeratePhrases),
    strong: _pick(_kChinUpStrongPhrases),
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
      confidence: Confidence.decisionConfidence(
        Confidence(subject.confidenceFor('faceAngleXDegrees')),
        Confidence(reference.confidenceFor('faceAngleXDegrees')),
      ).value,
      controllability: kAttributeControllability[CoachingAttribute.facePitch]!,
    ),
  );
}

AttributeEvaluation? evaluateFaceRoll(
    SubjectProfile subject,
    ReferenceProfile reference,
    ToleranceSettings tolerance,
    bool isFrontCamera,
    ) {
  final subjectValue = subject.faceAngleZDegrees;
  final referenceValue = reference.faceAngleZDegrees;
  if (subjectValue == null || referenceValue == null) return null;

  final deviation = ComparisonMath.circularDeviation(
    subjectValue,
    referenceValue,
    360.0,
  );
  final signedDiff = ComparisonMath.signedCircularDiff(
    subjectValue,
    referenceValue,
    360.0,
  );
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

  // NOTE: see the identical note on _evaluateFaceRoll in
  // reference_comparison_engine.dart — this reads ML Kit's own
  // headEulerAngleZ, a different signal than the custom shoulder/body-yaw
  // math, so the shoulderBalance fix's confidence doesn't automatically
  // transfer here. Left unchanged; vocabulary expanded only.
  final subjectTiltedMoreTowardRight = isFrontCamera
      ? signedDiff < 0
      : signedDiff > 0;

  final phrase = subjectTiltedMoreTowardRight
      ? tieredPhrase(
    normalizedSeverity,
    mild: _pick(_kStraightenHeadMildPhrases),
    moderate: _pick(_kStraightenHeadFromRightModeratePhrases),
    strong: _pick(_kStraightenHeadFromRightStrongPhrases),
  )
      : tieredPhrase(
    normalizedSeverity,
    mild: _pick(_kStraightenHeadMildPhrases),
    moderate: _pick(_kStraightenHeadFromLeftModeratePhrases),
    strong: _pick(_kStraightenHeadFromLeftStrongPhrases),
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
      confidence: Confidence.decisionConfidence(
        Confidence(subject.confidenceFor('faceAngleZDegrees')),
        Confidence(reference.confidenceFor('faceAngleZDegrees')),
      ).value,
      controllability: kAttributeControllability[CoachingAttribute.faceRoll]!,
    ),
  );
}

AttributeEvaluation? evaluateFaceYaw(
    SubjectProfile subject,
    ReferenceProfile reference,
    ToleranceSettings tolerance,
    bool isFrontCamera,
    ) {
  final subjectValue = subject.faceAngleDegrees;
  final referenceValue = reference.faceAngleDegrees;
  if (subjectValue == null || referenceValue == null) return null;

  final deviation = ComparisonMath.circularDeviation(
    subjectValue,
    referenceValue,
    360.0,
  );
  final signedDiff = ComparisonMath.signedCircularDiff(
    subjectValue,
    referenceValue,
    360.0,
  );
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

  // NOTE: see the identical note on _evaluateFaceYaw in
  // reference_comparison_engine.dart — this reads ML Kit's own
  // headEulerAngleY, a different signal than the custom shoulder/body-yaw
  // math, so the shoulderBalance fix's confidence doesn't automatically
  // transfer here. Left unchanged; vocabulary expanded only.
  final subjectTurnedMoreTowardRight = isFrontCamera
      ? signedDiff < 0
      : signedDiff > 0;

  final phrase = subjectTurnedMoreTowardRight
      ? tieredPhrase(
    normalizedSeverity,
    mild: _pick(_kTurnFaceLeftMildPhrases),
    moderate: _pick(_kTurnFaceLeftModeratePhrases),
    strong: _pick(_kTurnFaceLeftStrongPhrases),
  )
      : tieredPhrase(
    normalizedSeverity,
    mild: _pick(_kTurnFaceRightMildPhrases),
    moderate: _pick(_kTurnFaceRightModeratePhrases),
    strong: _pick(_kTurnFaceRightStrongPhrases),
  );

  return AttributeEvaluation(
    deviationExceedsThreshold: deviationExceedsThreshold,
    decision: CoachingDecision(
      attribute: CoachingAttribute.faceYaw,
      direction: subjectTurnedMoreTowardRight
          ? CoachingDirection.left
          : CoachingDirection.right,
      tier: CoachingTier.poseAndFace,
      normalizedSeverity: normalizedSeverity,
      fallbackPhrase: phrase,
      confidence: Confidence.decisionConfidence(
        Confidence(subject.confidenceFor('faceAngleDegrees')),
        Confidence(reference.confidenceFor('faceAngleDegrees')),
      ).value,
      controllability: kAttributeControllability[CoachingAttribute.faceYaw]!,
    ),
  );
}

AttributeEvaluation? evaluateShoulderBalance(
    SubjectProfile subject,
    ReferenceProfile reference,
    ToleranceSettings tolerance,
    bool isFrontCamera,
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

  // NOTE: previously flipped on `isFrontCamera` here. That flip was never
  // justified by an actual coordinate-level mirror anywhere in the
  // pipeline (ml_kit_service.dart applies no horizontal flip to the
  // CameraImage bytes before ML Kit sees them; pose_analyzer.dart and
  // reference_image_analyzer.dart derive shoulderBalanceRatio with the
  // identical formula regardless of lens). Verified against a real
  // front-camera device log: with the flip in place, subjectValue was
  // consistently far below referenceValue (left shoulder visibly higher
  // than target) and the app kept saying "lift your left shoulder" —
  // which pushes leftShoulder.y further down (up on screen), moving the
  // ratio further from the target instead of toward it. Removing the
  // flip (unconditional `subjectValue > referenceValue`, same as back
  // camera) matches the math: `isFrontCamera` is kept as a parameter only
  // so this call site doesn't need to change if a real mirror source is
  // found later.
  final subjectLeftLowerThanReference = subjectValue > referenceValue;

  final phrase = subjectLeftLowerThanReference
      ? tieredPhrase(
    normalizedSeverity,
    mild: _pick(_kShoulderBalanceMildPhrases),
    moderate: _pick(_kLiftLeftShoulderModeratePhrases),
    strong: _pick(_kLiftLeftShoulderStrongPhrases),
  )
      : tieredPhrase(
    normalizedSeverity,
    mild: _pick(_kShoulderBalanceMildPhrases),
    moderate: _pick(_kLiftRightShoulderModeratePhrases),
    strong: _pick(_kLiftRightShoulderStrongPhrases),
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
    mild: _pick(_kRelaxShouldersMildPhrases),
    moderate: _pick(_kRelaxShouldersModeratePhrases),
    strong: _pick(_kRelaxShouldersStrongPhrases),
  )
      : tieredPhrase(
    normalizedSeverity,
    mild: _pick(_kOpenShouldersMildPhrases),
    moderate: _pick(_kOpenShouldersModeratePhrases),
    strong: _pick(_kOpenShouldersStrongPhrases),
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
    bool isFrontCamera,
    ) {
  final subjectValue = subject.bodyYawEstimate;
  final referenceValue = reference.bodyYawEstimate;
  if (subjectValue == null || referenceValue == null) return null;

  final deviation = ComparisonMath.circularDeviation(
    subjectValue,
    referenceValue,
    360.0,
  );
  final signedDiff = ComparisonMath.signedCircularDiff(
    subjectValue,
    referenceValue,
    360.0,
  );
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

  // NOTE: same isFrontCamera-flip pattern as shoulderBalance had (see that
  // evaluator's note) — this one relies on the sign of leftShoulder/
  // rightShoulder .z (ML Kit depth), which we don't have an independent,
  // device-confirmed convention for the way we do for the y-axis balance
  // case. NOT changed here since flipping it blind, without a matching
  // real-device confirmation, risks trading a possible bug for a
  // different one. To verify: face the front camera, deliberately rotate
  // your torso one direction only, and confirm bodyYawEstimate moves the
  // way this branch assumes before trusting it the way shoulderBalance's
  // fix was confirmed.
  final subjectTurnedMoreTowardRight = isFrontCamera
      ? signedDiff < 0
      : signedDiff > 0;

  final phrase = subjectTurnedMoreTowardRight
      ? tieredPhrase(
    normalizedSeverity,
    mild: _pick(_kTurnLeftMildPhrases),
    moderate: _pick(_kTurnLeftModeratePhrases),
    strong: _pick(_kTurnLeftStrongPhrases),
  )
      : tieredPhrase(
    normalizedSeverity,
    mild: _pick(_kTurnRightMildPhrases),
    moderate: _pick(_kTurnRightModeratePhrases),
    strong: _pick(_kTurnRightStrongPhrases),
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
      confidence: Confidence.decisionConfidence(
        Confidence(subject.confidenceFor('mouthOpenRatio')),
        Confidence(reference.confidenceFor('mouthOpenRatio')),
      ).value,
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
      confidence: Confidence.decisionConfidence(
        Confidence(subject.confidenceFor('eyeOpenRatio')),
        Confidence(reference.confidenceFor('eyeOpenRatio')),
      ).value,
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

AttributeEvaluation? evaluateRightArmPosition(
    SubjectProfile subject,
    ReferenceProfile reference,
    ToleranceSettings tolerance,
    ) => _evaluateArmPosition(
  attribute: CoachingAttribute.rightArmPosition,
  side: 'right',
  subjectRaise: subject.rightArmRaiseDegrees,
  referenceRaise: reference.rightArmRaiseDegrees,
  subjectElbow: subject.rightElbowAngleDegrees,
  referenceElbow: reference.rightElbowAngleDegrees,
  subjectCategory: subject.rightArmPoseCategory,
  referenceCategory: reference.rightArmPoseCategory,
  confidence: Confidence.minOf([
    Confidence.decisionConfidence(
      Confidence(subject.confidenceFor('rightArmRaiseDegrees')),
      Confidence(reference.confidenceFor('rightArmRaiseDegrees')),
    ),
    Confidence.decisionConfidence(
      Confidence(subject.confidenceFor('rightElbowAngleDegrees')),
      Confidence(reference.confidenceFor('rightElbowAngleDegrees')),
    ),
  ]).value,
  tolerance: tolerance,
);

AttributeEvaluation? evaluateLeftArmPosition(
    SubjectProfile subject,
    ReferenceProfile reference,
    ToleranceSettings tolerance,
    ) => _evaluateArmPosition(
  attribute: CoachingAttribute.leftArmPosition,
  side: 'left',
  subjectRaise: subject.leftArmRaiseDegrees,
  referenceRaise: reference.leftArmRaiseDegrees,
  subjectElbow: subject.leftElbowAngleDegrees,
  referenceElbow: reference.leftElbowAngleDegrees,
  subjectCategory: subject.leftArmPoseCategory,
  referenceCategory: reference.leftArmPoseCategory,
  confidence: Confidence.minOf([
    Confidence.decisionConfidence(
      Confidence(subject.confidenceFor('leftArmRaiseDegrees')),
      Confidence(reference.confidenceFor('leftArmRaiseDegrees')),
    ),
    Confidence.decisionConfidence(
      Confidence(subject.confidenceFor('leftElbowAngleDegrees')),
      Confidence(reference.confidenceFor('leftElbowAngleDegrees')),
    ),
  ]).value,
  tolerance: tolerance,
);

const Map<String, List<String>> _kArmPoseCategoryInstructions = {
  'down': [
    'let your {side} arm rest down naturally',
    'relax your {side} arm down by your side',
    'drop your {side} arm down, nice and relaxed',
  ],
  'crossed': [
    'cross your {side} arm in front of you',
    'bring your {side} arm across your body',
    'fold your {side} arm in front, like the reference',
  ],
  'akimbo': [
    'put your {side} hand on your hip',
    'rest your {side} hand on your waist',
    'place your {side} hand on your hip, like the reference',
  ],
  'nearFace': [
    'bring your {side} hand up near your face',
    'raise your {side} hand toward your face',
    'lift your {side} hand up near your head, like the reference',
  ],
  'raised': [
    'raise your {side} arm',
    'lift your {side} arm up',
    'raise your {side} arm higher, like the reference',
  ],
};

AttributeEvaluation? _evaluateArmPosition({
  required CoachingAttribute attribute,
  required String side,
  required double? subjectRaise,
  required double? referenceRaise,
  required double? subjectElbow,
  required double? referenceElbow,
  required String? subjectCategory,
  required String? referenceCategory,
  required double confidence,
  required ToleranceSettings tolerance,
}) {
  if (referenceCategory != null &&
      subjectCategory != null &&
      referenceCategory != subjectCategory) {
    final templates =
        _kArmPoseCategoryInstructions[referenceCategory] ??
            const ['match your {side} arm to the reference'];
    final instruction = _pick(templates).replaceAll('{side}', side);
    final fallbackPhrase =
        '${instruction[0].toUpperCase()}${instruction.substring(1)}, like the reference';

    return AttributeEvaluation(
      deviationExceedsThreshold: true,
      decision: CoachingDecision(
        attribute: attribute,
        direction: CoachingDirection.none,
        tier: CoachingTier.poseAndFace,
        normalizedSeverity: 1.0,
        fallbackPhrase: fallbackPhrase,
        confidence: confidence,
        controllability: kAttributeControllability[attribute]!,
      ),
    );
  }

  if (referenceRaise == null && referenceElbow == null) return null;

  final threshold = ComparisonMath.thresholdForPose(tolerance.poseTolerance);

  double? raiseDeviation;
  if (subjectRaise != null && referenceRaise != null) {
    raiseDeviation = ComparisonMath.deviation(subjectRaise, referenceRaise);
  }
  double? elbowDeviation;
  if (subjectElbow != null && referenceElbow != null) {
    elbowDeviation = ComparisonMath.deviation(subjectElbow, referenceElbow);
  }
  if (raiseDeviation == null && elbowDeviation == null) return null;

  final normalizedSeverity = ComparisonMath.normalizedSeverity(
    [
      raiseDeviation,
      elbowDeviation,
    ].whereType<double>().reduce((a, b) => a > b ? a : b),
    ComparisonMath.maxDeviationForPose,
  );

  final raiseExceeds =
      raiseDeviation != null &&
          ComparisonMath.exceedsThreshold(raiseDeviation, threshold);
  final elbowExceeds =
      elbowDeviation != null &&
          ComparisonMath.exceedsThreshold(elbowDeviation, threshold);

  final raiseInstruction = raiseExceeds
      ? _pick(
    subjectRaise! < referenceRaise!
        ? [
      'raise your $side arm to about ${referenceRaise.round()}°',
      'lift your $side arm higher, to about ${referenceRaise.round()}°',
      'bring your $side arm up more, toward ${referenceRaise.round()}°',
    ]
        : [
      'lower your $side arm to about ${referenceRaise.round()}°',
      'bring your $side arm down some, to about ${referenceRaise.round()}°',
      'ease your $side arm down toward ${referenceRaise.round()}°',
    ],
  )
      : null;
  final elbowInstruction = elbowExceeds
      ? _pick(
    subjectElbow! > referenceElbow!
        ? [
      'bend your $side elbow in more',
      'fold your $side elbow in a bit more',
      'bring your $side elbow in closer',
    ]
        : [
      'straighten your $side elbow a bit',
      'extend your $side elbow a little more',
      'open up your $side elbow slightly',
    ],
  )
      : null;

  final instructions = [
    raiseInstruction,
    elbowInstruction,
  ].whereType<String>().toList();
  final combined = instructions.isEmpty
      ? 'match your $side arm to the reference'
      : '${instructions.join(', and ')}, like the reference';
  final fallbackPhrase = '${combined[0].toUpperCase()}${combined.substring(1)}';

  final direction = (raiseDeviation ?? -1) >= (elbowDeviation ?? -1)
      ? (raiseExceeds && subjectRaise! < referenceRaise!
      ? CoachingDirection.increase
      : CoachingDirection.decrease)
      : (elbowExceeds && subjectElbow! > referenceElbow!
      ? CoachingDirection.decrease
      : CoachingDirection.increase);

  return AttributeEvaluation(
    deviationExceedsThreshold: raiseExceeds || elbowExceeds,
    decision: CoachingDecision(
      attribute: attribute,
      direction: direction,
      tier: CoachingTier.poseAndFace,
      normalizedSeverity: normalizedSeverity,
      fallbackPhrase: fallbackPhrase,
      confidence: confidence,
      controllability: kAttributeControllability[attribute]!,
    ),
  );
}

// ---------------------------------------------------------------------------
// Phrase banks — expanded vocabulary for shoulderBalance / shoulderSpan /
// bodyYaw, the three attributes most often triggered when matching a pose
// like the raised-arm reference photo (one shoulder dipped, torso turned,
// arm lifted). Each tier picks randomly among a few options via `_pick(...)`
// so the same correction doesn't read as the identical sentence every time.
// ---------------------------------------------------------------------------

const List<String> _kShoulderBalanceMildPhrases = [
  'Level your shoulders just a touch',
  'Even out your shoulders a little',
  'Almost level — just a small shoulder adjustment',
  'Just a touch more and your shoulders will match',
];

const List<String> _kLiftLeftShoulderModeratePhrases = [
  'Lift your left shoulder slightly, like the reference',
  'Raise your left shoulder a bit to match the reference',
  'Bring your left shoulder up a little',
  'Your left shoulder could come up slightly',
];

const List<String> _kLiftLeftShoulderStrongPhrases = [
  'Your left shoulder is a lot lower than the reference — lift it',
  'Lift your left shoulder significantly to match the reference',
  'Raise your left shoulder a lot — it is much lower than the reference',
  'Your left shoulder needs a big lift to match this pose',
];

const List<String> _kLiftRightShoulderModeratePhrases = [
  'Lift your right shoulder slightly, like the reference',
  'Raise your right shoulder a bit to match the reference',
  'Bring your right shoulder up a little',
  'Your right shoulder could come up slightly',
];

const List<String> _kLiftRightShoulderStrongPhrases = [
  'Your right shoulder is a lot lower than the reference — lift it',
  'Lift your right shoulder significantly to match the reference',
  'Raise your right shoulder a lot — it is much lower than the reference',
  'Your right shoulder needs a big lift to match this pose',
];

const List<String> _kRelaxShouldersMildPhrases = [
  'Relax your shoulders just a touch',
  'Ease your shoulders in a little',
  'Soften your shoulders slightly',
];

const List<String> _kRelaxShouldersModeratePhrases = [
  'Relax your shoulders, like the reference',
  'Bring your shoulders in a bit, like the reference',
  'Ease your shoulders inward to match',
];

const List<String> _kRelaxShouldersStrongPhrases = [
  'Your shoulders are a lot broader than the reference — relax them in',
  'Your shoulders are much wider than the reference — relax them inward',
  'Bring your shoulders in a lot — they are much broader than the reference',
];

const List<String> _kOpenShouldersMildPhrases = [
  'Open your shoulders slightly',
  'Broaden your shoulders a touch',
  'Roll your shoulders back a little',
];

const List<String> _kOpenShouldersModeratePhrases = [
  'Open your shoulders more, like the reference',
  'Broaden your shoulders to match the reference',
  'Roll your shoulders back more, like the reference',
];

const List<String> _kOpenShouldersStrongPhrases = [
  'Your shoulders are a lot narrower than the reference — open them up',
  'Your shoulders are much narrower than the reference — broaden them',
  "Open your shoulders a lot more — the reference's stance is much wider",
];

const List<String> _kTurnLeftMildPhrases = [
  'Turn your body slightly to your left',
  'Rotate a touch to your left',
  'Angle your body a little more to the left',
];

const List<String> _kTurnLeftModeratePhrases = [
  'Turn your body more to your left, like the reference',
  'Rotate further to your left to match the reference',
  'Angle your body more to the left, like the reference',
];

const List<String> _kTurnLeftStrongPhrases = [
  'Turn your body a lot more to your left — your torso is angled well past the reference',
  'Rotate significantly to your left — you are well past the reference angle',
  'Your torso needs a big turn to the left to match the reference',
];

const List<String> _kTurnRightMildPhrases = [
  'Turn your body slightly to your right',
  'Rotate a touch to your right',
  'Angle your body a little more to the right',
];

const List<String> _kTurnRightModeratePhrases = [
  'Turn your body more to your right, like the reference',
  'Rotate further to your right to match the reference',
  'Angle your body more to the right, like the reference',
];

const List<String> _kTurnRightStrongPhrases = [
  'Turn your body a lot more to your right — your torso is angled well past the reference',
  'Rotate significantly to your right — you are well past the reference angle',
  'Your torso needs a big turn to the right to match the reference',
];

const List<String> _kSquareShouldersMildPhrases = [
  'Square your shoulders just a touch',
  'Bring your shoulders level with the camera a little more',
  'Straighten your shoulder line slightly',
];

const List<String> _kSquareShouldersModeratePhrases = [
  'Square your shoulders more',
  'Bring your shoulders more level with the camera',
  'Straighten your shoulder line, like the reference',
];

const List<String> _kSquareShouldersStrongPhrases = [
  "Really square up your shoulders — they're tilted well off the reference",
  'Your shoulders are tilted a lot — square them up to match the reference',
  'Straighten your shoulder line a lot — it is well off the reference angle',
];

const List<String> _kAngleShouldersMildPhrases = [
  'Angle your shoulders slightly, like the reference',
  'Tilt your shoulder line a touch, like the reference',
  'Give your shoulders a small tilt, like the reference',
];

const List<String> _kAngleShouldersModeratePhrases = [
  'Angle your shoulders more, like the reference',
  'Tilt your shoulder line more, like the reference',
  'Give your shoulders more of a tilt, like the reference',
];

const List<String> _kAngleShouldersStrongPhrases = [
  "Angle your shoulders a lot more — match the reference's tilt",
  'Tilt your shoulder line a lot more to match the reference',
  "Your shoulders need a much bigger tilt to match the reference's angle",
];

const List<String> _kChinDownMildPhrases = [
  'Tilt your chin down just a touch',
  'Lower your chin slightly',
  'Dip your chin a little',
];

const List<String> _kChinDownModeratePhrases = [
  'Tilt your head down',
  'Lower your chin more',
  'Bring your head down a bit, like the reference',
];

const List<String> _kChinDownStrongPhrases = [
  "Tilt your head down a lot more — you're well above the reference angle",
  'Bring your chin down a lot — your head is angled well above the reference',
  'Lower your head significantly to match the reference',
];

const List<String> _kChinUpMildPhrases = [
  'Lift your chin slightly',
  'Raise your chin a touch',
  'Tilt your head up a little',
];

const List<String> _kChinUpModeratePhrases = [
  'Tilt your head up',
  'Raise your chin more',
  'Bring your head up a bit, like the reference',
];

const List<String> _kChinUpStrongPhrases = [
  "Tilt your head up a lot more — you're well below the reference angle",
  'Raise your chin a lot — your head is angled well below the reference',
  'Lift your head significantly to match the reference',
];

const List<String> _kStraightenHeadMildPhrases = [
  'Straighten your head just a touch',
  'Level your head out a little',
  'Even out your head tilt slightly',
];

const List<String> _kStraightenHeadFromRightModeratePhrases = [
  "Straighten your head — it's tilted to the right",
  'Level out your head — it is leaning to the right',
  'Bring your head back toward center — it is tilted right',
];

const List<String> _kStraightenHeadFromRightStrongPhrases = [
  "Straighten your head — it's tilted well to the right compared to the reference",
  'Your head is tilted a lot to the right — level it out to match the reference',
  'Bring your head back to center — it is well off to the right',
];

const List<String> _kStraightenHeadFromLeftModeratePhrases = [
  "Straighten your head — it's tilted to the left",
  'Level out your head — it is leaning to the left',
  'Bring your head back toward center — it is tilted left',
];

const List<String> _kStraightenHeadFromLeftStrongPhrases = [
  "Straighten your head — it's tilted well to the left compared to the reference",
  'Your head is tilted a lot to the left — level it out to match the reference',
  'Bring your head back to center — it is well off to the left',
];

const List<String> _kTurnFaceLeftMildPhrases = [
  'Turn your face slightly to your left',
  'Angle your face a touch to your left',
  'Rotate your face a little to your left',
];

const List<String> _kTurnFaceLeftModeratePhrases = [
  'Turn your face more to your left, like the reference',
  'Angle your face more to your left, like the reference',
  'Rotate your face further to your left, like the reference',
];

const List<String> _kTurnFaceLeftStrongPhrases = [
  "Turn your face a lot more to your left — you're turned well past the reference",
  'Rotate your face significantly to your left to match the reference',
  'Your face needs a big turn to the left to match the reference angle',
];

const List<String> _kTurnFaceRightMildPhrases = [
  'Turn your face slightly to your right',
  'Angle your face a touch to your right',
  'Rotate your face a little to your right',
];

const List<String> _kTurnFaceRightModeratePhrases = [
  'Turn your face more to your right, like the reference',
  'Angle your face more to your right, like the reference',
  'Rotate your face further to your right, like the reference',
];

const List<String> _kTurnFaceRightStrongPhrases = [
  "Turn your face a lot more to your right — you're turned well past the reference",
  'Rotate your face significantly to your right to match the reference',
  'Your face needs a big turn to the right to match the reference angle',
];