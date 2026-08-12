// core/services/tracking_engine.dart
import 'package:cuemera/features/reference_photo/domain/comparison_math.dart';
import 'package:cuemera/features/reference_photo/domain/models/detection_thresholds.dart';
import 'package:cuemera/features/reference_photo/domain/models/tolerance_settings.dart';
import 'package:cuemera/features/scene_analysis/domain/models/scene_profile.dart';
import 'package:cuemera/features/scene_analysis/domain/models/subject_profile.dart';

class TrackingEngine {
  TrackingEngine({this.thresholds = DetectionThresholds.defaultValues});

  final DetectionThresholds thresholds;

  bool? _pendingEyesOpen;
  int _eyesOpenStreak = 0;

  String? _pendingExpression;
  int _expressionStreak = 0;

  int? _pendingClutterCount;
  int _clutterStreak = 0;

  int _bodyRatioMissingStreak = 0;
  int _faceAngleMissingStreak = 0;
  int _faceAngleXMissingStreak = 0;
  int _faceAngleZMissingStreak = 0;
  int _mouthOpenMissingStreak = 0;
  int _eyeOpenRatioMissingStreak = 0;
  int _shoulderAngleMissingStreak = 0;
  int _eyesOpenMissingStreak = 0;
  int _expressionMissingStreak = 0;
  int _lightDirectionMissingStreak = 0;
  int _depthMissingStreak = 0;

  double? _ema(double? raw, double? previous) {
    if (raw == null) return previous;
    if (previous == null) return raw;
    return previous + thresholds.emaAlpha * (raw - previous);
  }

  int _bumpMissingStreak(int streak, bool rawIsNull) {
    return rawIsNull ? streak + 1 : 0;
  }

