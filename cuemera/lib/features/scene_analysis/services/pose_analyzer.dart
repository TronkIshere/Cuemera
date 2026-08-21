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
  late final TemporalStabilizer _leftArmRaiseStabilizer = TemporalStabilizer(
    _config,
  );
  late final TemporalStabilizer _rightArmRaiseStabilizer = TemporalStabilizer(
    _config,
  );
  late final TemporalStabilizer _leftElbowAngleStabilizer = TemporalStabilizer(
    _config,
  );
  late final TemporalStabilizer _rightElbowAngleStabilizer = TemporalStabilizer(
    _config,
  );

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

  double? _angleBetweenDegrees(
    RawLandmark rayA,
    RawLandmark vertex,
    RawLandmark rayB,
  ) {
    final v1x = rayA.x - vertex.x;
    final v1y = rayA.y - vertex.y;
    final v2x = rayB.x - vertex.x;
    final v2y = rayB.y - vertex.y;
    final mag1 = sqrt(v1x * v1x + v1y * v1y);
    final mag2 = sqrt(v2x * v2x + v2y * v2y);
    if (mag1 == 0 || mag2 == 0) return null;
    final cosAngle = ((v1x * v2x) + (v1y * v2y)) / (mag1 * mag2);
    return acos(cosAngle.clamp(-1.0, 1.0)) * 180 / pi;
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
      final leftArmRaiseMetric = _resolveLinear(
        _leftArmRaiseStabilizer,
        null,
        at,
      );
      final rightArmRaiseMetric = _resolveLinear(
        _rightArmRaiseStabilizer,
        null,
        at,
      );
      final leftElbowAngleMetric = _resolveLinear(
        _leftElbowAngleStabilizer,
        null,
        at,
      );
      final rightElbowAngleMetric = _resolveLinear(
        _rightElbowAngleStabilizer,
        null,
        at,
      );

      return previous.copyWith(
        bodyRatio: bodyRatioMetric?.value,
        shoulderAngleDegrees: shoulderAngleMetric?.value,
        shoulderBalanceRatio: shoulderBalanceMetric?.value,
        shoulderSpanRatio: shoulderSpanMetric?.value,
        bodyYawEstimate: bodyYawMetric?.value,
        leftArmRaiseDegrees: leftArmRaiseMetric?.value,
        rightArmRaiseDegrees: rightArmRaiseMetric?.value,
        leftElbowAngleDegrees: leftElbowAngleMetric?.value,
        rightElbowAngleDegrees: rightElbowAngleMetric?.value,
        metricTemporalEligibility: {
          'bodyRatio': bodyRatioMetric?.isEligible ?? false,
          'shoulderAngleDegrees': shoulderAngleMetric?.isEligible ?? false,
          'shoulderBalanceRatio': shoulderBalanceMetric?.isEligible ?? false,
          'shoulderSpanRatio': shoulderSpanMetric?.isEligible ?? false,
          'bodyYawEstimate': bodyYawMetric?.isEligible ?? false,
          'leftArmRaiseDegrees': leftArmRaiseMetric?.isEligible ?? false,
          'rightArmRaiseDegrees': rightArmRaiseMetric?.isEligible ?? false,
          'leftElbowAngleDegrees': leftElbowAngleMetric?.isEligible ?? false,
          'rightElbowAngleDegrees': rightElbowAngleMetric?.isEligible ?? false,
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

    final leftElbow = gate.landmark(PoseLandmarkType.leftElbow);
    final rightElbow = gate.landmark(PoseLandmarkType.rightElbow);
    final leftWrist = gate.landmark(PoseLandmarkType.leftWrist);
    final rightWrist = gate.landmark(PoseLandmarkType.rightWrist);

    double? leftArmRaise;
    if (leftShoulder != null && leftElbow != null && leftHip != null) {
      leftArmRaise = _angleBetweenDegrees(leftHip, leftShoulder, leftElbow);
    }
    double? rightArmRaise;
    if (rightShoulder != null && rightElbow != null && rightHip != null) {
      rightArmRaise = _angleBetweenDegrees(rightHip, rightShoulder, rightElbow);
    }
    double? leftElbowAngle;
    if (leftShoulder != null && leftElbow != null && leftWrist != null) {
      leftElbowAngle = _angleBetweenDegrees(leftShoulder, leftElbow, leftWrist);
    }
    double? rightElbowAngle;
    if (rightShoulder != null && rightElbow != null && rightWrist != null) {
      rightElbowAngle = _angleBetweenDegrees(
        rightShoulder,
        rightElbow,
        rightWrist,
      );
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
      if (leftArmRaise != null)
        'leftArmRaiseDegrees': _minConfidence(gate, [
          PoseLandmarkType.leftHip,
          PoseLandmarkType.leftShoulder,
          PoseLandmarkType.leftElbow,
        ]),
      if (rightArmRaise != null)
        'rightArmRaiseDegrees': _minConfidence(gate, [
          PoseLandmarkType.rightHip,
          PoseLandmarkType.rightShoulder,
          PoseLandmarkType.rightElbow,
        ]),
      if (leftElbowAngle != null)
        'leftElbowAngleDegrees': _minConfidence(gate, [
          PoseLandmarkType.leftShoulder,
          PoseLandmarkType.leftElbow,
          PoseLandmarkType.leftWrist,
        ]),
      if (rightElbowAngle != null)
        'rightElbowAngleDegrees': _minConfidence(gate, [
          PoseLandmarkType.rightShoulder,
          PoseLandmarkType.rightElbow,
          PoseLandmarkType.rightWrist,
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
    final leftArmRaiseMetric = _resolveLinear(
      _leftArmRaiseStabilizer,
      leftArmRaise,
      at,
    );
    final rightArmRaiseMetric = _resolveLinear(
      _rightArmRaiseStabilizer,
      rightArmRaise,
      at,
    );
    final leftElbowAngleMetric = _resolveLinear(
      _leftElbowAngleStabilizer,
      leftElbowAngle,
      at,
    );
    final rightElbowAngleMetric = _resolveLinear(
      _rightElbowAngleStabilizer,
      rightElbowAngle,
      at,
    );

    return previous.copyWith(
      bodyRatio: bodyRatioMetric?.value,
      shoulderAngleDegrees: shoulderAngleMetric?.value,
      shoulderBalanceRatio: shoulderBalanceMetric?.value,
      shoulderSpanRatio: shoulderSpanMetric?.value,
      bodyYawEstimate: bodyYawMetric?.value,
      leftArmRaiseDegrees: leftArmRaiseMetric?.value,
      rightArmRaiseDegrees: rightArmRaiseMetric?.value,
      leftElbowAngleDegrees: leftElbowAngleMetric?.value,
      rightElbowAngleDegrees: rightElbowAngleMetric?.value,
      metricConfidence: metricConfidence.isEmpty ? null : metricConfidence,
      metricTemporalEligibility: {
        'bodyRatio': bodyRatioMetric?.isEligible ?? false,
        'shoulderAngleDegrees': shoulderAngleMetric?.isEligible ?? false,
        'shoulderBalanceRatio': shoulderBalanceMetric?.isEligible ?? false,
        'shoulderSpanRatio': shoulderSpanMetric?.isEligible ?? false,
        'bodyYawEstimate': bodyYawMetric?.isEligible ?? false,
        'leftArmRaiseDegrees': leftArmRaiseMetric?.isEligible ?? false,
        'rightArmRaiseDegrees': rightArmRaiseMetric?.isEligible ?? false,
        'leftElbowAngleDegrees': leftElbowAngleMetric?.isEligible ?? false,
        'rightElbowAngleDegrees': rightElbowAngleMetric?.isEligible ?? false,
      },
    );
  }
}
