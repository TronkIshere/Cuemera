// features/voice_director/domain/reference_comparison_engine.dart
import 'package:cuemera/features/voice_director/domain/action_plan.dart';
import 'package:cuemera/features/voice_director/domain/root_cause_engine.dart';
import 'package:cuemera/features/voice_director/models/coaching_decision.dart';
import 'package:flutter/foundation.dart';

import '../../../core/analysis/analysis_constants.dart';
import '../../../core/confidence/confidence.dart';
import '../../reference_photo/domain/comparison_math.dart';
import '../../reference_photo/domain/models/reference_profile.dart';
import '../../reference_photo/domain/models/tolerance_settings.dart';
import '../../scene_analysis/domain/models/scene_profile.dart';
import '../../scene_analysis/domain/models/subject_profile.dart';

class ReferenceComparisonEngine {
  static const double _mildSeverityCeiling =
      CoachingDecision.mildSeverityCeiling;
  static const double _moderateSeverityCeiling =
      CoachingDecision.moderateSeverityCeiling;

  String _tieredPhrase(
    double normalizedSeverity, {
    required String mild,
    required String moderate,
    required String strong,
  }) {
    if (normalizedSeverity < _mildSeverityCeiling) return mild;
    if (normalizedSeverity < _moderateSeverityCeiling) return moderate;
    return strong;
  }

  final RootCauseEngine _rootCause = const RootCauseEngine();
  int _tierRotation = 0;

  ActionPlan _toActionPlan(_AttributeEvaluation evaluation) {
    return ActionPlan(
      phrase: evaluation.phrase,
      decision: evaluation.decision,
      sourceLayer: 'reference_comparison_engine',
      confidence: evaluation.decision.confidence,
      controllability: evaluation.decision.controllability,
    );
  }

  TierCandidates evaluateTiers({
    required SubjectProfile subject,
    required SceneProfile scene,
    required ReferenceProfile reference,
    required ToleranceSettings tolerance,
    required bool isFrontCamera,
  }) {
    final poseAndFaceTier = <_AttributeEvaluation>[];
    final compositionTier = <_AttributeEvaluation>[];
    final lightingTier = <_AttributeEvaluation>[];

    void addIfPresent(
      List<_AttributeEvaluation> tier,
      _AttributeEvaluation? evaluation,
    ) {
      if (evaluation != null) tier.add(evaluation);
    }

    addIfPresent(
      poseAndFaceTier,
      _evaluateShoulderAngle(subject, reference, tolerance),
    );
    addIfPresent(
      poseAndFaceTier,
      _evaluateFacePitch(subject, reference, tolerance),
    );
    addIfPresent(
      poseAndFaceTier,
      _evaluateFaceRoll(subject, reference, tolerance, isFrontCamera),
    );
    addIfPresent(
      poseAndFaceTier,
      _evaluateFaceYaw(subject, reference, tolerance, isFrontCamera),
    );
    addIfPresent(
      poseAndFaceTier,
      _evaluateBodyRatio(subject, reference, tolerance),
    );
    addIfPresent(
      poseAndFaceTier,
      _evaluateMouthOpen(subject, reference, tolerance),
    );
    addIfPresent(
      poseAndFaceTier,
      _evaluateEyeOpen(subject, reference, tolerance),
    );
    addIfPresent(
      poseAndFaceTier,
      _evaluateExpression(subject, reference, tolerance),
    );
    addIfPresent(
      poseAndFaceTier,
      _evaluateShoulderBalance(subject, reference, tolerance, isFrontCamera),
    );
    addIfPresent(
      poseAndFaceTier,
      _evaluateShoulderSpan(subject, reference, tolerance),
    );
    addIfPresent(
      poseAndFaceTier,
      _evaluateBodyYaw(subject, reference, tolerance, isFrontCamera),
    );

    addIfPresent(
      compositionTier,
      _evaluateNegativeSpace(scene, reference, tolerance),
    );
    addIfPresent(
      compositionTier,
      _evaluateSymmetry(scene, reference, tolerance),
    );
    addIfPresent(
      compositionTier,
      _evaluateBackgroundClutter(scene, reference, tolerance),
    );

    addIfPresent(
      lightingTier,
      _evaluateBrightness(scene, reference, tolerance),
    );
    addIfPresent(lightingTier, _evaluateWarmth(scene, reference, tolerance));
    addIfPresent(lightingTier, _evaluateHue(scene, reference, tolerance));

    final poseCandidates = _rootCause.collapse(
      poseAndFaceTier
          .where((c) => c.deviationExceedsThreshold)
          .map(_toActionPlan)
          .toList(),
    );
    final compositionCandidates = compositionTier
        .where((c) => c.deviationExceedsThreshold)
        .map(_toActionPlan)
        .toList();
    final lightingCandidates = lightingTier
        .where((c) => c.deviationExceedsThreshold)
        .map(_toActionPlan)
        .toList();

    if (kDebugMode) {
      debugPrint(
        'pick_worst: pose=[${poseCandidates.map((c) => '${c.decision.attribute.name}=${c.severity.toStringAsFixed(3)}').join(', ')}] '
        'composition=[${compositionCandidates.map((c) => '${c.decision.attribute.name}=${c.severity.toStringAsFixed(3)}').join(', ')}] '
        'lighting=[${lightingCandidates.map((c) => '${c.decision.attribute.name}=${c.severity.toStringAsFixed(3)}').join(', ')}]',
      );
    }

    return TierCandidates(
      poseAndFace: poseCandidates,
      composition: compositionCandidates,
      lighting: lightingCandidates,
    );
  }

