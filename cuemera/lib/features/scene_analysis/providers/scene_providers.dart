// features/scene_analysis/providers/scene_providers.dart
import 'package:camera/camera.dart';
import 'package:cuemera/core/services/tracking_engine.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/ml_kit_service.dart';
import '../../reference_photo/domain/models/reference_profile.dart';
import '../../reference_photo/providers/detection_thresholds_provider.dart';
import '../../reference_photo/providers/reference_providers.dart';
import '../domain/models/scene_profile.dart';
import '../domain/models/subject_profile.dart';
import '../services/face_analyzer.dart';
import '../services/pose_analyzer.dart';

final subjectProfileProvider = StateProvider<SubjectProfile>((ref) {
  return SubjectProfile(timestamp: DateTime.now());
});

final sceneProfileProvider = StateProvider<SceneProfile>((ref) {
  return const SceneProfile(
    brightness: 0.5,
    negativeSpaceScore: 0.0,
    symmetryScore: 0.0,
    backgroundClutterCount: 0,
  );
});

final onFrameCallbackProvider =
    StateProvider<void Function(CameraImage image)?>((ref) => null);

/// True once `MlKitService` has confirmed it's failing consistently
/// (typically the on-device pose/face/segmentation models failed to
/// download or initialize). Camera_screen shows a persistent banner while
/// this is true so the user knows why coaching/auto-capture have gone
/// quiet, instead of the app just silently doing nothing.
final mlKitUnavailableProvider = StateProvider<bool>((ref) => false);

final mlKitAvailabilityListenerProvider = Provider<void>((ref) {
  final mlKitService = ref.watch(mlKitServiceProvider);

  final subscription = mlKitService.unavailableStream.listen((unavailable) {
    ref.read(mlKitUnavailableProvider.notifier).state = unavailable;
  });

  ref.onDispose(subscription.cancel);
});

final poseAnalyzerProvider = Provider<PoseAnalyzer>((ref) => PoseAnalyzer());
final faceAnalyzerProvider = Provider<FaceAnalyzer>((ref) => FaceAnalyzer());
final trackingEngineProvider = Provider<TrackingEngine>((ref) {
  final thresholds = ref.watch(detectionThresholdsProvider);
  return TrackingEngine(thresholds: thresholds);
});

final targetSubjectProfileProvider = Provider<SubjectProfile>((ref) {
  final current = ref.watch(subjectProfileProvider);
  final referenceAsync = ref.watch(referenceProfileProvider);
  final ReferenceProfile? reference = referenceAsync.valueOrNull;

  if (reference != null) {
    return SubjectProfile(
      bodyRatio: reference.bodyRatio,
      faceAngleDegrees: reference.faceAngleDegrees,
      shoulderAngleDegrees: reference.shoulderAngleDegrees,
      eyesOpen: true,
      expression: reference.expression,
      timestamp: DateTime.now(),
    );
  }

  return SubjectProfile(
    bodyRatio: current.bodyRatio,
    faceAngleDegrees: 0.0,
    shoulderAngleDegrees: 0.0,
    eyesOpen: true,
    expression: 'smiling',
    timestamp: DateTime.now(),
  );
});

final targetSceneProfileProvider = Provider<SceneProfile>((ref) {
  final referenceAsync = ref.watch(referenceProfileProvider);
  final ReferenceProfile? reference = referenceAsync.valueOrNull;

  return SceneProfile(
    brightness: reference?.overallBrightness ?? 0.55,
    negativeSpaceScore: 0.0,
    symmetryScore: 0.0,
    backgroundClutterCount: reference?.backgroundClutterCount ?? 5,
  );
});

final trackingProgressProvider = Provider<double>((ref) {
  final current = ref.watch(subjectProfileProvider);
  final target = ref.watch(targetSubjectProfileProvider);
  final scene = ref.watch(sceneProfileProvider);
  final targetScene = ref.watch(targetSceneProfileProvider);
  final tolerance = ref.watch(toleranceSettingsProvider);
  final trackingEngine = ref.watch(trackingEngineProvider);
  return trackingEngine.trackingProgress(
    current,
    target,
    scene,
    targetScene,
    tolerance,
  );
});

final sceneAnalysisListenerProvider = Provider<void>((ref) {
  final mlKitService = ref.watch(mlKitServiceProvider);
  final poseAnalyzer = ref.watch(poseAnalyzerProvider);
  final faceAnalyzer = ref.watch(faceAnalyzerProvider);
  final trackingEngine = ref.watch(trackingEngineProvider);

  final subscription = mlKitService.analysisStream.listen((result) {
    final previous = ref.read(subjectProfileProvider);
    var raw = previous;

    if (result.poses != null) {
      raw = poseAnalyzer.analyzePose(result.poses, raw);
    }
    if (result.faces != null) {
      raw = faceAnalyzer.analyzeFace(result.faces, raw);
    }

    final smoothed = trackingEngine.smoothSubject(raw, previous);
    ref.read(subjectProfileProvider.notifier).state = smoothed;
  });

  ref.onDispose(subscription.cancel);
});
