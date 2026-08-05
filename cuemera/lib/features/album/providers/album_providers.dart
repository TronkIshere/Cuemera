// features/album/providers/album_providers.dart
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/memory_service.dart';
import '../domain/models/album_state.dart';
import '../domain/models/shot.dart';

const _shotsKey = 'shots';

class AlbumNotifier extends StateNotifier<AlbumState> {
  AlbumNotifier(this._ref) : super(const AlbumState()) {
    _restore();
  }

  final Ref _ref;

  Future<void> _restore() async {
    try {
      final memoryService = await _ref.read(memoryServiceProvider.future);
      final stored = memoryService.getAlbumValue<List>(
        _shotsKey,
        defaultValue: const [],
      );
      if (stored == null || stored.isEmpty) return;

      final shots = stored
          .whereType<Map>()
          .map((m) => Shot.fromMap(Map<String, dynamic>.from(m)))
          .toList();

      state = AlbumState(shots: shots);
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final memoryService = await _ref.read(memoryServiceProvider.future);
      await memoryService.setAlbumValue(
        _shotsKey,
        state.shots.map((s) => s.toMap()).toList(),
      );
    } catch (_) {}
  }

  void addShot(Shot shot) {
    state = state.addShot(shot);
    _persist();
  }

  Future<void> removeShot(String shotId) async {
    final shot = state.shots.where((s) => s.id == shotId).firstOrNull;
    state = state.removeShot(shotId);
    await _persist();

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
  return AlbumNotifier(ref);
});
