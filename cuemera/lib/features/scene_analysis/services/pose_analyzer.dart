// features/scene_analysis/services/pose_analyzer.dart
import 'dart:math';

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../../../core/pose/landmark_gate.dart';
import '../../../core/tracking/temporal_stabilizer.dart';
import '../domain/models/subject_profile.dart';

class PoseAnalyzer {
  PoseAnalyzer({StabilizerConfig? stabilizerConfig})
    : _config = stabilizerConfig ?? const StabilizerConfig();

  static const double _maxExtremityExtrapolationMultiplier = 4.0;

  final StabilizerConfig _config;

  late final TemporalStabilizer _bodyRatioStabilizer = TemporalStabilizer(
    _config,
  );
  late final CircularStabilizer _shoulderAngleStabilizer = CircularStabilizer(
    _config,
  );
  late final TemporalStabilizer _shoulderBalanceStabilizer = TemporalStabilizer(
    _config,
  );
  late final TemporalStabilizer _shoulderSpanStabilizer = TemporalStabilizer(
    _config,
  );
  late final CircularStabilizer _bodyYawStabilizer = CircularStabilizer(
    _config,
  );

  /// Genuinely-lost detection: temporal_stabilizer.dart returns
  /// temporalConfidence 0 exactly when raw was null AND the hold-on-loss
  /// window has fully elapsed — everything else (a real value, or a raw
  /// null still within the hold window) should surface a value.
  StabilizedMetric? _resolveLinear(
    TemporalStabilizer stabilizer,
    double? raw,
    DateTime now,
  ) {
    final metric = stabilizer.update(raw, now);
    if (raw == null && metric.temporalConfidence == 0) return null;
    return metric;
  }

  StabilizedMetric? _resolveCircular(
    CircularStabilizer stabilizer,
    double? raw,
    DateTime now,
  ) {
    final metric = stabilizer.update(raw, now);
    if (raw == null && metric.temporalConfidence == 0) return null;
    return metric;
  }

  double _minConfidence(PoseLandmarkGate gate, List<PoseLandmarkType> types) {
    var lowest = 1.0;
    for (final type in types) {
      final value = gate.trust(type)?.confidence.value ?? 0.0;
      if (value < lowest) lowest = value;
    }
    return lowest;
  }

