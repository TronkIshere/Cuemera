// features/capture/services/auto_capture_service.dart
import '../../scene_analysis/domain/models/scene_profile.dart';
import '../../scene_analysis/domain/models/subject_profile.dart';

class AutoCaptureService {
  DateTime? _lastCapture;

  bool shouldCapture(SubjectProfile subject, SceneProfile scene) {
    if (subject.eyesOpen == false) return false;
    if (scene.brightness < 0.2) return false;

    final shoulderOk =
        subject.shoulderAngleDegrees == null ||
        subject.shoulderAngleDegrees!.abs() < 15;
    final faceOk =
        subject.faceAngleDegrees == null ||
        subject.faceAngleDegrees!.abs() < 20;
    final backgroundOk = scene.backgroundClutterCount <= 5;

    if (!shoulderOk || !faceOk || !backgroundOk) return false;

    if (_lastCapture != null) {
      final elapsed = DateTime.now().difference(_lastCapture!);
      if (elapsed.inMilliseconds < 1500) return false;
    }

    return true;
  }

  Future<void> triggerCapture() async {
    _lastCapture = DateTime.now();
  }
}
