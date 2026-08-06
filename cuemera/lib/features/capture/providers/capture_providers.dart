// features/capture/providers/capture_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// Set to a user-facing message whenever the most recent capture (manual
/// or auto) saved to the local album fine but failed to save to the
/// device gallery. `camera_screen.dart` listens to this and shows a
/// snackbar, then clears it back to null.
final gallerySaveWarningProvider = StateProvider<String?>((ref) => null);

const gallerySaveFailedMessage =
    "Couldn't save to your gallery — the photo is still in your album.";

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

  ref.listen<bool>(shouldCaptureProvider, (previous, shouldCapture) async {
    if (shouldCapture != true) return;

    final referenceAsync = ref.read(referenceProfileProvider);
    final reference = referenceAsync.valueOrNull;
    if (reference == null) return;
    final tolerance = ref.read(toleranceSettingsProvider);

    await autoCaptureService.triggerCapture();

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

    final onFrame = ref.read(onFrameCallbackProvider);
    if (onFrame != null) {
      await cameraService.startImageStream(onFrame);
    }
  });
});

final capturedShotProvider = StateProvider<Shot?>((ref) => null);
