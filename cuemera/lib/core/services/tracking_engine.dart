// features/scene_analysis/services/tracking_engine.dart
import 'package:cuemera/features/scene_analysis/domain/models/scene_profile.dart';
import 'package:cuemera/features/scene_analysis/domain/models/subject_profile.dart';

const double _emaAlpha = 0.3;
const int _debounceFrames = 2;

class TrackingEngine {
  bool? _pendingEyesOpen;
  int _eyesOpenStreak = 0;

  String? _pendingExpression;
  int _expressionStreak = 0;

  int? _pendingClutterCount;
  int _clutterStreak = 0;

  int _bodyRatioMissingStreak = 0;
  int _faceAngleMissingStreak = 0;
  int _shoulderAngleMissingStreak = 0;
  int _eyesOpenMissingStreak = 0;
  int _expressionMissingStreak = 0;
  int _lightDirectionMissingStreak = 0;
  int _depthMissingStreak = 0;

  double? _ema(double? raw, double? previous) {
    if (raw == null) return previous;
    if (previous == null) return raw;
    return previous + _emaAlpha * (raw - previous);
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
    _shoulderAngleMissingStreak = _bumpMissingStreak(
      _shoulderAngleMissingStreak,
      raw.shoulderAngleDegrees == null,
    );

    var bodyRatio = _ema(raw.bodyRatio, previous.bodyRatio);
    if (_bodyRatioMissingStreak >= _debounceFrames) bodyRatio = null;

    var faceAngleDegrees = _ema(
      raw.faceAngleDegrees,
      previous.faceAngleDegrees,
    );
    if (_faceAngleMissingStreak >= _debounceFrames) faceAngleDegrees = null;

    var shoulderAngleDegrees = _ema(
      raw.shoulderAngleDegrees,
      previous.shoulderAngleDegrees,
    );
    if (_shoulderAngleMissingStreak >= _debounceFrames) {
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
      if (_eyesOpenStreak >= _debounceFrames) {
        eyesOpen = _pendingEyesOpen;
      }
    }
    _eyesOpenMissingStreak = _bumpMissingStreak(
      _eyesOpenMissingStreak,
      raw.eyesOpen == null,
    );
    if (_eyesOpenMissingStreak >= _debounceFrames) eyesOpen = null;

    String? expression = previous.expression;
    if (raw.expression != null) {
      if (raw.expression == _pendingExpression) {
        _expressionStreak++;
      } else {
        _pendingExpression = raw.expression;
        _expressionStreak = 1;
      }
      if (_expressionStreak >= _debounceFrames) {
        expression = _pendingExpression;
      }
    }
    _expressionMissingStreak = _bumpMissingStreak(
      _expressionMissingStreak,
      raw.expression == null,
    );
    if (_expressionMissingStreak >= _debounceFrames) expression = null;

    return SubjectProfile(
      bodyRatio: bodyRatio,
      faceAngleDegrees: faceAngleDegrees,
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
    if (_lightDirectionMissingStreak >= _debounceFrames) {
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
    if (_depthMissingStreak >= _debounceFrames) depthEstimate = null;

    int backgroundClutterCount = previous.backgroundClutterCount;
    if (raw.backgroundClutterCount == _pendingClutterCount) {
      _clutterStreak++;
    } else {
      _pendingClutterCount = raw.backgroundClutterCount;
      _clutterStreak = 1;
    }
    if (_clutterStreak >= _debounceFrames) {
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

  double trackingProgress(SubjectProfile current, SubjectProfile target) {
    final diffs = <double>[];

    if (current.shoulderAngleDegrees != null &&
        target.shoulderAngleDegrees != null) {
      final diff =
          (current.shoulderAngleDegrees! - target.shoulderAngleDegrees!).abs();
      diffs.add(1.0 - (diff / 45.0).clamp(0.0, 1.0));
    }

    if (current.faceAngleDegrees != null && target.faceAngleDegrees != null) {
      final diff = (current.faceAngleDegrees! - target.faceAngleDegrees!).abs();
      diffs.add(1.0 - (diff / 45.0).clamp(0.0, 1.0));
    }

    if (current.bodyRatio != null && target.bodyRatio != null) {
      final diff = (current.bodyRatio! - target.bodyRatio!).abs();
      diffs.add(1.0 - (diff / 1.0).clamp(0.0, 1.0));
    }

    if (current.eyesOpen != null && target.eyesOpen != null) {
      diffs.add(current.eyesOpen == target.eyesOpen ? 1.0 : 0.0);
    }

    if (current.expression != null && target.expression != null) {
      diffs.add(current.expression == target.expression ? 1.0 : 0.0);
    }

    if (diffs.isEmpty) return 0.0;

    final sum = diffs.reduce((a, b) => a + b);
    return (sum / diffs.length).clamp(0.0, 1.0);
  }
}
