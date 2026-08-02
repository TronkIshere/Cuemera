// features/capture/domain/shot_builder.dart
import '../../album/domain/models/shot.dart';
import '../../editorial_score/domain/score_calculator.dart';
import '../../goal_selection/domain/models/photography_goal.dart';
import '../../scene_analysis/domain/models/scene_profile.dart';
import '../../scene_analysis/domain/models/subject_profile.dart';

Shot buildShotFromCapture({
  required String? imagePath,
  required SubjectProfile subject,
  required SceneProfile scene,
  required PhotographyGoal goal,
  required String shotType,
}) {
  final score = calculateScore(subject, scene, goal);

  return Shot(
    id: DateTime.now().millisecondsSinceEpoch.toString(),
    score: score,
    timestamp: DateTime.now(),
    shotType: shotType,
    imagePath: imagePath,
  );
}
