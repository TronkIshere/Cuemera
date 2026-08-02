// features/goal_selection/providers/goal_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/photography_goal.dart';

final selectedGoalProvider = StateProvider<PhotographyGoal?>((ref) => null);

final styleProfileProvider = Provider<GoalStyleProfile?>((ref) {
  final goal = ref.watch(selectedGoalProvider);
  if (goal == null) return null;
  return getStyleProfile(goal);
});
