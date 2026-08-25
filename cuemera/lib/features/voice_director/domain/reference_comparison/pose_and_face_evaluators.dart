import 'package:cuemera/features/voice_director/domain/action_plan.dart';
import 'package:cuemera/features/voice_director/models/coaching_decision.dart';

import '../../../../core/confidence/confidence.dart';
import '../../../reference_photo/domain/comparison_math.dart';
import '../../../reference_photo/domain/models/reference_profile.dart';
import '../../../reference_photo/domain/models/tolerance_settings.dart';
import '../../../scene_analysis/domain/models/subject_profile.dart';
import 'attribute_evaluation.dart';

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

  final subjectTiltedMoreTowardRight = isFrontCamera
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

  final subjectTurnedMoreTowardRight = isFrontCamera
      ? signedDiff < 0
      : signedDiff > 0;

  final phrase = subjectTurnedMoreTowardRight
      ? tieredPhrase(
          normalizedSeverity,
          mild: 'Turn your face slightly to your left',
          moderate: 'Turn your face more to your left, like the reference',
          strong:
              "Turn your face a lot more to your left — you're turned well past the reference",
        )
      : tieredPhrase(
          normalizedSeverity,
          mild: 'Turn your face slightly to your right',
          moderate: 'Turn your face more to your right, like the reference',
          strong:
              "Turn your face a lot more to your right — you're turned well past the reference",
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

  final subjectLeftLowerThanReference = isFrontCamera
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

  final subjectTurnedMoreTowardRight = isFrontCamera
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

const Map<String, String> _armPoseCategoryInstruction = {
  'down': 'let your {side} arm rest down naturally',
  'crossed': 'cross your {side} arm in front of you',
  'akimbo': 'put your {side} hand on your hip',
  'nearFace': 'bring your {side} hand up near your face',
  'raised': 'raise your {side} arm',
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
    final template =
        _armPoseCategoryInstruction[referenceCategory] ??
        'match your {side} arm to the reference';
    final instruction = template.replaceAll('{side}', side);
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
      ? (subjectRaise! < referenceRaise!
            ? 'raise your $side arm to about ${referenceRaise.round()}°'
            : 'lower your $side arm to about ${referenceRaise.round()}°')
      : null;
  final elbowInstruction = elbowExceeds
      ? (subjectElbow! > referenceElbow!
            ? 'bend your $side elbow in more'
            : 'straighten your $side elbow a bit')
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