  SubjectProfile smoothSubject(SubjectProfile raw, SubjectProfile previous) {
    _bodyRatioMissingStreak = _bumpMissingStreak(
      _bodyRatioMissingStreak,
      raw.bodyRatio == null,
    );
    _faceAngleMissingStreak = _bumpMissingStreak(
      _faceAngleMissingStreak,
      raw.faceAngleDegrees == null,
    );
    _faceAngleXMissingStreak = _bumpMissingStreak(
      _faceAngleXMissingStreak,
      raw.faceAngleXDegrees == null,
    );
    _faceAngleZMissingStreak = _bumpMissingStreak(
      _faceAngleZMissingStreak,
      raw.faceAngleZDegrees == null,
    );
    _mouthOpenMissingStreak = _bumpMissingStreak(
      _mouthOpenMissingStreak,
      raw.mouthOpenRatio == null,
    );
    _eyeOpenRatioMissingStreak = _bumpMissingStreak(
      _eyeOpenRatioMissingStreak,
      raw.eyeOpenRatio == null,
    );
    _shoulderAngleMissingStreak = _bumpMissingStreak(
      _shoulderAngleMissingStreak,
      raw.shoulderAngleDegrees == null,
    );

    var bodyRatio = _ema(raw.bodyRatio, previous.bodyRatio);
    if (_bodyRatioMissingStreak >= thresholds.debounceFrames) bodyRatio = null;

    var faceAngleDegrees = _ema(
      raw.faceAngleDegrees,
      previous.faceAngleDegrees,
    );
    if (_faceAngleMissingStreak >= thresholds.debounceFrames)
      faceAngleDegrees = null;

    var faceAngleXDegrees = _ema(
      raw.faceAngleXDegrees,
      previous.faceAngleXDegrees,
    );
    if (_faceAngleXMissingStreak >= thresholds.debounceFrames) {
      faceAngleXDegrees = null;
    }

    var faceAngleZDegrees = _ema(
      raw.faceAngleZDegrees,
      previous.faceAngleZDegrees,
    );
    if (_faceAngleZMissingStreak >= thresholds.debounceFrames) {
      faceAngleZDegrees = null;
    }

    var mouthOpenRatio = _ema(raw.mouthOpenRatio, previous.mouthOpenRatio);
    if (_mouthOpenMissingStreak >= thresholds.debounceFrames) {
      mouthOpenRatio = null;
    }

    var eyeOpenRatio = _ema(raw.eyeOpenRatio, previous.eyeOpenRatio);
    if (_eyeOpenRatioMissingStreak >= thresholds.debounceFrames) {
      eyeOpenRatio = null;
    }

    var shoulderAngleDegrees = _ema(
      raw.shoulderAngleDegrees,
      previous.shoulderAngleDegrees,
    );
    if (_shoulderAngleMissingStreak >= thresholds.debounceFrames) {
      shoulderAngleDegrees = null;
    }

    bool? eyesOpen = previous.eyesOpen;
    if (raw.eyesOpen != null) {
      if (raw.eyesOpen == _pendingEyesOpen) {
        _eyesOpenStreak++;
      } else {
        _pendingEyesOpen = raw.eyesOpen;
        _eyesOpenStreak = 1;
      }
      if (_eyesOpenStreak >= thresholds.debounceFrames) {
        eyesOpen = _pendingEyesOpen;
      }
    }
    _eyesOpenMissingStreak = _bumpMissingStreak(
      _eyesOpenMissingStreak,
      raw.eyesOpen == null,
    );
    if (_eyesOpenMissingStreak >= thresholds.debounceFrames) eyesOpen = null;

    String? expression = previous.expression;
    if (raw.expression != null) {
      if (raw.expression == _pendingExpression) {
        _expressionStreak++;
      } else {
        _pendingExpression = raw.expression;
        _expressionStreak = 1;
      }
      if (_expressionStreak >= thresholds.debounceFrames) {
        expression = _pendingExpression;
      }
    }
    _expressionMissingStreak = _bumpMissingStreak(
      _expressionMissingStreak,
      raw.expression == null,
    );
    if (_expressionMissingStreak >= thresholds.debounceFrames)
      expression = null;

    return SubjectProfile(
      bodyRatio: bodyRatio,
      faceAngleDegrees: faceAngleDegrees,
      faceAngleXDegrees: faceAngleXDegrees,
      faceAngleZDegrees: faceAngleZDegrees,
      mouthOpenRatio: mouthOpenRatio,
      eyeOpenRatio: eyeOpenRatio,
      shoulderAngleDegrees: shoulderAngleDegrees,
      eyesOpen: eyesOpen,
      expression: expression,
      timestamp: DateTime.now(),
    );
  }

  SceneProfile smoothScene(SceneProfile raw, SceneProfile previous) {
    final brightness =
        _ema(raw.brightness, previous.brightness) ?? previous.brightness;

    _lightDirectionMissingStreak = _bumpMissingStreak(
      _lightDirectionMissingStreak,
      raw.lightDirectionDegrees == null,
    );
    var lightDirectionDegrees = _ema(
      raw.lightDirectionDegrees,
      previous.lightDirectionDegrees,
    );
    if (_lightDirectionMissingStreak >= thresholds.debounceFrames) {
      lightDirectionDegrees = null;
    }

    final negativeSpaceScore =
        _ema(raw.negativeSpaceScore, previous.negativeSpaceScore) ??
        previous.negativeSpaceScore;
    final symmetryScore =
        _ema(raw.symmetryScore, previous.symmetryScore) ??
        previous.symmetryScore;

    _depthMissingStreak = _bumpMissingStreak(
      _depthMissingStreak,
      raw.depthEstimate == null,
    );
    var depthEstimate = _ema(raw.depthEstimate, previous.depthEstimate);
    if (_depthMissingStreak >= thresholds.debounceFrames) depthEstimate = null;

    int backgroundClutterCount = previous.backgroundClutterCount;
    if (raw.backgroundClutterCount == _pendingClutterCount) {
      _clutterStreak++;
    } else {
      _pendingClutterCount = raw.backgroundClutterCount;
      _clutterStreak = 1;
    }
    if (_clutterStreak >= thresholds.debounceFrames) {
      backgroundClutterCount = _pendingClutterCount!;
    }

    return SceneProfile(
      brightness: brightness,
      lightDirectionDegrees: lightDirectionDegrees,
      negativeSpaceScore: negativeSpaceScore,
      symmetryScore: symmetryScore,
      backgroundClutterCount: backgroundClutterCount,
      depthEstimate: depthEstimate,
    );
  }

