// features/scene_analysis/services/pose_analyzer.dart
import 'dart:math';

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../../../core/pose/landmark_gate.dart';
import '../domain/models/subject_profile.dart';

class PoseAnalyzer {
  PoseAnalyzer({Duration holdWindow = Duration.zero})
    : _hold = GateHold(window: holdWindow);

  static const double _maxExtremityExtrapolationMultiplier = 4.0;

  final GateHold _hold;

  SubjectProfile analyzePose(dynamic mlkitPoseResult, SubjectProfile previous) {
    final poses = mlkitPoseResult as List<Pose>?;
    if (poses == null || poses.isEmpty) return previous;

    final gate = PoseLandmarkGate.fromLandmarks(
      landmarks: poses.first.landmarks,
    );

    double? shoulderAngle;
    double? torsoScale;
    final leftShoulder = gate.landmark(PoseLandmarkType.leftShoulder);
    final rightShoulder = gate.landmark(PoseLandmarkType.rightShoulder);
    if (leftShoulder != null && rightShoulder != null) {
      final dy = rightShoulder.y - leftShoulder.y;
      final dx = rightShoulder.x - leftShoulder.x;
      shoulderAngle = atan2(dy, dx) * 180 / pi;
      torsoScale = sqrt(dx * dx + dy * dy);
    }

    double? bodyRatio;
    final nose = gate.landmark(PoseLandmarkType.nose);
    final leftHip = gate.landmark(PoseLandmarkType.leftHip);
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

    return previous.copyWith(
      bodyRatio: _hold.resolve('bodyRatio', bodyRatio),
      shoulderAngleDegrees: _hold.resolve(
        'shoulderAngleDegrees',
        shoulderAngle,
      ),
    );
  }
}
