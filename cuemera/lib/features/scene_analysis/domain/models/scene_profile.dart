// features/scene_analysis/domain/models/scene_profile.dart
class SceneProfile {
  const SceneProfile({
    required this.brightness,
    this.lightDirectionDegrees,
    required this.negativeSpaceScore,
    required this.symmetryScore,
    this.subjectHorizontalPosition,
    required this.backgroundClutterCount,
    this.depthEstimate,
    this.liveWarmthScore,
    this.liveDominantHue,
  });

  final double brightness;
  final double? lightDirectionDegrees;
  final double negativeSpaceScore;
  final double symmetryScore;
  final double? subjectHorizontalPosition;
  final int backgroundClutterCount;
  final double? depthEstimate;
  final double? liveWarmthScore;
  final double? liveDominantHue;

  static const Object _unset = Object();

  SceneProfile copyWith({
    double? brightness,
    Object? lightDirectionDegrees = _unset,
    double? negativeSpaceScore,
    double? symmetryScore,
    Object? subjectHorizontalPosition = _unset,
    int? backgroundClutterCount,
    Object? depthEstimate = _unset,
    Object? liveWarmthScore = _unset,
    Object? liveDominantHue = _unset,
  }) {
    return SceneProfile(
      brightness: brightness ?? this.brightness,
      lightDirectionDegrees: identical(lightDirectionDegrees, _unset)
          ? this.lightDirectionDegrees
          : lightDirectionDegrees as double?,
      negativeSpaceScore: negativeSpaceScore ?? this.negativeSpaceScore,
      symmetryScore: symmetryScore ?? this.symmetryScore,
      subjectHorizontalPosition: identical(subjectHorizontalPosition, _unset)
          ? this.subjectHorizontalPosition
          : subjectHorizontalPosition as double?,
      backgroundClutterCount:
          backgroundClutterCount ?? this.backgroundClutterCount,
      depthEstimate: identical(depthEstimate, _unset)
          ? this.depthEstimate
          : depthEstimate as double?,
      liveWarmthScore: identical(liveWarmthScore, _unset)
          ? this.liveWarmthScore
          : liveWarmthScore as double?,
      liveDominantHue: identical(liveDominantHue, _unset)
          ? this.liveDominantHue
          : liveDominantHue as double?,
    );
  }
}
