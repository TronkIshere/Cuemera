// features/voice_director/domain/editorial_rules.dart
import '../../goal_selection/domain/models/photography_goal.dart';
import '../../scene_analysis/domain/models/scene_profile.dart';
import '../../scene_analysis/domain/models/subject_profile.dart';

class RuleCondition {
  const RuleCondition({
    required this.matches,
    required this.directionPhrase,
    required this.severity,
  });

  final bool Function(SubjectProfile subject, SceneProfile scene) matches;
  final String directionPhrase;
  final int severity;
}

List<RuleCondition> rulesFor(PhotographyGoal goal) {
  final common = <RuleCondition>[
    RuleCondition(
      matches: (subject, scene) => subject.eyesOpen == false,
      directionPhrase: 'Open your eyes',
      severity: 9,
    ),
    RuleCondition(
      matches: (subject, scene) => scene.brightness < 0.25,
      directionPhrase: 'Find more light',
      severity: 8,
    ),
    RuleCondition(
      matches: (subject, scene) => scene.brightness > 0.9,
      directionPhrase: 'Step out of direct light',
      severity: 6,
    ),
    RuleCondition(
      matches: (subject, scene) =>
          subject.shoulderAngleDegrees != null &&
          subject.shoulderAngleDegrees!.abs() > 20,
      directionPhrase: 'Square your shoulders',
      severity: 5,
    ),
    RuleCondition(
      matches: (subject, scene) =>
          subject.faceAngleDegrees != null &&
          subject.faceAngleDegrees!.abs() > 35,
      directionPhrase: 'Turn your face toward me',
      severity: 6,
    ),
    RuleCondition(
      matches: (subject, scene) => scene.backgroundClutterCount > 5,
      directionPhrase: 'Move to a cleaner background',
      severity: 7,
    ),
  ];

  switch (goal) {
    case PhotographyGoal.editorial:
      return [
        ...common,
        RuleCondition(
          matches: (subject, scene) => scene.negativeSpaceScore < 0.3,
          directionPhrase: 'Give me more space in the frame',
          severity: 4,
        ),
      ];
    case PhotographyGoal.linkedin:
      return [
        ...common,
        RuleCondition(
          matches: (subject, scene) => subject.expression != 'smiling',
          directionPhrase: 'Give a warm smile',
          severity: 5,
        ),
        RuleCondition(
          matches: (subject, scene) => scene.symmetryScore < 0.5,
          directionPhrase: 'Center yourself in frame',
          severity: 4,
        ),
      ];
    case PhotographyGoal.travel:
      return [
        ...common,
        RuleCondition(
          matches: (subject, scene) => scene.negativeSpaceScore < 0.2,
          directionPhrase: 'Step back to show the scene',
          severity: 5,
        ),
      ];
    case PhotographyGoal.dating:
      return [
        ...common,
        RuleCondition(
          matches: (subject, scene) => subject.expression != 'smiling',
          directionPhrase: 'Relax and smile naturally',
          severity: 6,
        ),
      ];
    case PhotographyGoal.beach:
      return [
        ...common,
        RuleCondition(
          matches: (subject, scene) => scene.lightDirectionDegrees == null,
          directionPhrase: 'Face toward the sun',
          severity: 4,
        ),
      ];
    case PhotographyGoal.luxury:
      return [
        ...common,
        RuleCondition(
          matches: (subject, scene) => scene.symmetryScore < 0.7,
          directionPhrase: 'Align yourself to center',
          severity: 6,
        ),
      ];
  }
}
