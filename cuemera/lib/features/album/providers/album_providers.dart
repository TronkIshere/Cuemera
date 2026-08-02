// features/album/providers/album_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/album_state.dart';
import '../domain/models/shot.dart';

class AlbumNotifier extends StateNotifier<AlbumState> {
  AlbumNotifier() : super(const AlbumState());

  void addShot(Shot shot) {
    state = state.addShot(shot);
  }

  String suggestNextShotType() {
    return state.suggestNextShotType();
  }

  double diversityScore() {
    return state.diversityScore();
  }
}

final albumStateProvider = StateNotifierProvider<AlbumNotifier, AlbumState>((
  ref,
) {
  return AlbumNotifier();
});
