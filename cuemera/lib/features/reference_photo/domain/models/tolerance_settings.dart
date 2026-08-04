// features/reference_photo/domain/models/tolerance_settings.dart
class ToleranceSettings {
  const ToleranceSettings({
    required this.poseTolerance,
    required this.compositionTolerance,
    required this.expressionTolerance,
    required this.colorTolerance,
  });

  final double poseTolerance;
  final double compositionTolerance;
  final double expressionTolerance;
  final double colorTolerance;

  static const ToleranceSettings defaultBalanced = ToleranceSettings(
    poseTolerance: 0.5,
    compositionTolerance: 0.5,
    expressionTolerance: 0.5,
    colorTolerance: 0.5,
  );

  ToleranceSettings copyWith({
    double? poseTolerance,
    double? compositionTolerance,
    double? expressionTolerance,
    double? colorTolerance,
  }) {
    return ToleranceSettings(
      poseTolerance: poseTolerance ?? this.poseTolerance,
      compositionTolerance: compositionTolerance ?? this.compositionTolerance,
      expressionTolerance: expressionTolerance ?? this.expressionTolerance,
      colorTolerance: colorTolerance ?? this.colorTolerance,
    );
  }
}
