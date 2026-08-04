// features/capture/domain/shot_builder.dart
import '../../album/domain/models/shot.dart';
import '../../editorial_score/domain/score_calculator.dart';
import '../../reference_photo/domain/models/reference_profile.dart';
import '../../reference_photo/domain/models/tolerance_settings.dart';
import '../../scene_analysis/domain/models/scene_profile.dart';
import '../../scene_analysis/domain/models/subject_profile.dart';

Shot buildShotFromCapture({
  required String? imagePath,
  required SubjectProfile subject,
  required SceneProfile scene,
  required ReferenceProfile reference,
  required ToleranceSettings tolerance,
  required String shotType,
}) {
  final score = calculateReferenceScore(subject, scene, reference, tolerance);

  return Shot(
    id: DateTime.now().millisecondsSinceEpoch.toString(),
    score: score,
    timestamp: DateTime.now(),
    shotType: shotType,
    imagePath: imagePath,
  );
}