  double trackingProgress(
    SubjectProfile current,
    SubjectProfile target,
    SceneProfile scene,
    SceneProfile targetScene,
    ToleranceSettings tolerance,
  ) {
    final scores = <double>[];

    if (target.shoulderAngleDegrees != null) {
      if (current.shoulderAngleDegrees == null) {
        scores.add(0.0);
      } else {
        final deviation = ComparisonMath.deviation(
          current.shoulderAngleDegrees!,
          target.shoulderAngleDegrees!,
        );
        final threshold = ComparisonMath.thresholdForPose(
          tolerance.poseTolerance,
        );
        scores.add(
          ComparisonMath.similarity(
            deviation,
            threshold,
            ComparisonMath.maxDeviationForPose,
          ),
        );
      }
    }

    if (target.faceAngleDegrees != null) {
      if (current.faceAngleDegrees == null) {
        scores.add(0.0);
      } else {
        final deviation = ComparisonMath.deviation(
          current.faceAngleDegrees!,
          target.faceAngleDegrees!,
        );
        final threshold = ComparisonMath.thresholdForPose(
          tolerance.poseTolerance,
        );
        scores.add(
          ComparisonMath.similarity(
            deviation,
            threshold,
            ComparisonMath.maxDeviationForPose,
          ),
        );
      }
    }

    if (target.bodyRatio != null) {
      if (current.bodyRatio == null) {
        scores.add(0.0);
      } else {
        final deviation = ComparisonMath.relativeDeviation(
          current.bodyRatio!,
          target.bodyRatio!,
        );
        if (deviation != null) {
          final threshold = ComparisonMath.thresholdForPoseRatio(
            tolerance.poseTolerance,
          );
          scores.add(
            ComparisonMath.similarity(
              deviation,
              threshold,
              ComparisonMath.maxDeviationForPoseRatio,
            ),
          );
        }
      }
    }

    if (current.eyesOpen != null && target.eyesOpen != null) {
      scores.add(current.eyesOpen == target.eyesOpen ? 1.0 : 0.0);
    }

    if (current.expression != null && target.expression != null) {
      final deviation = current.expression == target.expression ? 0.0 : 1.0;
      final threshold = ComparisonMath.thresholdForExpression(
        tolerance.expressionTolerance,
      );
      scores.add(ComparisonMath.similarity(deviation, threshold, 1.0));
    }

    final brightnessDeviation = ComparisonMath.deviation(
      scene.brightness,
      targetScene.brightness,
    );
    final brightnessThreshold = ComparisonMath.thresholdForColor(
      tolerance.colorTolerance,
    );
    scores.add(
      ComparisonMath.similarity(
        brightnessDeviation,
        brightnessThreshold,
        ComparisonMath.maxDeviationForColor,
      ),
    );

    final sceneClutterNormalized = (scene.backgroundClutterCount / 10).clamp(
      0.0,
      1.0,
    );
    final targetClutterNormalized = (targetScene.backgroundClutterCount / 10)
        .clamp(0.0, 1.0);
    final clutterDeviation = ComparisonMath.deviation(
      sceneClutterNormalized,
      targetClutterNormalized,
    );
    final clutterThreshold = ComparisonMath.thresholdForComposition(
      tolerance.compositionTolerance,
    );
    scores.add(
      ComparisonMath.similarity(
        clutterDeviation,
        clutterThreshold,
        ComparisonMath.maxDeviationForComposition,
      ),
    );

    if (scores.isEmpty) return 0.0;

    final sum = scores.reduce((a, b) => a + b);
    return (sum / scores.length).clamp(0.0, 1.0);
  }
}
