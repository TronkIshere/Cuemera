// features/capture/services/auto_capture_service.dart
import '../../reference_photo/domain/comparison_math.dart';
import '../../reference_photo/domain/models/reference_profile.dart';
import '../../reference_photo/domain/models/tolerance_settings.dart';
import '../../scene_analysis/domain/models/scene_profile.dart';
import '../../scene_analysis/domain/models/subject_profile.dart';

const double _minTrackingProgress = 0.9;

class AutoCaptureService {
  DateTime? _lastCapture;

  bool shouldCapture(
    SubjectProfile subject,
    SceneProfile scene,
    ReferenceProfile reference,
    ToleranceSettings tolerance,
    double trackingProgress,
  ) {
    if (subject.eyesOpen != true) return false;
    if (scene.brightness < 0.2) return false;

    final shoulderOk = _shoulderOk(subject, reference, tolerance);
    final faceOk = _faceOk(subject, reference, tolerance);
    final backgroundOk = scene.backgroundClutterCount <= 5;

    if (!shoulderOk || !faceOk || !backgroundOk) return false;

    if (trackingProgress < _minTrackingProgress) return false;

    if (_lastCapture != null) {
      final elapsed = DateTime.now().difference(_lastCapture!);
      if (elapsed.inMilliseconds < 1500) return false;
    }

    return true;
  }

  Future<void> triggerCapture() async {
    _lastCapture = DateTime.now();
  }

  Map<String, bool> debugConditionBreakdown(
    SubjectProfile subject,
    SceneProfile scene,
    ReferenceProfile reference,
    ToleranceSettings tolerance,
    double trackingProgress,
  ) {
    final shoulderOk = _shoulderOk(subject, reference, tolerance);
    final faceOk = _faceOk(subject, reference, tolerance);
    final backgroundOk = scene.backgroundClutterCount <= 5;
    final cooldownOk =
        _lastCapture == null ||
        DateTime.now().difference(_lastCapture!).inMilliseconds >= 1500;

    return {
      'eyesOpen': subject.eyesOpen == true,
      'brightness': scene.brightness >= 0.2,
      'shoulderAngle': shoulderOk,
      'faceAngle': faceOk,
      'backgroundClutter': backgroundOk,
      'trackingProgress': trackingProgress >= _minTrackingProgress,
      'cooldown': cooldownOk,
    };
  }

  bool _shoulderOk(
    SubjectProfile subject,
    ReferenceProfile reference,
    ToleranceSettings tolerance,
  ) {
    final subjectValue = subject.shoulderAngleDegrees;
    final referenceValue = reference.shoulderAngleDegrees;
    if (subjectValue == null || referenceValue == null) return true;

    final deviation = ComparisonMath.deviation(subjectValue, referenceValue);
    final threshold = ComparisonMath.thresholdForPose(tolerance.poseTolerance);
    return !ComparisonMath.exceedsThreshold(deviation, threshold);
  }

  bool _faceOk(
    SubjectProfile subject,
    ReferenceProfile reference,
    ToleranceSettings tolerance,
  ) {
    final subjectValue = subject.faceAngleDegrees;
    if (subjectValue == null) return false;
    final referenceValue = reference.faceAngleDegrees;
    if (referenceValue == null) return true;

    final deviation = ComparisonMath.deviation(subjectValue, referenceValue);
    final threshold = ComparisonMath.thresholdForPose(tolerance.poseTolerance);
    return !ComparisonMath.exceedsThreshold(deviation, threshold);
  }
}
