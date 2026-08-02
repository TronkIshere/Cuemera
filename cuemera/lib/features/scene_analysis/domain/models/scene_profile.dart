// features/scene_analysis/domain/models/scene_profile.dart
class SceneProfile {
  const SceneProfile({
    required this.brightness,
    this.lightDirectionDegrees,
    required this.negativeSpaceScore,
    required this.symmetryScore,
    required this.backgroundClutterCount,
    this.depthEstimate,
  });

  final double brightness;
  final double? lightDirectionDegrees;
  final double negativeSpaceScore;
  final double symmetryScore;
  final int backgroundClutterCount;
  final double? depthEstimate;

  SceneProfile copyWith({
    double? brightness,
    double? lightDirectionDegrees,
    double? negativeSpaceScore,
    double? symmetryScore,
    int? backgroundClutterCount,
    double? depthEstimate,
  }) {
    return SceneProfile(
      brightness: brightness ?? this.brightness,
      lightDirectionDegrees:
          lightDirectionDegrees ?? this.lightDirectionDegrees,
      negativeSpaceScore: negativeSpaceScore ?? this.negativeSpaceScore,
      symmetryScore: symmetryScore ?? this.symmetryScore,
      backgroundClutterCount:
          backgroundClutterCount ?? this.backgroundClutterCount,
      depthEstimate: depthEstimate ?? this.depthEstimate,
    );
  }
}
