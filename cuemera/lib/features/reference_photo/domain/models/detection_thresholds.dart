// features/reference_photo/domain/models/detection_thresholds.dart
class DetectionThresholds {
  const DetectionThresholds({
    required this.emaAlpha,
    required this.debounceFrames,
    required this.minTrackingProgressForCapture,
    required this.defaultBackgroundClutterThreshold,
    required this.minBrightnessForCapture,
    required this.captureCooldownMs,
  });

  final double emaAlpha;
  final int debounceFrames;
  final double minTrackingProgressForCapture;
  final int defaultBackgroundClutterThreshold;
  final double minBrightnessForCapture;
  final int captureCooldownMs;

  static const DetectionThresholds defaultValues = DetectionThresholds(
    emaAlpha: 0.3,
    debounceFrames: 2,
    minTrackingProgressForCapture: 0.9,
    defaultBackgroundClutterThreshold: 5,
    minBrightnessForCapture: 0.2,
    captureCooldownMs: 1500,
  );

  DetectionThresholds copyWith({
    double? emaAlpha,
    int? debounceFrames,
    double? minTrackingProgressForCapture,
    int? defaultBackgroundClutterThreshold,
    double? minBrightnessForCapture,
    int? captureCooldownMs,
  }) {
    return DetectionThresholds(
      emaAlpha: emaAlpha ?? this.emaAlpha,
      debounceFrames: debounceFrames ?? this.debounceFrames,
      minTrackingProgressForCapture:
          minTrackingProgressForCapture ?? this.minTrackingProgressForCapture,
      defaultBackgroundClutterThreshold:
          defaultBackgroundClutterThreshold ??
          this.defaultBackgroundClutterThreshold,
      minBrightnessForCapture:
          minBrightnessForCapture ?? this.minBrightnessForCapture,
      captureCooldownMs: captureCooldownMs ?? this.captureCooldownMs,
    );
  }
}
