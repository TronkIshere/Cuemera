// core/analysis/analysis_constants.dart
import 'dart:math' as math;

const int kClutterSamplesPerRow = 160;
const double kClutterVarianceDivisor = 12.0;
const double kClutterScoreCeiling = 10.0;
const int kBrightnessTargetSamples = 2000;
const int kMaskSampleStep = 4;

int clutterStep(int width) {
  if (width <= 0) return 1;
  return math.max(1, (width / kClutterSamplesPerRow).round());
}

int adaptiveStep(int width, int height, int targetSamples) {
  if (width <= 0 || height <= 0 || targetSamples <= 0) return 1;
  final step = math.sqrt((width * height) / targetSamples).round();
  return step.clamp(1, math.max(1, width));
}

int clutterScoreFromVariance(double variance) {
  return (variance / kClutterVarianceDivisor)
      .clamp(0.0, kClutterScoreCeiling)
      .round();
}

double normalizeClutterCount(num count) {
  return (count / kClutterScoreCeiling).clamp(0.0, 1.0).toDouble();
}
