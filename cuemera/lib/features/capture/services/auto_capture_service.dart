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
    if (scene.brightness < thresholds.minBrightnessForCapture) return false;

    final shoulderOk = _shoulderOk(subject, reference, tolerance);
    final faceOk = _faceOk(subject, reference, tolerance);
    final facePitchOk = _facePitchOk(subject, reference, tolerance);
    final faceRollOk = _faceRollOk(subject, reference, tolerance);
    final bodyYawOk = _bodyYawOk(subject, reference, tolerance);
    final shoulderBalanceOk = _shoulderBalanceOk(subject, reference, tolerance);
    final shoulderSpanOk = _shoulderSpanOk(subject, reference, tolerance);
    final bodyRatioOk = _bodyRatioOk(subject, reference, tolerance);
    final mouthOpenOk = _mouthOpenOk(subject, reference, tolerance);
    final negativeSpaceOk = _negativeSpaceOk(scene, reference, tolerance);
    final symmetryOk = _symmetryOk(scene, reference, tolerance);
    final backgroundOk = _backgroundOk(scene, reference, tolerance, thresholds);

    if (!shoulderOk ||
        !faceOk ||
        !facePitchOk ||
        !faceRollOk ||
        !bodyYawOk ||
        !shoulderBalanceOk ||
        !shoulderSpanOk ||
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
    final bodyYawOk = _bodyYawOk(subject, reference, tolerance);
    final shoulderBalanceOk = _shoulderBalanceOk(subject, reference, tolerance);
    final shoulderSpanOk = _shoulderSpanOk(subject, reference, tolerance);
    final bodyRatioOk = _bodyRatioOk(subject, reference, tolerance);
    final mouthOpenOk = _mouthOpenOk(subject, reference, tolerance);
    final negativeSpaceOk = _negativeSpaceOk(scene, reference, tolerance);
    final symmetryOk = _symmetryOk(scene, reference, tolerance);
    final backgroundOk = _backgroundOk(scene, reference, tolerance, thresholds);
    final cooldownOk =
        _lastCapture == null ||
        DateTime.now().difference(_lastCapture!).inMilliseconds >=
            thresholds.captureCooldownMs;

    return {
      'brightness': scene.brightness >= thresholds.minBrightnessForCapture,
      'shoulderAngle': shoulderOk,
      'faceAngle': faceOk,
      'facePitch': facePitchOk,
      'faceRoll': faceRollOk,
      'bodyYaw': bodyYawOk,
      'shoulderBalance': shoulderBalanceOk,
      'shoulderSpan': shoulderSpanOk,
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

    final deviation = ComparisonMath.circularDeviation(
      subjectValue,
      referenceValue,
      360.0,
    );
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

    final deviation = ComparisonMath.circularDeviation(
      subjectValue,
      referenceValue,
      360.0,
    );
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

    final deviation = ComparisonMath.circularDeviation(
      subjectValue,
      referenceValue,
      360.0,
    );
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

    final deviation = ComparisonMath.circularDeviation(
      subjectValue,
      referenceValue,
      360.0,
    );
    final threshold = ComparisonMath.thresholdForPose(tolerance.poseTolerance);
    return !ComparisonMath.exceedsThreshold(deviation, threshold);
  }

  bool _bodyYawOk(
    SubjectProfile subject,
    ReferenceProfile reference,
    ToleranceSettings tolerance,
  ) {
    final referenceValue = reference.bodyYawEstimate;
    if (referenceValue == null) return true;
    final subjectValue = subject.bodyYawEstimate;
    if (subjectValue == null) return false;

    final deviation = ComparisonMath.circularDeviation(
      subjectValue,
      referenceValue,
      360.0,
    );
    final threshold = ComparisonMath.thresholdForPose(tolerance.poseTolerance);
    return !ComparisonMath.exceedsThreshold(deviation, threshold);
  }

  bool _shoulderBalanceOk(
    SubjectProfile subject,
    ReferenceProfile reference,
    ToleranceSettings tolerance,
  ) {
    final referenceValue = reference.shoulderBalanceRatio;
    if (referenceValue == null) return true;
    final subjectValue = subject.shoulderBalanceRatio;
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

  bool _shoulderSpanOk(
    SubjectProfile subject,
    ReferenceProfile reference,
    ToleranceSettings tolerance,
  ) {
    final referenceValue = reference.shoulderSpanRatio;
    if (referenceValue == null) return true;
    final subjectValue = subject.shoulderSpanRatio;
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
