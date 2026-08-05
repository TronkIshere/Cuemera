// core/services/expression_classifier.dart

String? classifyExpression({
  required double? smilingProbability,
  required double? leftEyeOpenProbability,
  required double? rightEyeOpenProbability,
}) {
  if (smilingProbability == null) return null;

  if (leftEyeOpenProbability != null &&
      rightEyeOpenProbability != null &&
      ((leftEyeOpenProbability > 0.5 && rightEyeOpenProbability <= 0.5) ||
          (leftEyeOpenProbability <= 0.5 && rightEyeOpenProbability > 0.5))) {
    return 'wink';
  }

  final eyeOpenValues = [
    leftEyeOpenProbability,
    rightEyeOpenProbability,
  ].whereType<double>().toList();
  final avgEyeOpen = eyeOpenValues.isEmpty
      ? null
      : eyeOpenValues.reduce((a, b) => a + b) / eyeOpenValues.length;

  if (avgEyeOpen != null && avgEyeOpen < 0.25) {
    return smilingProbability > 0.5 ? 'laughing_eyes_closed' : 'eyes_closed';
  }

  if (smilingProbability > 0.85) return 'big_smile';
  if (smilingProbability > 0.6) return 'smiling';
  if (smilingProbability > 0.35) return 'slight_smile';
  if (smilingProbability > 0.15) return 'neutral';
  return 'serious';
}
