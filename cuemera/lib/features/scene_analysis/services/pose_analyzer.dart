// features/scene_analysis/services/pose_analyzer.dart
import 'dart:math';

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../../../core/pose/landmark_gate.dart';
import '../../../core/tracking/temporal_stabilizer.dart';
import '../domain/models/subject_profile.dart';

const List<String> kPoseMetricKeys = [
  'bodyRatio',
  'shoulderAngleDegrees',
  'shoulderBalanceRatio',
  'shoulderSpanRatio',
  'bodyYawEstimate',
  'leftArmRaiseDegrees',
  'rightArmRaiseDegrees',
  'leftElbowAngleDegrees',
  'rightElbowAngleDegrees',
];

class PoseAnalyzer {
  PoseAnalyzer({StabilizerConfig? stabilizerConfig})
    : _config = stabilizerConfig ?? const StabilizerConfig() {
    _buildStabilizers();
  }

  static const double _maxExtremityExtrapolationMultiplier = 4.0;

  final StabilizerConfig _config;

  late TemporalStabilizer _bodyRatioStabilizer;
  late CircularStabilizer _shoulderAngleStabilizer;
  late TemporalStabilizer _shoulderBalanceStabilizer;
  late TemporalStabilizer _shoulderSpanStabilizer;
  late CircularStabilizer _bodyYawStabilizer;
  late TemporalStabilizer _leftArmRaiseStabilizer;
  late TemporalStabilizer _rightArmRaiseStabilizer;
  late TemporalStabilizer _leftElbowAngleStabilizer;
  late TemporalStabilizer _rightElbowAngleStabilizer;

  void _buildStabilizers() {
    _bodyRatioStabilizer = TemporalStabilizer(_config);
    _shoulderAngleStabilizer = CircularStabilizer(_config);
    _shoulderBalanceStabilizer = TemporalStabilizer(_config);
    _shoulderSpanStabilizer = TemporalStabilizer(_config);
    _bodyYawStabilizer = CircularStabilizer(_config);
    _leftArmRaiseStabilizer = TemporalStabilizer(_config);
    _rightArmRaiseStabilizer = TemporalStabilizer(_config);
    _leftElbowAngleStabilizer = TemporalStabilizer(_config);
    _rightElbowAngleStabilizer = TemporalStabilizer(_config);
  }

  void reset() => _buildStabilizers();

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

  Map<String, double>? _mergeConfidence(
    Map<String, double>? previous,
    Map<String, double> poseConfidence,
  ) {
    final merged = <String, double>{};
    if (previous != null) {
      for (final entry in previous.entries) {
        if (!kPoseMetricKeys.contains(entry.key))
          merged[entry.key] = entry.value;
      }
    }
    merged.addAll(poseConfidence);
    return merged.isEmpty ? null : merged;
  }

