// features/scene_analysis/services/pose_analyzer.dart
import 'dart:math';

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../domain/models/subject_profile.dart';

class PoseAnalyzer {
  SubjectProfile analyzePose(dynamic mlkitPoseResult, SubjectProfile previous) {
    final poses = mlkitPoseResult as List<Pose>?;
    if (poses == null || poses.isEmpty) return previous;

    final pose = poses.first;
    final landmarks = pose.landmarks;

    final leftShoulder = landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = landmarks[PoseLandmarkType.rightShoulder];
    final leftHip = landmarks[PoseLandmarkType.leftHip];
    final leftAnkle = landmarks[PoseLandmarkType.leftAnkle];
    final nose = landmarks[PoseLandmarkType.nose];

    double? shoulderAngle;
    if (leftShoulder != null && rightShoulder != null) {
      final dy = rightShoulder.y - leftShoulder.y;
      final dx = rightShoulder.x - leftShoulder.x;
      shoulderAngle = atan2(dy, dx) * 180 / pi;
    }

    double? bodyRatio;
    if (nose != null && leftHip != null && leftAnkle != null) {
      final upperLength = (leftHip.y - nose.y).abs();
      final lowerLength = (leftAnkle.y - leftHip.y).abs();
      if (lowerLength > 0) bodyRatio = upperLength / lowerLength;
    }

    return previous.copyWith(
      bodyRatio: bodyRatio,
      shoulderAngleDegrees: shoulderAngle,
    );
  }
}
