// features/scene_analysis/services/face_analyzer.dart
import 'dart:ui' show Offset;

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../../core/services/expression_classifier.dart';
import '../../reference_photo/domain/comparison_math.dart';
import '../domain/models/subject_profile.dart';

class FaceAnalyzer {
  static const bool enableEyeAndExpressionSignals = false;

  SubjectProfile analyzeFace(dynamic mlkitFaceResult, SubjectProfile previous) {
    final faces = mlkitFaceResult as List<Face>?;
    if (faces == null || faces.isEmpty) {
      return previous.copyWith(
        faceAngleDegrees: null,
        faceAngleXDegrees: null,
        faceAngleZDegrees: null,
        mouthOpenRatio: null,
        eyeOpenRatio: null,
        eyesOpen: null,
        expression: null,
      );
    }

    final face = faces.first;

    final faceAngle = face.headEulerAngleY;
    final faceAngleX = face.headEulerAngleX;
    final faceAngleZ = face.headEulerAngleZ;

    bool? eyesOpen;
    final leftOpen = face.leftEyeOpenProbability;
    final rightOpen = face.rightEyeOpenProbability;
    if (leftOpen != null && rightOpen != null) {
      eyesOpen = leftOpen > 0.5 && rightOpen > 0.5;
    }

    final smileProb = face.smilingProbability;

    final expression = classifyExpression(
      smilingProbability: smileProb,
      leftEyeOpenProbability: leftOpen,
      rightEyeOpenProbability: rightOpen,
    );

    if (!enableEyeAndExpressionSignals) {
      eyesOpen = null;
    }
    final outputExpression = enableEyeAndExpressionSignals ? expression : null;

    List<Offset>? contourPoints(FaceContourType type) {
      final contour = face.contours[type];
      final points = contour?.points;
      if (points == null || points.isEmpty) return null;
      return points.map((p) => Offset(p.x.toDouble(), p.y.toDouble())).toList();
    }

    final mouthOpenRatio = ComparisonMath.boundingBoxAspectRatio([
      ...?contourPoints(FaceContourType.upperLipTop),
      ...?contourPoints(FaceContourType.upperLipBottom),
      ...?contourPoints(FaceContourType.lowerLipTop),
      ...?contourPoints(FaceContourType.lowerLipBottom),
    ]);

    final leftEyeRatio = ComparisonMath.boundingBoxAspectRatio(
      contourPoints(FaceContourType.leftEye),
    );
    final rightEyeRatio = ComparisonMath.boundingBoxAspectRatio(
      contourPoints(FaceContourType.rightEye),
    );
    final eyeOpenRatio = (leftEyeRatio != null && rightEyeRatio != null)
        ? (leftEyeRatio + rightEyeRatio) / 2
        : (leftEyeRatio ?? rightEyeRatio);

    return previous.copyWith(
      faceAngleDegrees: faceAngle,
      faceAngleXDegrees: faceAngleX,
      faceAngleZDegrees: faceAngleZ,
      mouthOpenRatio: mouthOpenRatio,
      eyeOpenRatio: eyeOpenRatio,
      eyesOpen: eyesOpen,
      expression: outputExpression,
    );
  }
}
