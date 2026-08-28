// features/reference_photo/domain/models/tolerance_settings.dart
class ToleranceSettings {
  const ToleranceSettings({
    required this.poseTolerance,
    required this.compositionTolerance,
    required this.expressionTolerance,
    required this.colorTolerance,
    required this.bodyYawTolerance,
  });

  final double poseTolerance;
  final double compositionTolerance;
  final double expressionTolerance;
  final double colorTolerance;
  // Split out from poseTolerance: bodyYaw is derived from ML Kit's
  // per-landmark z (depth) estimate, a single-camera guess that's
  // noticeably noisier than the x/y-based pose attributes sharing
  // poseTolerance — see comparison_math.dart's thresholdForBodyYaw. A
  // dedicated tolerance lets this be loosened on its own without also
  // loosening shoulderAngle/shoulderBalance/facePitch/etc., which were
  // otherwise fine.
  final double bodyYawTolerance;

  static const ToleranceSettings defaultBalanced = ToleranceSettings(
    poseTolerance: 0.5,
    compositionTolerance: 0.5,
    expressionTolerance: 0.5,
    colorTolerance: 0.5,
    bodyYawTolerance: 0.5,
  );

  ToleranceSettings copyWith({
    double? poseTolerance,
    double? compositionTolerance,
    double? expressionTolerance,
    double? colorTolerance,
    double? bodyYawTolerance,
  }) {
    return ToleranceSettings(
      poseTolerance: poseTolerance ?? this.poseTolerance,
      compositionTolerance: compositionTolerance ?? this.compositionTolerance,
      expressionTolerance: expressionTolerance ?? this.expressionTolerance,
      colorTolerance: colorTolerance ?? this.colorTolerance,
      bodyYawTolerance: bodyYawTolerance ?? this.bodyYawTolerance,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'poseTolerance': poseTolerance,
      'compositionTolerance': compositionTolerance,
      'expressionTolerance': expressionTolerance,
      'colorTolerance': colorTolerance,
      'bodyYawTolerance': bodyYawTolerance,
    };
  }

  factory ToleranceSettings.fromMap(Map<String, dynamic> map) {
    return ToleranceSettings(
      poseTolerance: (map['poseTolerance'] as num).toDouble(),
      compositionTolerance: (map['compositionTolerance'] as num).toDouble(),
      expressionTolerance: (map['expressionTolerance'] as num).toDouble(),
      colorTolerance: (map['colorTolerance'] as num).toDouble(),
      // Old persisted settings (saved before this field existed) won't
      // have this key — fall back to poseTolerance's value so an
      // existing user's saved settings don't suddenly behave as if
      // bodyYaw strictness were unset/zero.
      bodyYawTolerance: map.containsKey('bodyYawTolerance')
          ? (map['bodyYawTolerance'] as num).toDouble()
          : (map['poseTolerance'] as num).toDouble(),
    );
  }
}
