// features/voice_director/domain/action_plan.dart

import 'package:cuemera/features/voice_director/models/coaching_decision.dart';

enum ActionControllability {
  subjectAction,
  cameraAction,
  environmentAction,
  lightingAction,
  compositionAction,
  doNotCoach,
}

const Map<CoachingAttribute, ActionControllability> kAttributeControllability =
    {
      CoachingAttribute.shoulderAngle: ActionControllability.subjectAction,
      CoachingAttribute.facePitch: ActionControllability.subjectAction,
      CoachingAttribute.faceRoll: ActionControllability.subjectAction,
      CoachingAttribute.faceYaw: ActionControllability.subjectAction,
      CoachingAttribute.shoulderBalance: ActionControllability.subjectAction,
      CoachingAttribute.shoulderSpan: ActionControllability.subjectAction,
      CoachingAttribute.bodyYaw: ActionControllability.subjectAction,
      CoachingAttribute.mouthOpen: ActionControllability.subjectAction,
      CoachingAttribute.eyeOpen: ActionControllability.subjectAction,
      CoachingAttribute.expression: ActionControllability.subjectAction,

      CoachingAttribute.bodyRatio: ActionControllability.cameraAction,
      CoachingAttribute.negativeSpace: ActionControllability.compositionAction,
      CoachingAttribute.symmetry: ActionControllability.compositionAction,
      CoachingAttribute.backgroundClutter:
          ActionControllability.environmentAction,

      CoachingAttribute.brightness: ActionControllability.lightingAction,
      CoachingAttribute.warmth: ActionControllability.lightingAction,
      CoachingAttribute.hue: ActionControllability.lightingAction,
    };

const Map<CoachingAttribute, String> kExpectedVisualEffect = {
  CoachingAttribute.shoulderAngle: 'shoulder_line_matches_reference_tilt',
  CoachingAttribute.facePitch: 'chin_angle_matches_reference',
  CoachingAttribute.faceRoll: 'head_tilt_matches_reference',
  CoachingAttribute.faceYaw: 'face_turn_matches_reference',
  CoachingAttribute.shoulderBalance: 'shoulder_height_levelled',
  CoachingAttribute.shoulderSpan: 'shoulder_width_matches_reference',
  CoachingAttribute.bodyYaw: 'torso_rotation_matches_reference',
  CoachingAttribute.mouthOpen: 'mouth_openness_matches_reference',
  CoachingAttribute.eyeOpen: 'eye_openness_matches_reference',
  CoachingAttribute.expression: 'expression_matches_target',
  CoachingAttribute.bodyRatio: 'framing_matches_reference_proportions',
  CoachingAttribute.negativeSpace: 'frame_fill_matches_reference',
  CoachingAttribute.symmetry: 'subject_centered_in_frame',
  CoachingAttribute.backgroundClutter: 'background_busyness_reduced',
  CoachingAttribute.brightness: 'exposure_matches_reference',
  CoachingAttribute.warmth: 'color_temperature_matches_reference',
  CoachingAttribute.hue: 'dominant_hue_matches_reference',
};

class ActionPlan {
  const ActionPlan({
    required this.phrase,
    required this.decision,
    required this.sourceLayer,
    required this.confidence,
    required this.controllability,
  });

  final String phrase;
  final CoachingDecision decision;
  final String sourceLayer;

  final double confidence;

  final ActionControllability controllability;

  double get severity => decision.normalizedSeverity;

  String get expectedVisualEffect =>
      kExpectedVisualEffect[decision.attribute] ?? 'unspecified';

  String debugLine(int priorityRank, {required bool eligible}) =>
      'DECISION: candidate=${decision.attribute.name} severity=${severity.toStringAsFixed(2)} '
      'confidence=${confidence.toStringAsFixed(2)} priority=$priorityRank eligible=$eligible\n'
      'ACTION: attribute=${decision.attribute.name} direction=${decision.direction.name} '
      'controllability=${controllability.name} expectedEffect=$expectedVisualEffect';
}

typedef PriorityAction = ActionPlan;

ActionPlan? pickBest(List<ActionPlan> tierCandidates) {
  final eligible = tierCandidates
      .where((c) => c.controllability != ActionControllability.doNotCoach)
      .toList();
  if (eligible.isEmpty) return null;

  eligible.sort((a, b) {
    final severityCompare = b.severity.compareTo(a.severity);
    if (severityCompare != 0) return severityCompare;
    return b.confidence.compareTo(a.confidence);
  });
  return eligible.first;
}

ActionPlan? pickAcrossTiers({
  required List<ActionPlan> poseAndFace,
  required List<ActionPlan> composition,
  required List<ActionPlan> lighting,
  required int tierRotation,
}) {
  final poseBest = pickBest(poseAndFace);
  final compBest = pickBest(composition);
  final lightBest = pickBest(lighting);

  bool isReal(ActionPlan? a) =>
      a != null && a.decision.severityBand != CoachingSeverityBand.mild;

  if (isReal(poseBest)) return poseBest;
  if (isReal(compBest)) return compBest;
  if (isReal(lightBest)) return lightBest;

  final candidates = [
    poseBest,
    compBest,
    lightBest,
  ].whereType<ActionPlan>().toList();
  if (candidates.isEmpty) return null;
  return candidates[tierRotation % candidates.length];
}

class DirectionalContract {
  const DirectionalContract({required this.attribute, required this.direction});

  final CoachingAttribute attribute;
  final CoachingDirection direction;

  bool validate(String phrase) =>
      DirectionWordChecker.isConsistent(phrase, direction);
}

class DirectionWordChecker {
  DirectionWordChecker._();

  static const _leftWords = ['left', 'counterclockwise'];
  static const _rightWords = ['right', 'clockwise'];

  static bool isConsistent(String phrase, CoachingDirection direction) {
    final lower = phrase.toLowerCase();
    final hasLeft = _leftWords.any(lower.contains);
    final hasRight = _rightWords.any(lower.contains);

    if (direction == CoachingDirection.left) return !hasRight;
    if (direction == CoachingDirection.right) return !hasLeft;

    if (hasLeft && hasRight) return false;
    return true;
  }
}
