// features/capture/providers/capture_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/app_tts_service.dart';
import '../../../core/services/camera_service.dart';
import '../../album/domain/models/album_state.dart';
import '../../album/domain/models/shot.dart';
import '../../reference_photo/providers/detection_thresholds_provider.dart';
import '../../reference_photo/providers/reference_providers.dart';
import '../../scene_analysis/providers/scene_providers.dart';
import '../domain/shot_builder.dart';
import '../services/auto_capture_service.dart';

final selectedShotTypeProvider = StateProvider<String>(
  (ref) => AlbumState.shotTypes.first,
);

final gallerySaveWarningProvider = StateProvider<String?>((ref) => null);

const gallerySaveFailedMessage =
    "Couldn't save to your gallery — the photo is still in your album.";

const holdStillPhrase = 'Hold still.';

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
  final thresholds = ref.watch(detectionThresholdsProvider);

  final reference = referenceAsync.valueOrNull;
  if (reference == null) return false;

  return autoCaptureService.shouldCapture(
    subject,
    scene,
    reference,
    tolerance,
    trackingProgress,
    thresholds,
  );
});

final autoCaptureProvider = Provider<void>((ref) {
  final autoCaptureService = ref.watch(autoCaptureServiceProvider);
  final cameraService = ref.watch(cameraServiceProvider);
  final ttsService = ref.watch(appTtsServiceProvider);

  var captureInFlight = false;

  ref.listen<bool>(shouldCaptureProvider, (previous, shouldCapture) async {
    if (shouldCapture != true || captureInFlight) return;
    captureInFlight = true;

    try {
      final referenceAsync = ref.read(referenceProfileProvider);
      final reference = referenceAsync.valueOrNull;
      if (reference == null) return;
      final tolerance = ref.read(toleranceSettingsProvider);

      await autoCaptureService.triggerCapture();

      await ttsService.speak(holdStillPhrase, force: true);

      final imagePath = await cameraService.capture();
      if (cameraService.lastGallerySaveSucceeded == false) {
        ref.read(gallerySaveWarningProvider.notifier).state =
            gallerySaveFailedMessage;
      }

      final subject = ref.read(subjectProfileProvider);
      final scene = ref.read(sceneProfileProvider);

      final shot = buildShotFromCapture(
        imagePath: imagePath,
        subject: subject,
        scene: scene,
        reference: reference,
        tolerance: tolerance,
        shotType: ref.read(selectedShotTypeProvider),
      );

      ref.read(capturedShotProvider.notifier).state = shot;
    } finally {
      captureInFlight = false;
    }
  });
});

final capturedShotProvider = StateProvider<Shot?>((ref) => null);
