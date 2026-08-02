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

  double? _ema(double? raw, double? previous) {
    if (raw == null) return previous;
    if (previous == null) return raw;
    return previous + _emaAlpha * (raw - previous);
  }

  SubjectProfile smoothSubject(SubjectProfile raw, SubjectProfile previous) {
    final bodyRatio = _ema(raw.bodyRatio, previous.bodyRatio);
    final faceAngleDegrees = _ema(
      raw.faceAngleDegrees,
      previous.faceAngleDegrees,
    );
    final shoulderAngleDegrees = _ema(
      raw.shoulderAngleDegrees,
      previous.shoulderAngleDegrees,
    );

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
    final lightDirectionDegrees = _ema(
      raw.lightDirectionDegrees,
      previous.lightDirectionDegrees,
    );
    final negativeSpaceScore =
        _ema(raw.negativeSpaceScore, previous.negativeSpaceScore) ??
        previous.negativeSpaceScore;
    final symmetryScore =
        _ema(raw.symmetryScore, previous.symmetryScore) ??
        previous.symmetryScore;
    final depthEstimate = _ema(raw.depthEstimate, previous.depthEstimate);

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
