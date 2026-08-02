// features/capture/providers/capture_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/camera_service.dart';
import '../../album/domain/models/shot.dart';
import '../../goal_selection/providers/goal_providers.dart';
import '../../scene_analysis/providers/scene_providers.dart';
import '../domain/shot_builder.dart';
import '../services/auto_capture_service.dart';

final autoCaptureServiceProvider = Provider<AutoCaptureService>((ref) {
  return AutoCaptureService();
});

final shouldCaptureProvider = Provider<bool>((ref) {
  final subject = ref.watch(subjectProfileProvider);
  final scene = ref.watch(sceneProfileProvider);
  final trackingProgress = ref.watch(trackingProgressProvider);
  final autoCaptureService = ref.watch(autoCaptureServiceProvider);

  return autoCaptureService.shouldCapture(subject, scene, trackingProgress);
});

final autoCaptureProvider = Provider<void>((ref) {
  final autoCaptureService = ref.watch(autoCaptureServiceProvider);
  final cameraService = ref.watch(cameraServiceProvider);

  ref.listen<bool>(shouldCaptureProvider, (previous, shouldCapture) async {
    if (shouldCapture != true) return;

    await autoCaptureService.triggerCapture();

    final subject = ref.read(subjectProfileProvider);
    final scene = ref.read(sceneProfileProvider);
    final goal = ref.read(selectedGoalProvider);
    if (goal == null) return;

    final shot = buildShotFromCapture(
      imagePath: null,
      subject: subject,
      scene: scene,
      goal: goal,
      shotType: 'hero',
    );

    ref.read(capturedShotProvider.notifier).state = shot;
  });
});

final capturedShotProvider = StateProvider<Shot?>((ref) => null);
