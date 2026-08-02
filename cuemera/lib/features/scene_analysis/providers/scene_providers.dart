// features/scene_analysis/providers/scene_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/camera_service.dart';
import '../../../core/services/ml_kit_service.dart';
import '../domain/models/scene_profile.dart';
import '../domain/models/subject_profile.dart';
import '../services/face_analyzer.dart';
import '../services/light_analyzer.dart';
import '../services/pose_analyzer.dart';
import '../services/tracking_engine.dart';

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
