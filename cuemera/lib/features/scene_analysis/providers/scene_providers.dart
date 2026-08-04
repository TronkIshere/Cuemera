// features/scene_analysis/providers/scene_providers.dart
import 'package:cuemera/core/services/tracking_engine.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/camera_service.dart';
import '../../../core/services/ml_kit_service.dart';
import '../../reference_photo/domain/models/reference_profile.dart';
import '../../reference_photo/providers/reference_providers.dart';
import '../domain/models/scene_profile.dart';
import '../domain/models/subject_profile.dart';
import '../services/face_analyzer.dart';
import '../services/light_analyzer.dart';
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

final poseAnalyzerProvider = Provider<PoseAnalyzer>((ref) => PoseAnalyzer());
final faceAnalyzerProvider = Provider<FaceAnalyzer>((ref) => FaceAnalyzer());
final lightAnalyzerProvider = Provider<LightAnalyzer>((ref) => LightAnalyzer());
final trackingEngineProvider = Provider<TrackingEngine>(
  (ref) => TrackingEngine(),
);

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

final trackingProgressProvider = Provider<double>((ref) {
  final current = ref.watch(subjectProfileProvider);
  final target = ref.watch(targetSubjectProfileProvider);
  final trackingEngine = ref.watch(trackingEngineProvider);
  return trackingEngine.trackingProgress(current, target);
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

final lightAnalysisListenerProvider = Provider<void>((ref) {
  final cameraService = ref.watch(cameraServiceProvider);
  final lightAnalyzer = ref.watch(lightAnalyzerProvider);
  final trackingEngine = ref.watch(trackingEngineProvider);

  cameraService.startImageStream((image) {
    final previous = ref.read(sceneProfileProvider);
    final raw = lightAnalyzer.analyzeLight(image, previous);
    final smoothed = trackingEngine.smoothScene(raw, previous);
    ref.read(sceneProfileProvider.notifier).state = smoothed;
  });

  ref.onDispose(() {
    cameraService.stopImageStream();
  });
});
