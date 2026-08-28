// features/voice_director/domain/reference_comparison_engine.dart
import 'dart:math' as math;

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

// ---------------------------------------------------------------------------
// Phrase banks — expanded vocabulary for shoulderBalance / shoulderSpan /
// bodyYaw, the three attributes most often triggered when matching a pose
// like the raised-arm reference photo (one shoulder dipped, torso turned,
// arm lifted). Each tier picks randomly among a few options via
// `_pickPhrase(...)` so the same correction doesn't read as the identical
// sentence every time.
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

  /// Shared RNG for picking among equivalent phrase variants, so the same
  /// coaching cue doesn't read the exact same sentence every time it fires.
  final math.Random _phraseRandom = math.Random();

  String _pickPhrase(List<String> options) =>
      options[_phraseRandom.nextInt(options.length)];

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
      poseAndFaceTier,
      _evaluateRightArmPosition(subject, reference, tolerance),
    );
    addIfPresent(
      poseAndFaceTier,
      _evaluateLeftArmPosition(subject, reference, tolerance),
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
      mild: _pickPhrase(_kSquareShouldersMildPhrases),
      moderate: _pickPhrase(_kSquareShouldersModeratePhrases),
      strong: _pickPhrase(_kSquareShouldersStrongPhrases),
    )
        : _tieredPhrase(
      normalizedSeverity,
      mild: _pickPhrase(_kAngleShouldersMildPhrases),
      moderate: _pickPhrase(_kAngleShouldersModeratePhrases),
      strong: _pickPhrase(_kAngleShouldersStrongPhrases),
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
      mild: _pickPhrase(_kChinDownMildPhrases),
      moderate: _pickPhrase(_kChinDownModeratePhrases),
      strong: _pickPhrase(_kChinDownStrongPhrases),
    )
        : _tieredPhrase(
      normalizedSeverity,
      mild: _pickPhrase(_kChinUpMildPhrases),
      moderate: _pickPhrase(_kChinUpModeratePhrases),
      strong: _pickPhrase(_kChinUpStrongPhrases),
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
        confidence: Confidence.decisionConfidence(
          Confidence(subject.confidenceFor('faceAngleXDegrees')),
          Confidence(reference.confidenceFor('faceAngleXDegrees')),
        ).value,
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

    // NOTE: same isFrontCamera-flip pattern as _evaluateShoulderBalance
    // originally had. UNLIKE shoulderBalance/bodyYaw (custom atan2 math over
    // pose landmarks, confirmed nowhere else mirrored), this reads ML Kit's
    // own face-detector headEulerAngleZ directly — a different signal
    // source with its own, separately-documented front-camera sign
    // conventions we haven't independently verified here. Left unchanged;
    // vocabulary expanded only. To verify: face the front camera, tilt your
    // head to one side only, and confirm this branch names the side you
    // actually tilted toward.
    final subjectTiltedMoreTowardRight = isFrontCamera
        ? signedDiff < 0
        : signedDiff > 0;

    final phrase = subjectTiltedMoreTowardRight
        ? _tieredPhrase(
      normalizedSeverity,
      mild: _pickPhrase(_kStraightenHeadMildPhrases),
      moderate: _pickPhrase(_kStraightenHeadFromRightModeratePhrases),
      strong: _pickPhrase(_kStraightenHeadFromRightStrongPhrases),
    )
        : _tieredPhrase(
      normalizedSeverity,
      mild: _pickPhrase(_kStraightenHeadMildPhrases),
      moderate: _pickPhrase(_kStraightenHeadFromLeftModeratePhrases),
      strong: _pickPhrase(_kStraightenHeadFromLeftStrongPhrases),
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
        confidence: Confidence.decisionConfidence(
          Confidence(subject.confidenceFor('faceAngleZDegrees')),
          Confidence(reference.confidenceFor('faceAngleZDegrees')),
        ).value,
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

    // NOTE: same isFrontCamera-flip pattern as _evaluateShoulderBalance
    // originally had. UNLIKE shoulderBalance/bodyYaw (custom atan2 math over
    // pose landmarks, confirmed nowhere else mirrored), this reads ML Kit's
    // own face-detector headEulerAngleY directly — a different signal
    // source with its own, separately-documented front-camera sign
    // conventions we haven't independently verified here. Left unchanged;
    // vocabulary expanded only. To verify: face the front camera, turn your
    // head to one side only, and confirm this branch names the side you
    // actually turned toward.
    final subjectTurnedMoreTowardRight = isFrontCamera
        ? signedDiff < 0
        : signedDiff > 0;

    final phrase = subjectTurnedMoreTowardRight
        ? _tieredPhrase(
      normalizedSeverity,
      mild: _pickPhrase(_kTurnFaceLeftMildPhrases),
      moderate: _pickPhrase(_kTurnFaceLeftModeratePhrases),
      strong: _pickPhrase(_kTurnFaceLeftStrongPhrases),
    )
        : _tieredPhrase(
      normalizedSeverity,
      mild: _pickPhrase(_kTurnFaceRightMildPhrases),
      moderate: _pickPhrase(_kTurnFaceRightModeratePhrases),
      strong: _pickPhrase(_kTurnFaceRightStrongPhrases),
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
        confidence: Confidence.decisionConfidence(
          Confidence(subject.confidenceFor('faceAngleDegrees')),
          Confidence(reference.confidenceFor('faceAngleDegrees')),
        ).value,
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
        ? _tieredPhrase(
      normalizedSeverity,
      mild: _pickPhrase(_kShoulderBalanceMildPhrases),
      moderate: _pickPhrase(_kLiftLeftShoulderModeratePhrases),
      strong: _pickPhrase(_kLiftLeftShoulderStrongPhrases),
    )
        : _tieredPhrase(
      normalizedSeverity,
      mild: _pickPhrase(_kShoulderBalanceMildPhrases),
      moderate: _pickPhrase(_kLiftRightShoulderModeratePhrases),
      strong: _pickPhrase(_kLiftRightShoulderStrongPhrases),
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
      mild: _pickPhrase(_kRelaxShouldersMildPhrases),
      moderate: _pickPhrase(_kRelaxShouldersModeratePhrases),
      strong: _pickPhrase(_kRelaxShouldersStrongPhrases),
    )
        : _tieredPhrase(
      normalizedSeverity,
      mild: _pickPhrase(_kOpenShouldersMildPhrases),
      moderate: _pickPhrase(_kOpenShouldersModeratePhrases),
      strong: _pickPhrase(_kOpenShouldersStrongPhrases),
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

    // NOTE: same isFrontCamera-flip pattern as _evaluateShoulderBalance had
    // (see that method's note) — this one relies on the sign of
    // leftShoulder/rightShoulder .z (ML Kit depth), which we don't have an
    // independent, device-confirmed convention for the way we do for the
    // y-axis balance case. NOT changed here since flipping it blind, without
    // a matching real-device confirmation, risks trading a possible bug for
    // a different one. To verify: face the front camera, deliberately
    // rotate your torso one direction only, and confirm bodyYawEstimate
    // moves the way this branch assumes before trusting it the way
    // shoulderBalance's fix was confirmed.
    final subjectTurnedMoreTowardRight = isFrontCamera
        ? signedDiff < 0
        : signedDiff > 0;

    final phrase = subjectTurnedMoreTowardRight
        ? _tieredPhrase(
      normalizedSeverity,
      mild: _pickPhrase(_kTurnLeftMildPhrases),
      moderate: _pickPhrase(_kTurnLeftModeratePhrases),
      strong: _pickPhrase(_kTurnLeftStrongPhrases),
    )
        : _tieredPhrase(
      normalizedSeverity,
      mild: _pickPhrase(_kTurnRightMildPhrases),
      moderate: _pickPhrase(_kTurnRightModeratePhrases),
      strong: _pickPhrase(_kTurnRightStrongPhrases),
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

  // ---------------------------------------------------------------------
  // Arm position — ported from the standalone pose_and_face_evaluators.dart
  // (which was never wired into this engine's evaluateTiers(), so arm
  // position was never actually coached despite pose_analyzer.dart already
  // computing rightArmRaiseDegrees/leftArmRaiseDegrees/rightArmPoseCategory/
  // leftArmPoseCategory every frame). This is the single most visually
  // defining part of a pose like a raised hand near the face with the
  // other hand on the hip, so it's ported here with expanded phrasing
  // rather than left orphaned.
  // ---------------------------------------------------------------------

  static const Map<String, List<String>> _kArmPoseCategoryInstructions = {
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

  _AttributeEvaluation? _evaluateRightArmPosition(
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

  _AttributeEvaluation? _evaluateLeftArmPosition(
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

  _AttributeEvaluation? _evaluateArmPosition({
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
      final instruction = _pickPhrase(templates).replaceAll('{side}', side);
      final fallbackPhrase =
          '${instruction[0].toUpperCase()}${instruction.substring(1)}, like the reference';

      return _AttributeEvaluation(
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
        ? _pickPhrase(
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
        ? _pickPhrase(
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
    final fallbackPhrase =
        '${combined[0].toUpperCase()}${combined.substring(1)}';

    final direction = (raiseDeviation ?? -1) >= (elbowDeviation ?? -1)
        ? (raiseExceeds && subjectRaise! < referenceRaise!
        ? CoachingDirection.increase
        : CoachingDirection.decrease)
        : (elbowExceeds && subjectElbow! > referenceElbow!
        ? CoachingDirection.decrease
        : CoachingDirection.increase);

    return _AttributeEvaluation(
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
        confidence: Confidence.decisionConfidence(
          Confidence(subject.confidenceFor('mouthOpenRatio')),
          Confidence(reference.confidenceFor('mouthOpenRatio')),
        ).value,
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
        confidence: Confidence.decisionConfidence(
          Confidence(subject.confidenceFor('eyeOpenRatio')),
          Confidence(reference.confidenceFor('eyeOpenRatio')),
        ).value,
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