  Map<String, bool> _mergeEligibility(
    Map<String, bool>? previous,
    Map<String, StabilizedMetric?> metrics,
  ) {
    final merged = <String, bool>{};
    if (previous != null) {
      for (final entry in previous.entries) {
        if (!kPoseMetricKeys.contains(entry.key))
          merged[entry.key] = entry.value;
      }
    }
    for (final entry in metrics.entries) {
      merged[entry.key] = entry.value?.isEligible ?? false;
    }
    return merged;
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

  double _distance(RawLandmark a, RawLandmark b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return sqrt(dx * dx + dy * dy);
  }

  bool _crossedMidline(
    RawLandmark wrist,
    RawLandmark ownShoulder,
    RawLandmark otherShoulder,
  ) {
    final midX = (ownShoulder.x + otherShoulder.x) / 2;
    final axisDir = (otherShoulder.x - ownShoulder.x).sign;
    return (wrist.x - midX) * axisDir > 0;
  }

  String? _classifyArmPose({
    required double? raiseAngle,
    required double? elbowAngle,
    required RawLandmark? wrist,
    required RawLandmark? hip,
    required RawLandmark? nose,
    required RawLandmark? ownShoulder,
    required RawLandmark? otherShoulder,
    required double? torsoScale,
  }) {
    if (raiseAngle == null ||
        wrist == null ||
        hip == null ||
        nose == null ||
        ownShoulder == null ||
        otherShoulder == null ||
        torsoScale == null ||
        torsoScale <= 0) {
      return null;
    }

    if (raiseAngle < 25) return 'down';
    if (_crossedMidline(wrist, ownShoulder, otherShoulder)) return 'crossed';

    final wristToNoseRatio = _distance(wrist, nose) / torsoScale;
    if (wristToNoseRatio < 0.6) return 'nearFace';

    final wristToHipRatio = _distance(wrist, hip) / torsoScale;
    if (wristToHipRatio < 0.4 && (elbowAngle ?? 180) < 130) return 'akimbo';

    return 'raised';
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

      final metrics = <String, StabilizedMetric?>{
        'bodyRatio': bodyRatioMetric,
        'shoulderAngleDegrees': shoulderAngleMetric,
        'shoulderBalanceRatio': shoulderBalanceMetric,
        'shoulderSpanRatio': shoulderSpanMetric,
        'bodyYawEstimate': bodyYawMetric,
        'leftArmRaiseDegrees': leftArmRaiseMetric,
        'rightArmRaiseDegrees': rightArmRaiseMetric,
        'leftElbowAngleDegrees': leftElbowAngleMetric,
        'rightElbowAngleDegrees': rightElbowAngleMetric,
      };

      final decayedConfidence = <String, double>{
        for (final entry in metrics.entries)
          if (entry.value != null)
            entry.key: entry.value!.temporalConfidence.clamp(0.0, 1.0),
      };

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
        leftArmPoseCategory: null,
        rightArmPoseCategory: null,
        metricConfidence: _mergeConfidence(
          previous.metricConfidence,
          decayedConfidence,
        ),
        metricTemporalEligibility: _mergeEligibility(
          previous.metricTemporalEligibility,
          metrics,
        ),
        timestamp: at,
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

    final leftArmPoseCategory = _classifyArmPose(
      raiseAngle: leftArmRaise,
      elbowAngle: leftElbowAngle,
      wrist: leftWrist,
      hip: leftHip,
      nose: nose,
      ownShoulder: leftShoulder,
      otherShoulder: rightShoulder,
      torsoScale: torsoScale,
    );
    final rightArmPoseCategory = _classifyArmPose(
      raiseAngle: rightArmRaise,
      elbowAngle: rightElbowAngle,
      wrist: rightWrist,
      hip: rightHip,
      nose: nose,
      ownShoulder: rightShoulder,
      otherShoulder: leftShoulder,
      torsoScale: torsoScale,
    );

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

    final metrics = <String, StabilizedMetric?>{
      'bodyRatio': bodyRatioMetric,
      'shoulderAngleDegrees': shoulderAngleMetric,
      'shoulderBalanceRatio': shoulderBalanceMetric,
      'shoulderSpanRatio': shoulderSpanMetric,
      'bodyYawEstimate': bodyYawMetric,
      'leftArmRaiseDegrees': leftArmRaiseMetric,
      'rightArmRaiseDegrees': rightArmRaiseMetric,
      'leftElbowAngleDegrees': leftElbowAngleMetric,
      'rightElbowAngleDegrees': rightElbowAngleMetric,
    };

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
      leftArmPoseCategory: leftArmPoseCategory,
      rightArmPoseCategory: rightArmPoseCategory,
      metricConfidence: _mergeConfidence(
        previous.metricConfidence,
        metricConfidence,
      ),
      metricTemporalEligibility: _mergeEligibility(
        previous.metricTemporalEligibility,
        metrics,
      ),
      timestamp: at,
    );
  }
}
