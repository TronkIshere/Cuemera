// features/scene_analysis/providers/scene_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/camera_service.dart';
import '../../../core/services/ml_kit_service.dart';
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

final sceneAnalysisListenerProvider = Provider<void>((ref) {
  final mlKitService = ref.watch(mlKitServiceProvider);
  final cameraService = ref.watch(cameraServiceProvider);
  final poseAnalyzer = ref.watch(poseAnalyzerProvider);
  final faceAnalyzer = ref.watch(faceAnalyzerProvider);
  final lightAnalyzer = ref.watch(lightAnalyzerProvider);

  final subscription = mlKitService.analysisStream.listen((result) {
    var subject = ref.read(subjectProfileProvider);

    if (result.poses != null) {
      subject = poseAnalyzer.analyzePose(result.poses, subject);
    }
    if (result.faces != null) {
      subject = faceAnalyzer.analyzeFace(result.faces, subject);
    }

    ref.read(subjectProfileProvider.notifier).state = subject;
  });

  ref.onDispose(subscription.cancel);
});

final lightAnalysisListenerProvider = Provider<void>((ref) {
  final cameraService = ref.watch(cameraServiceProvider);
  final lightAnalyzer = ref.watch(lightAnalyzerProvider);

  cameraService.startImageStream((image) {
    final scene = ref.read(sceneProfileProvider);
    final updated = lightAnalyzer.analyzeLight(image, scene);
    ref.read(sceneProfileProvider.notifier).state = updated;
  });

  ref.onDispose(() {
    cameraService.stopImageStream();
  });
});
