// features/voice_director/domain/reference_comparison_engine.dart
import 'package:cuemera/features/voice_director/domain/action_plan.dart';
import 'package:cuemera/features/voice_director/domain/root_cause_engine.dart';
import 'package:flutter/foundation.dart';

import '../../reference_photo/domain/models/reference_profile.dart';
import '../../reference_photo/domain/models/tolerance_settings.dart';
import '../../scene_analysis/domain/models/scene_profile.dart';
import '../../scene_analysis/domain/models/subject_profile.dart';
import 'reference_comparison/attribute_evaluation.dart';
import 'reference_comparison/composition_evaluators.dart';
import 'reference_comparison/lighting_evaluators.dart';
import 'reference_comparison/pose_and_face_evaluators.dart';

class ReferenceComparisonEngine {
  final RootCauseEngine _rootCause = const RootCauseEngine();
  int _tierRotation = 0;

  ActionPlan _toActionPlan(AttributeEvaluation evaluation) {
    return ActionPlan(
      phrase: evaluation.phrase,
      decision: evaluation.decision,
      sourceLayer: 'reference_comparison_engine',
      confidence: evaluation.decision.confidence,
      controllability: evaluation.decision.controllability,
    );
  }

  /// Builds the three tiers' exceeding-threshold candidates as [ActionPlan]s
  /// (pose/face root-cause-collapsed), without picking a single winner —
  /// shared by [evaluate] (which picks one via [pickAcrossTiers]) and the
  /// state-machine listener (step 10), which needs the raw per-tier lists
  /// for its own eligibility filtering + selection.
  TierCandidates evaluateTiers({
    required SubjectProfile subject,
    required SceneProfile scene,
    required ReferenceProfile reference,
    required ToleranceSettings tolerance,
  }) {
    final poseAndFaceTier = <AttributeEvaluation>[];
    final compositionTier = <AttributeEvaluation>[];
    final lightingTier = <AttributeEvaluation>[];

    void addIfPresent(
      List<AttributeEvaluation> tier,
      AttributeEvaluation? evaluation,
    ) {
      if (evaluation != null) tier.add(evaluation);
    }

    addIfPresent(
      poseAndFaceTier,
      evaluateShoulderAngle(subject, reference, tolerance),
    );
    addIfPresent(
      poseAndFaceTier,
      evaluateFacePitch(subject, reference, tolerance),
    );
    addIfPresent(
      poseAndFaceTier,
      evaluateFaceRoll(subject, reference, tolerance),
    );
    addIfPresent(
      poseAndFaceTier,
      evaluateBodyRatio(subject, reference, tolerance),
    );
    addIfPresent(
      poseAndFaceTier,
      evaluateMouthOpen(subject, reference, tolerance),
    );
    addIfPresent(
      poseAndFaceTier,
      evaluateEyeOpen(subject, reference, tolerance),
    );
    addIfPresent(
      poseAndFaceTier,
      evaluateExpression(subject, reference, tolerance),
    );
    addIfPresent(
      poseAndFaceTier,
      evaluateShoulderBalance(subject, reference, tolerance),
    );
    addIfPresent(
      poseAndFaceTier,
      evaluateShoulderSpan(subject, reference, tolerance),
    );
    addIfPresent(
      poseAndFaceTier,
      evaluateBodyYaw(subject, reference, tolerance),
    );
    addIfPresent(
      poseAndFaceTier,
      evaluateRightArmPosition(subject, reference, tolerance),
    );
    addIfPresent(
      poseAndFaceTier,
      evaluateLeftArmPosition(subject, reference, tolerance),
    );

    addIfPresent(
      compositionTier,
      evaluateNegativeSpace(scene, reference, tolerance),
    );
    addIfPresent(
      compositionTier,
      evaluateSymmetry(scene, reference, tolerance),
    );
    addIfPresent(
      compositionTier,
      evaluateBackgroundClutter(scene, reference, tolerance),
    );

    addIfPresent(lightingTier, evaluateBrightness(scene, reference, tolerance));
    addIfPresent(lightingTier, evaluateWarmth(scene, reference, tolerance));
    addIfPresent(lightingTier, evaluateHue(scene, reference, tolerance));

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

    debugPrint(
      'pick_worst: pose=[${poseCandidates.map((c) => '${c.decision.attribute.name}=${c.severity.toStringAsFixed(3)}').join(', ')}] '
      'composition=[${compositionCandidates.map((c) => '${c.decision.attribute.name}=${c.severity.toStringAsFixed(3)}').join(', ')}] '
      'lighting=[${lightingCandidates.map((c) => '${c.decision.attribute.name}=${c.severity.toStringAsFixed(3)}').join(', ')}]',
    );

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
  }) {
    final tiers = evaluateTiers(
      subject: subject,
      scene: scene,
      reference: reference,
      tolerance: tolerance,
    );

    final chosen = pickAcrossTiers(
      poseAndFace: tiers.poseAndFace,
      composition: tiers.composition,
      lighting: tiers.lighting,
      tierRotation: _tierRotation,
    );
    _tierRotation++;
    return chosen;
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
