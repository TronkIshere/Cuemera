// features/scene_analysis/providers/scene_providers.dart
import 'package:camera/camera.dart';
import 'package:cuemera/core/services/tracking_engine.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analysis/analysis_constants.dart';
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
    symmetryScore: 0.5,
    backgroundClutterCount: 0,
  );
});

final onFrameCallbackProvider =
    StateProvider<void Function(CameraImage image)?>((ref) => null);

final mlKitUnavailableProvider = StateProvider<bool>((ref) => false);

final isFrontCameraProvider = StateProvider<bool>((ref) => false);

final mlKitAvailabilityListenerProvider = Provider.autoDispose<void>((ref) {
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

void resetLiveAnalyzers(Ref ref) {
  ref.read(poseAnalyzerProvider).reset();
  ref.read(faceAnalyzerProvider).reset();
}

final targetSubjectProfileProvider = Provider<SubjectProfile>((ref) {
  final referenceAsync = ref.watch(referenceProfileProvider);
  final ReferenceProfile? reference = referenceAsync.valueOrNull;

  if (reference != null) {
    return SubjectProfile(
      bodyRatio: reference.bodyRatio,
      faceAngleDegrees: reference.faceAngleDegrees,
      faceAngleXDegrees: reference.faceAngleXDegrees,
      faceAngleZDegrees: reference.faceAngleZDegrees,
      mouthOpenRatio: reference.mouthOpenRatio,
      eyeOpenRatio: reference.eyeOpenRatio,
      shoulderAngleDegrees: reference.shoulderAngleDegrees,
      shoulderBalanceRatio: reference.shoulderBalanceRatio,
      shoulderSpanRatio: reference.shoulderSpanRatio,
      bodyYawEstimate: reference.bodyYawEstimate,
      leftArmRaiseDegrees: reference.leftArmRaiseDegrees,
      rightArmRaiseDegrees: reference.rightArmRaiseDegrees,
      leftElbowAngleDegrees: reference.leftElbowAngleDegrees,
      rightElbowAngleDegrees: reference.rightElbowAngleDegrees,
      leftArmPoseCategory: reference.leftArmPoseCategory,
      rightArmPoseCategory: reference.rightArmPoseCategory,
      eyesOpen: null,
      expression: reference.expression,
      metricConfidence: reference.metricConfidence,
      timestamp: DateTime.now(),
    );
  }

  return SubjectProfile(timestamp: DateTime.now());
});

final targetSceneProfileProvider = Provider<SceneProfile>((ref) {
  final referenceAsync = ref.watch(referenceProfileProvider);
  final ReferenceProfile? reference = referenceAsync.valueOrNull;

  return SceneProfile(
    brightness: reference?.overallBrightness ?? 0.55,
    lightDirectionDegrees: reference?.lightDirectionDegrees,
    negativeSpaceScore: reference?.negativeSpaceScore ?? 0.5,
    symmetryScore: reference?.symmetryScore ?? 0.5,
    subjectHorizontalPosition: reference?.subjectHorizontalPosition,
    backgroundClutterCount:
        reference?.backgroundClutterCount ?? (kClutterScoreCeiling / 2).round(),
    liveWarmthScore: reference?.warmthScore,
    liveDominantHue: reference?.dominantHue,
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

final sceneAnalysisListenerProvider = Provider.autoDispose<void>((ref) {
  final mlKitService = ref.watch(mlKitServiceProvider);
  final poseAnalyzer = ref.watch(poseAnalyzerProvider);
  final faceAnalyzer = ref.watch(faceAnalyzerProvider);
  final trackingEngine = ref.watch(trackingEngineProvider);

  final subscription = mlKitService.analysisStream.listen((result) {
    final previous = ref.read(subjectProfileProvider);
    final at = DateTime.now();

    var raw = poseAnalyzer.analyzePose(result.poses, previous, now: at);
    raw = faceAnalyzer.analyzeFace(result.faces, raw, now: at);

    final poseDetected = result.poses != null && result.poses!.isNotEmpty;
    final faceDetected = result.faces != null && result.faces!.isNotEmpty;

    final smoothed = trackingEngine
        .smoothSubject(raw, previous)
        .copyWith(
          subjectFullyInFrame: poseDetected,
          detectorsAgree: poseDetected && faceDetected,
          timestamp: at,
        );
    ref.read(subjectProfileProvider.notifier).state = smoothed;
  });

  ref.onDispose(subscription.cancel);
});