  PriorityAction? evaluate({
    required SubjectProfile subject,
    required SceneProfile scene,
    required ReferenceProfile reference,
    required ToleranceSettings tolerance,
    required bool isFrontCamera,
  }) {
    final tiers = evaluateTiers(
      subject: subject,
      scene: scene,
      reference: reference,
      tolerance: tolerance,
      isFrontCamera: isFrontCamera,
    );

    final chosen = pickAcrossTiers(
      poseAndFace: tiers.poseAndFace,
      composition: tiers.composition,
      lighting: tiers.lighting,
      tierRotation: _tierRotation,
    );
    if (chosen != null) _tierRotation++;
    return chosen;
  }

  _AttributeEvaluation? _evaluateShoulderAngle(
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
        ? _tieredPhrase(
            normalizedSeverity,
            mild: 'Square your shoulders just a touch',
            moderate: 'Square your shoulders more',
            strong:
                "Really square up your shoulders — they're tilted well off the reference",
          )
        : _tieredPhrase(
            normalizedSeverity,
            mild: 'Angle your shoulders slightly, like the reference',
            moderate: 'Angle your shoulders more, like the reference',
            strong:
                "Angle your shoulders a lot more — match the reference's tilt",
          );

    return _AttributeEvaluation(
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

  _AttributeEvaluation? _evaluateFacePitch(
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
        ? _tieredPhrase(
            normalizedSeverity,
            mild: 'Tilt your chin down just a touch',
            moderate: 'Tilt your head down',
            strong:
                "Tilt your head down a lot more — you're well above the reference angle",
          )
        : _tieredPhrase(
            normalizedSeverity,
            mild: 'Lift your chin slightly',
            moderate: 'Tilt your head up',
            strong:
                "Tilt your head up a lot more — you're well below the reference angle",
          );

    return _AttributeEvaluation(
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
        controllability:
            kAttributeControllability[CoachingAttribute.facePitch]!,
      ),
    );
  }

  _AttributeEvaluation? _evaluateFaceRoll(
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
        ? _tieredPhrase(
            normalizedSeverity,
            mild: 'Straighten your head just a touch',
            moderate: "Straighten your head — it's tilted to the right",
            strong:
                "Straighten your head — it's tilted well to the right compared to the reference",
          )
        : _tieredPhrase(
            normalizedSeverity,
            mild: 'Straighten your head just a touch',
            moderate: "Straighten your head — it's tilted to the left",
            strong:
                "Straighten your head — it's tilted well to the left compared to the reference",
          );

    return _AttributeEvaluation(
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

  _AttributeEvaluation? _evaluateFaceYaw(
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
        ? _tieredPhrase(
            normalizedSeverity,
            mild: 'Turn your face slightly to your left',
            moderate: 'Turn your face more to your left, like the reference',
            strong:
                "Turn your face a lot more to your left — you're turned well past the reference",
          )
        : _tieredPhrase(
            normalizedSeverity,
            mild: 'Turn your face slightly to your right',
            moderate: 'Turn your face more to your right, like the reference',
            strong:
                "Turn your face a lot more to your right — you're turned well past the reference",
          );

    return _AttributeEvaluation(
      deviationExceedsThreshold: deviationExceedsThreshold,
      decision: CoachingDecision(
        attribute: CoachingAttribute.faceYaw,
        direction: subjectTurnedMoreTowardRight
            ? CoachingDirection.left
            : CoachingDirection.right,
        tier: CoachingTier.poseAndFace,
        normalizedSeverity: normalizedSeverity,
        fallbackPhrase: phrase,
        confidence:
            1.0, // no landmark-confidence signal wired for this attribute yet
        controllability: kAttributeControllability[CoachingAttribute.faceYaw]!,
      ),
    );
  }

  _AttributeEvaluation? _evaluateShoulderBalance(
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
        ? _tieredPhrase(
            normalizedSeverity,
            mild: 'Level your shoulders just a touch',
            moderate: 'Lift your left shoulder slightly, like the reference',
            strong:
                "Your left shoulder is a lot lower than the reference — lift it",
          )
        : _tieredPhrase(
            normalizedSeverity,
            mild: 'Level your shoulders just a touch',
            moderate: 'Lift your right shoulder slightly, like the reference',
            strong:
                "Your right shoulder is a lot lower than the reference — lift it",
          );

    return _AttributeEvaluation(
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

  _AttributeEvaluation? _evaluateShoulderSpan(
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
      ComparisonMath.maxRelativeDeviationForPoseRatio,
    );
    final thresholdForPose = ComparisonMath.thresholdForRelativePoseRatio(
      tolerance.poseTolerance,
    );
    final deviationExceedsThreshold = ComparisonMath.exceedsThreshold(
      deviation,
      thresholdForPose,
    );

    final subjectBroaderThanReference = subjectValue > referenceValue;
    final phrase = subjectBroaderThanReference
        ? _tieredPhrase(
            normalizedSeverity,
            mild: 'Relax your shoulders just a touch',
            moderate: 'Relax your shoulders, like the reference',
            strong:
                "Your shoulders are a lot broader than the reference — relax them in",
          )
        : _tieredPhrase(
            normalizedSeverity,
            mild: 'Open your shoulders slightly',
            moderate: 'Open your shoulders more, like the reference',
            strong:
                "Your shoulders are a lot narrower than the reference — open them up",
          );

    return _AttributeEvaluation(
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

  _AttributeEvaluation? _evaluateBodyYaw(
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
        ? _tieredPhrase(
            normalizedSeverity,
            mild: 'Turn your body slightly to your left',
            moderate: 'Turn your body more to your left, like the reference',
            strong:
                "Turn your body a lot more to your left — your torso is angled well past the reference",
          )
        : _tieredPhrase(
            normalizedSeverity,
            mild: 'Turn your body slightly to your right',
            moderate: 'Turn your body more to your right, like the reference',
            strong:
                "Turn your body a lot more to your right — your torso is angled well past the reference",
          );

    return _AttributeEvaluation(
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
      ComparisonMath.maxRelativeDeviationForPoseRatio,
    );
    final thresholdForPose = ComparisonMath.thresholdForRelativePoseRatio(
      tolerance.poseTolerance,
    );
    final deviationExceedsThreshold = ComparisonMath.exceedsThreshold(
      deviation,
      thresholdForPose,
    );

    final phrase = _tieredPhrase(
      normalizedSeverity,
      mild: "Your framing's a touch different from the reference",
      moderate: 'Adjust your framing to better match the reference proportions',
      strong:
          'Your framing is quite different from the reference — reframe to match',
    );

    return _AttributeEvaluation(
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
        controllability:
            kAttributeControllability[CoachingAttribute.bodyRatio]!,
      ),
    );
  }

  _AttributeEvaluation? _evaluateMouthOpen(
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
      ComparisonMath.maxRelativeDeviationForPoseRatio,
    );
    final thresholdForPose = ComparisonMath.thresholdForRelativePoseRatio(
      tolerance.poseTolerance,
    );
    final deviationExceedsThreshold = ComparisonMath.exceedsThreshold(
      deviation,
      thresholdForPose,
    );

    final phrase = subjectValue > referenceValue
        ? _tieredPhrase(
            normalizedSeverity,
            mild: 'Close your mouth just slightly',
            moderate: 'Close your mouth a bit more, like the reference',
            strong:
                "Your mouth is a lot more open than the reference — close it more",
          )
        : _tieredPhrase(
            normalizedSeverity,
            mild: 'Open your mouth just slightly, like the reference',
            moderate: 'Open your mouth more, like the reference',
            strong:
                "Your mouth is a lot more closed than the reference — open it more",
          );

    return _AttributeEvaluation(
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
        controllability:
            kAttributeControllability[CoachingAttribute.mouthOpen]!,
      ),
    );
  }

  _AttributeEvaluation? _evaluateEyeOpen(
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
      ComparisonMath.maxRelativeDeviationForPoseRatio,
    );
    final thresholdForPose = ComparisonMath.thresholdForRelativePoseRatio(
      tolerance.poseTolerance,
    );
    final deviationExceedsThreshold = ComparisonMath.exceedsThreshold(
      deviation,
      thresholdForPose,
    );

    final phrase = subjectValue > referenceValue
        ? _tieredPhrase(
            normalizedSeverity,
            mild: 'Relax your eyes just a touch',
            moderate: 'Ease your eyes to match the reference',
            strong:
                "Your eyes are much more open than the reference — relax them more",
          )
        : _tieredPhrase(
            normalizedSeverity,
            mild: 'Open your eyes just a touch more',
            moderate: 'Open your eyes more, like the reference',
            strong:
                "Your eyes are much more closed than the reference — open them more",
          );

    return _AttributeEvaluation(
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

    final phrase =
        "Try a more '$referenceValue' expression, like the reference";

    return _AttributeEvaluation(
      deviationExceedsThreshold: deviationExceedsThreshold,
      decision: CoachingDecision(
        attribute: CoachingAttribute.expression,
        direction: CoachingDirection.none,
        tier: CoachingTier.poseAndFace,
        normalizedSeverity: deviation,
        fallbackPhrase: phrase,
        confidence:
            1.0, // no landmark-confidence signal wired for this attribute yet
        controllability:
            kAttributeControllability[CoachingAttribute.expression]!,
        targetExpression: referenceValue,
      ),
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

    final phrase = subjectValue > referenceValue
        ? _tieredPhrase(
            normalizedSeverity,
            mild: 'Fill the frame just a touch more',
            moderate: 'Fill the frame more, like your reference',
            strong:
                "There's a lot more empty space around you than the reference — fill the frame more",
          )
        : _tieredPhrase(
            normalizedSeverity,
            mild: 'Give a touch more space in the frame',
            moderate: 'Give more space in the frame, like your reference',
            strong:
                "You're filling the frame a lot more than the reference — give more space around you",
          );

    return _AttributeEvaluation(
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

  _AttributeEvaluation? _evaluateSymmetry(
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

    final phrase = _tieredPhrase(
      normalizedSeverity,
      mild: 'Center yourself just a touch more',
      moderate: 'Center yourself more, like the reference',
      strong:
          "You're quite off-center — center yourself to match the reference",
    );

    return _AttributeEvaluation(
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

    final phrase = subjectValue > referenceValue
        ? _tieredPhrase(
            normalizedSeverity,
            mild: 'Move to slightly softer light, like your reference',
            moderate: 'Move to softer light, like your reference',
            strong:
                "You're in much brighter light than the reference — move somewhere softer",
          )
        : _tieredPhrase(
            normalizedSeverity,
            mild: 'Find a touch more light, like your reference',
            moderate: 'Find more light, like your reference',
            strong:
                "You're in much dimmer light than the reference — find somewhere brighter",
          );

    return _AttributeEvaluation(
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
        controllability:
            kAttributeControllability[CoachingAttribute.brightness]!,
      ),
    );
  }

  _AttributeEvaluation? _evaluateBackgroundClutter(
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
        ? _tieredPhrase(
            normalizedSeverity,
            mild: 'Clean up the background just a touch, like your reference',
            moderate: 'Clean up the background, like your reference',
            strong:
                "Your background is a lot busier than the reference — clean it up",
          )
        : _tieredPhrase(
            normalizedSeverity,
            mild: 'Add a touch of background interest, like your reference',
            moderate: 'Add some background interest, like your reference',
            strong:
                "Your background is a lot plainer than the reference — add some interest",
          );

    return _AttributeEvaluation(
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

  _AttributeEvaluation? _evaluateWarmth(
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
        ? _tieredPhrase(
            normalizedSeverity,
            mild: 'Find slightly warmer tones, like your reference',
            moderate: 'Find warmer tones, like your reference',
            strong:
                "Your tones are a lot cooler than the reference — find much warmer light",
          )
        : _tieredPhrase(
            normalizedSeverity,
            mild: 'Cool down the tones just a touch, like your reference',
            moderate: 'Cool down the tones, like your reference',
            strong:
                "Your tones are a lot warmer than the reference — find much cooler light",
          );

    return _AttributeEvaluation(
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

  _AttributeEvaluation? _evaluateHue(
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

    final phrase = _tieredPhrase(
      normalizedSeverity,
      mild: 'Your color tone is slightly off from the reference',
      moderate: 'Match the color tone of your reference more closely',
      strong:
          "Your color tone is quite different from the reference — try to match it",
    );

    return _AttributeEvaluation(
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
}

class TierCandidates {
  const TierCandidates({
    required this.poseAndFace,
    required this.composition,
    required this.lighting,
  });

  final List<ActionPlan> poseAndFace;
  final List<ActionPlan> composition;
  final List<ActionPlan> lighting;
}

class _AttributeEvaluation {
  const _AttributeEvaluation({
    required this.deviationExceedsThreshold,
    required this.decision,
  });

  final bool deviationExceedsThreshold;
  final CoachingDecision decision;

  String get phrase => decision.fallbackPhrase;
}
