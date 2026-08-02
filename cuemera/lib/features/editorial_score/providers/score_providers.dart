// features/editorial_score/providers/score_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../goal_selection/providers/goal_providers.dart';
import '../../scene_analysis/providers/scene_providers.dart';
import '../domain/score_calculator.dart';

final currentScoreProvider = Provider<EditorialScore?>((ref) {
  final subject = ref.watch(subjectProfileProvider);
  final scene = ref.watch(sceneProfileProvider);
  final goal = ref.watch(selectedGoalProvider);

  if (goal == null) return null;

  return calculateScore(subject, scene, goal);
});
