// features/scene_analysis/services/face_analyzer.dart
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../domain/models/subject_profile.dart';

class FaceAnalyzer {
  SubjectProfile analyzeFace(dynamic mlkitFaceResult, SubjectProfile previous) {
    final faces = mlkitFaceResult as List<Face>?;
    if (faces == null || faces.isEmpty) return previous;

    final face = faces.first;

    final faceAngle = face.headEulerAngleY;

    bool? eyesOpen;
    final leftOpen = face.leftEyeOpenProbability;
    final rightOpen = face.rightEyeOpenProbability;
    if (leftOpen != null && rightOpen != null) {
      eyesOpen = leftOpen > 0.5 && rightOpen > 0.5;
    }

    String? expression;
    final smileProb = face.smilingProbability;
    if (smileProb != null) {
      if (smileProb > 0.7) {
        expression = 'smiling';
      } else if (smileProb > 0.3) {
        expression = 'neutral';
      } else {
        expression = 'serious';
      }
    }

    return previous.copyWith(
      faceAngleDegrees: faceAngle,
      eyesOpen: eyesOpen,
      expression: expression,
    );
  }
}
