// features/capture/services/auto_capture_service.dart
import '../../reference_photo/domain/comparison_math.dart';
import '../../reference_photo/domain/models/detection_thresholds.dart';
import '../../reference_photo/domain/models/reference_profile.dart';
import '../../reference_photo/domain/models/tolerance_settings.dart';
import '../../scene_analysis/domain/models/scene_profile.dart';
import '../../scene_analysis/domain/models/subject_profile.dart';

class AutoCaptureService {
  DateTime? _lastCapture;

  bool shouldCapture(
    SubjectProfile subject,
    SceneProfile scene,
    ReferenceProfile reference,
    ToleranceSettings tolerance,
    double trackingProgress,
    DetectionThresholds thresholds,
  ) {
    // `eyesOpen` is currently disabled upstream (FaceAnalyzer always
    // produces null for it), so this is intentionally no longer a gate —
    // previously `subject.eyesOpen != true` would have permanently blocked
    // every capture once the signal went permanently null.
    if (scene.brightness < thresholds.minBrightnessForCapture) return false;

    // For each _xOk check below: reference null means the attribute isn't
    // part of what we're matching (auto-pass). Subject null with a
    // non-null reference means we can't currently measure it — e.g. the
    // subject's shoulders/hips aren't in frame — and that must block
    // capture, not silently pass, or a close-up-only framing bypasses
    // pose matching entirely.

    final shoulderOk = _shoulderOk(subject, reference, tolerance);
    final faceOk = _faceOk(subject, reference, tolerance);
    final facePitchOk = _facePitchOk(subject, reference, tolerance);
    final faceRollOk = _faceRollOk(subject, reference, tolerance);
    final bodyRatioOk = _bodyRatioOk(subject, reference, tolerance);
    final mouthOpenOk = _mouthOpenOk(subject, reference, tolerance);
    final negativeSpaceOk = _negativeSpaceOk(scene, reference, tolerance);
    final symmetryOk = _symmetryOk(scene, reference, tolerance);
    final backgroundOk = _backgroundOk(scene, reference, tolerance, thresholds);

    if (!shoulderOk ||
        !faceOk ||
        !facePitchOk ||
        !faceRollOk ||
        !bodyRatioOk ||
        !mouthOpenOk ||
        !negativeSpaceOk ||
        !symmetryOk ||
        !backgroundOk) {
      return false;
    }

    if (trackingProgress < thresholds.minTrackingProgressForCapture) {
      return false;
    }

    if (_lastCapture != null) {
      final elapsed = DateTime.now().difference(_lastCapture!);
      if (elapsed.inMilliseconds < thresholds.captureCooldownMs) return false;
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
    DetectionThresholds thresholds,
  ) {
    final shoulderOk = _shoulderOk(subject, reference, tolerance);
    final faceOk = _faceOk(subject, reference, tolerance);
    final facePitchOk = _facePitchOk(subject, reference, tolerance);
    final faceRollOk = _faceRollOk(subject, reference, tolerance);
    final bodyRatioOk = _bodyRatioOk(subject, reference, tolerance);
    final mouthOpenOk = _mouthOpenOk(subject, reference, tolerance);
    final negativeSpaceOk = _negativeSpaceOk(scene, reference, tolerance);
    final symmetryOk = _symmetryOk(scene, reference, tolerance);
    final backgroundOk = _backgroundOk(scene, reference, tolerance, thresholds);
    final cooldownOk =
        _lastCapture == null ||
        DateTime.now().difference(_lastCapture!).inMilliseconds >=
            thresholds.captureCooldownMs;

    // No 'eyesOpen' key: it's no longer part of the capture decision (see
    // shouldCapture), so reporting it here — as always-passing or
    // otherwise — would be misleading debug output.
    return {
      'brightness': scene.brightness >= thresholds.minBrightnessForCapture,
      'shoulderAngle': shoulderOk,
      'faceAngle': faceOk,
      'facePitch': facePitchOk,
      'faceRoll': faceRollOk,
      'bodyRatio': bodyRatioOk,
      'mouthOpen': mouthOpenOk,
      'negativeSpace': negativeSpaceOk,
      'symmetry': symmetryOk,
      'backgroundClutter': backgroundOk,
      'trackingProgress':
          trackingProgress >= thresholds.minTrackingProgressForCapture,
      'cooldown': cooldownOk,
    };
  }

  bool _shoulderOk(
    SubjectProfile subject,
    ReferenceProfile reference,
    ToleranceSettings tolerance,
  ) {
    final referenceValue = reference.shoulderAngleDegrees;
    if (referenceValue == null) return true;
    final subjectValue = subject.shoulderAngleDegrees;
    if (subjectValue == null) return false;

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

  bool _facePitchOk(
    SubjectProfile subject,
    ReferenceProfile reference,
    ToleranceSettings tolerance,
  ) {
    final subjectValue = subject.faceAngleXDegrees;
    if (subjectValue == null) return false;
    final referenceValue = reference.faceAngleXDegrees;
    if (referenceValue == null) return true;

    final deviation = ComparisonMath.deviation(subjectValue, referenceValue);
    final threshold = ComparisonMath.thresholdForPose(tolerance.poseTolerance);
    return !ComparisonMath.exceedsThreshold(deviation, threshold);
  }

  bool _faceRollOk(
    SubjectProfile subject,
    ReferenceProfile reference,
    ToleranceSettings tolerance,
  ) {
    final subjectValue = subject.faceAngleZDegrees;
    if (subjectValue == null) return false;
    final referenceValue = reference.faceAngleZDegrees;
    if (referenceValue == null) return true;

    final deviation = ComparisonMath.deviation(subjectValue, referenceValue);
    final threshold = ComparisonMath.thresholdForPose(tolerance.poseTolerance);
    return !ComparisonMath.exceedsThreshold(deviation, threshold);
  }

  bool _bodyRatioOk(
    SubjectProfile subject,
    ReferenceProfile reference,
    ToleranceSettings tolerance,
  ) {
    final referenceValue = reference.bodyRatio;
    if (referenceValue == null) return true;
    final subjectValue = subject.bodyRatio;
    if (subjectValue == null) return false;

    final deviation = ComparisonMath.relativeDeviation(
      subjectValue,
      referenceValue,
    );
    if (deviation == null) return true;

    final threshold = ComparisonMath.thresholdForPoseRatio(
      tolerance.poseTolerance,
    );
    return !ComparisonMath.exceedsThreshold(deviation, threshold);
  }

  bool _mouthOpenOk(
    SubjectProfile subject,
    ReferenceProfile reference,
    ToleranceSettings tolerance,
  ) {
    final referenceValue = reference.mouthOpenRatio;
    if (referenceValue == null) return true;
    final subjectValue = subject.mouthOpenRatio;
    if (subjectValue == null) return false;

    final deviation = ComparisonMath.relativeDeviation(
      subjectValue,
      referenceValue,
    );
    if (deviation == null) return true;

    final threshold = ComparisonMath.thresholdForPoseRatio(
      tolerance.poseTolerance,
    );
    return !ComparisonMath.exceedsThreshold(deviation, threshold);
  }

  bool _negativeSpaceOk(
    SceneProfile scene,
    ReferenceProfile reference,
    ToleranceSettings tolerance,
  ) {
    final referenceValue = reference.negativeSpaceScore;
    if (referenceValue == null) return true;

    final deviation = ComparisonMath.deviation(
      scene.negativeSpaceScore,
      referenceValue,
    );
    final threshold = ComparisonMath.thresholdForComposition(
      tolerance.compositionTolerance,
    );
    return !ComparisonMath.exceedsThreshold(deviation, threshold);
  }

  bool _symmetryOk(
    SceneProfile scene,
    ReferenceProfile reference,
    ToleranceSettings tolerance,
  ) {
    final referenceValue = reference.symmetryScore;
    if (referenceValue == null) return true;

    final deviation = (referenceValue - scene.symmetryScore).clamp(0.0, 1.0);
    final threshold = ComparisonMath.thresholdForComposition(
      tolerance.compositionTolerance,
    );
    return !ComparisonMath.exceedsThreshold(deviation, threshold);
  }

  bool _backgroundOk(
    SceneProfile scene,
    ReferenceProfile reference,
    ToleranceSettings tolerance,
    DetectionThresholds thresholds,
  ) {
    final referenceValue = reference.backgroundClutterCount;
    if (referenceValue == null) {
      return scene.backgroundClutterCount <=
          thresholds.defaultBackgroundClutterThreshold;
    }

    final sceneClutterNormalized = (scene.backgroundClutterCount / 10).clamp(
      0.0,
      1.0,
    );
    final referenceClutterNormalized = (referenceValue / 10).clamp(0.0, 1.0);

    final deviation = ComparisonMath.deviation(
      sceneClutterNormalized,
      referenceClutterNormalized,
    );
    final threshold = ComparisonMath.thresholdForComposition(
      tolerance.compositionTolerance,
    );
    return !ComparisonMath.exceedsThreshold(deviation, threshold);
  }
}
