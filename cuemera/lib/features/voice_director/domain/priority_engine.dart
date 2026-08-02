// features/voice_director/domain/priority_engine.dart
import '../../goal_selection/domain/models/photography_goal.dart';
import '../../scene_analysis/domain/models/scene_profile.dart';
import '../../scene_analysis/domain/models/subject_profile.dart';
import 'editorial_rules.dart';

class PriorityAction {
  const PriorityAction({
    required this.phrase,
    required this.severity,
    required this.sourceLayer,
  });

  final String phrase;
  final int severity;
  final String sourceLayer;
}

PriorityAction? getNextAction(
  SubjectProfile subject,
  SceneProfile scene,
  PhotographyGoal goal,
) {
  final rules = rulesFor(goal);

  RuleCondition? best;
  for (final rule in rules) {
    if (!rule.matches(subject, scene)) continue;
    if (best == null || rule.severity > best.severity) {
      best = rule;
    }
  }

  if (best == null) return null;

  return PriorityAction(
    phrase: best.directionPhrase,
    severity: best.severity,
    sourceLayer: 'editorial_rules',
  );
}
