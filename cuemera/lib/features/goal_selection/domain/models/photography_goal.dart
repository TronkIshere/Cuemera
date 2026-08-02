// features/goal_selection/domain/models/photography_goal.dart
enum PhotographyGoal { editorial, linkedin, travel, dating, beach, luxury }

class GoalStyleProfile {
  const GoalStyleProfile({
    required this.goal,
    required this.priorityWeights,
    required this.targetCompositionRules,
  });

  final PhotographyGoal goal;
  final Map<String, double> priorityWeights;
  final List<String> targetCompositionRules;
}

GoalStyleProfile getStyleProfile(PhotographyGoal goal) {
  switch (goal) {
    case PhotographyGoal.editorial:
      return const GoalStyleProfile(
        goal: PhotographyGoal.editorial,
        priorityWeights: {
          'composition': 0.3,
          'lighting': 0.25,
          'expression': 0.2,
          'background': 0.15,
          'story': 0.1,
        },
        targetCompositionRules: [
          'rule_of_thirds',
          'negative_space',
          'strong_angles',
        ],
      );
    case PhotographyGoal.linkedin:
      return const GoalStyleProfile(
        goal: PhotographyGoal.linkedin,
        priorityWeights: {
          'composition': 0.15,
          'lighting': 0.25,
          'expression': 0.35,
          'background': 0.2,
          'story': 0.05,
        },
        targetCompositionRules: [
          'centered_face',
          'clean_background',
          'eye_level',
        ],
      );
    case PhotographyGoal.travel:
      return const GoalStyleProfile(
        goal: PhotographyGoal.travel,
        priorityWeights: {
          'composition': 0.25,
          'lighting': 0.2,
          'expression': 0.15,
          'background': 0.25,
          'story': 0.15,
        },
        targetCompositionRules: [
          'environmental_context',
          'rule_of_thirds',
          'leading_lines',
        ],
      );
    case PhotographyGoal.dating:
      return const GoalStyleProfile(
        goal: PhotographyGoal.dating,
        priorityWeights: {
          'composition': 0.2,
          'lighting': 0.25,
          'expression': 0.35,
          'background': 0.1,
          'story': 0.1,
        },
        targetCompositionRules: ['warm_smile', 'soft_light', 'close_crop'],
      );
    case PhotographyGoal.beach:
      return const GoalStyleProfile(
        goal: PhotographyGoal.beach,
        priorityWeights: {
          'composition': 0.25,
          'lighting': 0.3,
          'expression': 0.2,
          'background': 0.15,
          'story': 0.1,
        },
        targetCompositionRules: [
          'golden_hour',
          'horizon_line',
          'negative_space',
        ],
      );
    case PhotographyGoal.luxury:
      return const GoalStyleProfile(
        goal: PhotographyGoal.luxury,
        priorityWeights: {
          'composition': 0.35,
          'lighting': 0.3,
          'expression': 0.15,
          'background': 0.15,
          'story': 0.05,
        },
        targetCompositionRules: [
          'symmetry',
          'strong_angles',
          'minimal_clutter',
        ],
      );
  }
}