  SubjectProfile analyzePose(
    dynamic mlkitPoseResult,
    SubjectProfile previous, {
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final poses = mlkitPoseResult as List<Pose>?;

    if (poses == null || poses.isEmpty) {
      final bodyRatioMetric = _resolveLinear(_bodyRatioStabilizer, null, at);
      final shoulderAngleMetric = _resolveCircular(
        _shoulderAngleStabilizer,
        null,
        at,
      );
      final shoulderBalanceMetric = _resolveLinear(
        _shoulderBalanceStabilizer,
        null,
        at,
      );
      final shoulderSpanMetric = _resolveLinear(
        _shoulderSpanStabilizer,
        null,
        at,
      );
      final bodyYawMetric = _resolveCircular(_bodyYawStabilizer, null, at);

      return previous.copyWith(
        bodyRatio: bodyRatioMetric?.value,
        shoulderAngleDegrees: shoulderAngleMetric?.value,
        shoulderBalanceRatio: shoulderBalanceMetric?.value,
        shoulderSpanRatio: shoulderSpanMetric?.value,
        bodyYawEstimate: bodyYawMetric?.value,
        metricTemporalEligibility: {
          'bodyRatio': bodyRatioMetric?.isEligible ?? false,
          'shoulderAngleDegrees': shoulderAngleMetric?.isEligible ?? false,
          'shoulderBalanceRatio': shoulderBalanceMetric?.isEligible ?? false,
          'shoulderSpanRatio': shoulderSpanMetric?.isEligible ?? false,
          'bodyYawEstimate': bodyYawMetric?.isEligible ?? false,
        },
      );
    }

    final gate = PoseLandmarkGate.fromLandmarks(
      landmarks: poses.first.landmarks,
      maskSignal: MaskTrustSignal.none,
    );

    double? shoulderAngle;
    double? torsoScale;
    double? shoulderBalanceRatio;
    double? bodyYawEstimate;
    final leftShoulder = gate.landmark(PoseLandmarkType.leftShoulder);
    final rightShoulder = gate.landmark(PoseLandmarkType.rightShoulder);
    if (leftShoulder != null && rightShoulder != null) {
      final dy = rightShoulder.y - leftShoulder.y;
      final dx = rightShoulder.x - leftShoulder.x;
      shoulderAngle = atan2(dy, dx) * 180 / pi;
      torsoScale = sqrt(dx * dx + dy * dy);

      // Previously missing entirely on the live path — mirrors
      // ReferenceImageAnalyzer._derivePose()'s formulas so the live and
      // reference-photo sides compute these identically.
      shoulderBalanceRatio = torsoScale > 0
          ? (leftShoulder.y - rightShoulder.y) / torsoScale
          : null;
      bodyYawEstimate = atan2(rightShoulder.z - leftShoulder.z, dx) * 180 / pi;
    }

    final leftHip = gate.landmark(PoseLandmarkType.leftHip);
    final rightHip = gate.landmark(PoseLandmarkType.rightHip);
    double? shoulderSpanRatio;
    if (leftShoulder != null &&
        rightShoulder != null &&
        leftHip != null &&
        rightHip != null &&
        torsoScale != null) {
      final shoulderMidX = (leftShoulder.x + rightShoulder.x) / 2;
      final shoulderMidY = (leftShoulder.y + rightShoulder.y) / 2;
      final hipMidX = (leftHip.x + rightHip.x) / 2;
      final hipMidY = (leftHip.y + rightHip.y) / 2;
      final torsoHeight = sqrt(
        pow(hipMidX - shoulderMidX, 2) + pow(hipMidY - shoulderMidY, 2),
      );
      shoulderSpanRatio = torsoHeight > 0 ? torsoScale / torsoHeight : null;
    }

    double? bodyRatio;
    final nose = gate.landmark(PoseLandmarkType.nose);
    final leftAnkle = gate.landmark(PoseLandmarkType.leftAnkle);
    if (nose != null && leftHip != null && leftAnkle != null) {
      final upperLength = (leftHip.y - nose.y).abs();
      final lowerLength = (leftAnkle.y - leftHip.y).abs();
      final scale = torsoScale;
      final ankleExtrapolationSuspect =
          scale != null &&
          scale > 0 &&
          lowerLength > _maxExtremityExtrapolationMultiplier * scale;
      if (lowerLength > 0 && !ankleExtrapolationSuspect) {
        bodyRatio = upperLength / lowerLength;
      }
    }

    final metricConfidence = <String, double>{
      if (shoulderAngle != null)
        'shoulderAngleDegrees': _minConfidence(gate, [
          PoseLandmarkType.leftShoulder,
          PoseLandmarkType.rightShoulder,
        ]),
      if (shoulderBalanceRatio != null)
        'shoulderBalanceRatio': _minConfidence(gate, [
          PoseLandmarkType.leftShoulder,
          PoseLandmarkType.rightShoulder,
        ]),
      if (bodyYawEstimate != null)
        'bodyYawEstimate': _minConfidence(gate, [
          PoseLandmarkType.leftShoulder,
          PoseLandmarkType.rightShoulder,
        ]),
      if (shoulderSpanRatio != null)
        'shoulderSpanRatio': _minConfidence(gate, [
          PoseLandmarkType.leftShoulder,
          PoseLandmarkType.rightShoulder,
          PoseLandmarkType.leftHip,
          PoseLandmarkType.rightHip,
        ]),
      if (bodyRatio != null)
        'bodyRatio': _minConfidence(gate, [
          PoseLandmarkType.nose,
          PoseLandmarkType.leftHip,
          PoseLandmarkType.leftAnkle,
        ]),
    };

    final bodyRatioMetric = _resolveLinear(_bodyRatioStabilizer, bodyRatio, at);
    final shoulderAngleMetric = _resolveCircular(
      _shoulderAngleStabilizer,
      shoulderAngle,
      at,
    );
    final shoulderBalanceMetric = _resolveLinear(
      _shoulderBalanceStabilizer,
      shoulderBalanceRatio,
      at,
    );
    final shoulderSpanMetric = _resolveLinear(
      _shoulderSpanStabilizer,
      shoulderSpanRatio,
      at,
    );
    final bodyYawMetric = _resolveCircular(
      _bodyYawStabilizer,
      bodyYawEstimate,
      at,
    );

    return previous.copyWith(
      bodyRatio: bodyRatioMetric?.value,
      shoulderAngleDegrees: shoulderAngleMetric?.value,
      shoulderBalanceRatio: shoulderBalanceMetric?.value,
      shoulderSpanRatio: shoulderSpanMetric?.value,
      bodyYawEstimate: bodyYawMetric?.value,
      metricConfidence: metricConfidence.isEmpty ? null : metricConfidence,
      metricTemporalEligibility: {
        'bodyRatio': bodyRatioMetric?.isEligible ?? false,
        'shoulderAngleDegrees': shoulderAngleMetric?.isEligible ?? false,
        'shoulderBalanceRatio': shoulderBalanceMetric?.isEligible ?? false,
        'shoulderSpanRatio': shoulderSpanMetric?.isEligible ?? false,
        'bodyYawEstimate': bodyYawMetric?.isEligible ?? false,
      },
    );
  }
}
