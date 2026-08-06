// test/album/domain/album_state_test.dart
import 'package:cuemera/features/album/domain/models/album_state.dart';
import 'package:cuemera/features/album/domain/models/shot.dart';
import 'package:cuemera/features/editorial_score/domain/score_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

Shot _shot({required String id, required String shotType}) {
  return Shot(
    id: id,
    score: const EditorialScore(overall: 80, breakdown: {'composition': 80}),
    timestamp: DateTime.now(),
    shotType: shotType,
  );
}

void main() {
  group('AlbumState.shotTypes', () {
    test(
      'is public and has 5 entries (P1 #4 fix — was private _shotTypes)',
      () {
        expect(AlbumState.shotTypes, hasLength(5));
        expect(AlbumState.shotTypes, contains('hero'));
      },
    );
  });

  group('addShot / removeShot', () {
    test('addShot appends without mutating the original state', () {
      const original = AlbumState();
      final updated = original.addShot(_shot(id: '1', shotType: 'hero'));

      expect(original.shots, isEmpty);
      expect(updated.shots, hasLength(1));
    });

    test('removeShot removes only the matching id', () {
      final state = const AlbumState()
          .addShot(_shot(id: '1', shotType: 'hero'))
          .addShot(_shot(id: '2', shotType: 'walking'));

      final updated = state.removeShot('1');

      expect(updated.shots, hasLength(1));
      expect(updated.shots.single.id, '2');
    });

    test('removeShot is a no-op when the id is not present', () {
      final state = const AlbumState().addShot(
        _shot(id: '1', shotType: 'hero'),
      );
      final updated = state.removeShot('does-not-exist');
      expect(updated.shots, hasLength(1));
    });
  });

  group('diversityScore', () {
    test('is 0.0 for an empty album', () {
      expect(const AlbumState().diversityScore(), 0.0);
    });

    test('is distinct-types / 5, not total-shots / 5', () {
      final state = const AlbumState()
          .addShot(_shot(id: '1', shotType: 'hero'))
          .addShot(_shot(id: '2', shotType: 'hero'))
          .addShot(_shot(id: '3', shotType: 'hero'));

      // 3 shots but all the same type -> only 1 distinct type
      expect(state.diversityScore(), closeTo(1 / 5, 1e-9));
    });

    test('reaches 1.0 once all 5 shot types are represented', () {
      var state = const AlbumState();
      for (final type in AlbumState.shotTypes) {
        state = state.addShot(_shot(id: type, shotType: type));
      }
      expect(state.diversityScore(), 1.0);
    });
  });

  group('suggestNextShotType', () {
    test('recommends a type with zero shots when the album is empty', () {
      const state = AlbumState();
      expect(AlbumState.shotTypes, contains(state.suggestNextShotType()));
    });

    test('recommends the least-represented type', () {
      final state = const AlbumState()
          .addShot(_shot(id: '1', shotType: 'hero'))
          .addShot(_shot(id: '2', shotType: 'hero'))
          .addShot(_shot(id: '3', shotType: 'walking'));

      // hero: 2, walking: 1, half_body/close_up/detail: 0 — suggestion
      // should be one of the untouched types, never 'hero'.
      final suggestion = state.suggestNextShotType();
      expect(suggestion, isNot('hero'));
    });
  });
}
