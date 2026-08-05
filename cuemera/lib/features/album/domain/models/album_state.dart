// features/album/domain/models/album_state.dart
import 'shot.dart';

class AlbumState {
  const AlbumState({this.shots = const []});

  final List<Shot> shots;

  static const List<String> shotTypes = [
    'hero',
    'half_body',
    'walking',
    'close_up',
    'detail',
  ];

  AlbumState addShot(Shot shot) {
    return AlbumState(shots: [...shots, shot]);
  }

  AlbumState removeShot(String shotId) {
    return AlbumState(shots: shots.where((s) => s.id != shotId).toList());
  }

  double diversityScore() {
    if (shots.isEmpty) return 0.0;
    final distinctTypes = shots.map((s) => s.shotType).toSet().length;
    return distinctTypes / shotTypes.length;
  }

  String suggestNextShotType() {
    final counts = <String, int>{for (final t in shotTypes) t: 0};
    for (final shot in shots) {
      counts[shot.shotType] = (counts[shot.shotType] ?? 0) + 1;
    }

    var leastType = shotTypes.first;
    var leastCount = counts[leastType] ?? 0;
    for (final type in shotTypes) {
      final count = counts[type] ?? 0;
      if (count < leastCount) {
        leastType = type;
        leastCount = count;
      }
    }

    return leastType;
  }
}
