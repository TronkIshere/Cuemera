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

  /// EMA smoothing factor used by TrackingEngine (0..1, higher = less smoothing).
  final double emaAlpha;

  /// Consecutive-frame streak required before accepting a changed
  /// discrete value (eyesOpen, expression, backgroundClutterCount).
  final int debounceFrames;

  /// Minimum trackingProgress (0..1) required before auto-capture can fire.
  final double minTrackingProgressForCapture;

  /// Fallback background-clutter ceiling when the reference photo has no
  /// measured backgroundClutterCount to compare against.
  final int defaultBackgroundClutterThreshold;

  /// Minimum scene brightness (0..1) required before auto-capture can fire.
  final double minBrightnessForCapture;

  /// Minimum time between consecutive auto-captures.
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
