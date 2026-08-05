// features/scene_analysis/domain/models/scene_profile.dart
class SceneProfile {
  const SceneProfile({
    required this.brightness,
    this.lightDirectionDegrees,
    required this.negativeSpaceScore,
    required this.symmetryScore,
    required this.backgroundClutterCount,
    this.depthEstimate,
    this.liveWarmthScore,
    this.liveDominantHue,
  });

  final double brightness;
  final double? lightDirectionDegrees;
  final double negativeSpaceScore;
  final double symmetryScore;
  final int backgroundClutterCount;
  final double? depthEstimate;
  final double? liveWarmthScore;
  final double? liveDominantHue;

  SceneProfile copyWith({
    double? brightness,
    double? lightDirectionDegrees,
    double? negativeSpaceScore,
    double? symmetryScore,
    int? backgroundClutterCount,
    double? depthEstimate,
    double? liveWarmthScore,
    double? liveDominantHue,
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
      liveWarmthScore: liveWarmthScore ?? this.liveWarmthScore,
      liveDominantHue: liveDominantHue ?? this.liveDominantHue,
    );
  }
}
