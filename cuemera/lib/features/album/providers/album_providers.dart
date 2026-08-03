// features/album/providers/album_providers.dart
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/album_state.dart';
import '../domain/models/shot.dart';

class AlbumNotifier extends StateNotifier<AlbumState> {
  AlbumNotifier() : super(const AlbumState());

  void addShot(Shot shot) {
    state = state.addShot(shot);
  }

  Future<void> removeShot(String shotId) async {
    final shot = state.shots.where((s) => s.id == shotId).firstOrNull;
    state = state.removeShot(shotId);

    final path = shot?.imagePath;
    if (path != null) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
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
