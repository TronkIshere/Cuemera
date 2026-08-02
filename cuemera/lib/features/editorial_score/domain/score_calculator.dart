// features/editorial_score/domain/score_calculator.dart
import '../../goal_selection/domain/models/photography_goal.dart';
import '../../scene_analysis/domain/models/scene_profile.dart';
import '../../scene_analysis/domain/models/subject_profile.dart';

class EditorialScore {
  const EditorialScore({
    required this.overall,
    required this.breakdown,
    this.nextSuggestion,
  });

  final int overall;
  final Map<String, int> breakdown;
  final String? nextSuggestion;
}

EditorialScore calculateScore(
  SubjectProfile subject,
  SceneProfile scene,
  PhotographyGoal goal,
) {
  final composition =
      ((scene.negativeSpaceScore * 0.5 + scene.symmetryScore * 0.5) * 100)
          .round()
          .clamp(0, 100);

  final lightingRaw = 1.0 - (scene.brightness - 0.55).abs() * 2;
  final lighting = (lightingRaw.clamp(0.0, 1.0) * 100).round();

  int expression = 60;
  if (subject.expression == 'smiling') expression = 90;
  if (subject.expression == 'serious') expression = 55;
  if (subject.eyesOpen == false) expression = 20;

  final backgroundRaw =
      1.0 - (scene.backgroundClutterCount / 10).clamp(0.0, 1.0);
  final background = (backgroundRaw * 100).round();

  final depthFactor = scene.depthEstimate != null ? 1.0 : 0.7;
  final story = (depthFactor * 75).round();

  final breakdown = {
    'composition': composition,
    'lighting': lighting,
    'expression': expression,
    'background': background,
    'story': story,
  };

  final weights = _weightsFor(goal);
  double weightedSum = 0;
  for (final entry in breakdown.entries) {
    weightedSum += entry.value * (weights[entry.key] ?? 0.2);
  }

  final overall = weightedSum.round().clamp(0, 100);

  String? suggestion;
  final lowest = breakdown.entries.reduce((a, b) => a.value < b.value ? a : b);
  if (lowest.value < 60) {
    suggestion = 'Improve ${lowest.key}';
  }

  return EditorialScore(
    overall: overall,
    breakdown: breakdown,
    nextSuggestion: suggestion,
  );
}

Map<String, double> _weightsFor(PhotographyGoal goal) {
  switch (goal) {
    case PhotographyGoal.editorial:
      return const {
        'composition': 0.3,
        'lighting': 0.25,
        'expression': 0.2,
        'background': 0.15,
        'story': 0.1,
      };
    case PhotographyGoal.linkedin:
      return const {
        'composition': 0.15,
        'lighting': 0.25,
        'expression': 0.35,
        'background': 0.2,
        'story': 0.05,
      };
    case PhotographyGoal.travel:
      return const {
        'composition': 0.25,
        'lighting': 0.2,
        'expression': 0.15,
        'background': 0.25,
        'story': 0.15,
      };
    case PhotographyGoal.dating:
      return const {
        'composition': 0.2,
        'lighting': 0.25,
        'expression': 0.35,
        'background': 0.1,
        'story': 0.1,
      };
    case PhotographyGoal.beach:
      return const {
        'composition': 0.25,
        'lighting': 0.3,
        'expression': 0.2,
        'background': 0.15,
        'story': 0.1,
      };
    case PhotographyGoal.luxury:
      return const {
        'composition': 0.35,
        'lighting': 0.3,
        'expression': 0.15,
        'background': 0.15,
        'story': 0.05,
      };
  }
}
