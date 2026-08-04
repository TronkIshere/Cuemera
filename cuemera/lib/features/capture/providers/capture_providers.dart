// features/capture/providers/capture_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/camera_service.dart';
import '../../album/domain/models/shot.dart';
import '../../reference_photo/providers/reference_providers.dart';
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
  final referenceAsync = ref.watch(referenceProfileProvider);
  final tolerance = ref.watch(toleranceSettingsProvider);

  final reference = referenceAsync.valueOrNull;
  if (reference == null) return false;

  return autoCaptureService.shouldCapture(
    subject,
    scene,
    reference,
    tolerance,
    trackingProgress,
  );
});

final autoCaptureProvider = Provider<void>((ref) {
  final autoCaptureService = ref.watch(autoCaptureServiceProvider);
  final cameraService = ref.watch(cameraServiceProvider);

  ref.listen<bool>(shouldCaptureProvider, (previous, shouldCapture) async {
    if (shouldCapture != true) return;

    final referenceAsync = ref.read(referenceProfileProvider);
    final reference = referenceAsync.valueOrNull;
    if (reference == null) return;
    final tolerance = ref.read(toleranceSettingsProvider);

    await autoCaptureService.triggerCapture();

    final subject = ref.read(subjectProfileProvider);
    final scene = ref.read(sceneProfileProvider);

    final shot = buildShotFromCapture(
      imagePath: null,
      subject: subject,
      scene: scene,
      reference: reference,
      tolerance: tolerance,
      shotType: 'hero',
    );

    ref.read(capturedShotProvider.notifier).state = shot;
  });
});

final capturedShotProvider = StateProvider<Shot?>((ref) => null);
