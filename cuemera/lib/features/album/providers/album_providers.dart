// features/album/providers/album_providers.dart
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/error_reporting_service.dart';
import '../../../core/services/memory_service.dart';
import '../domain/models/album_state.dart';
import '../domain/models/shot.dart';

const _shotsKey = 'shots';
const _schemaVersionKey = 'schemaVersion';

/// Bump this whenever the shape of a persisted `Shot` map changes, and add
/// a corresponding step in `_migrateShots`. v1 was the original
/// {id, score, timestamp, shotType, imagePath} shape; v2 added
/// referenceImagePath/toleranceSettings.
const int _currentShotsSchemaVersion = 2;

class AlbumNotifier extends StateNotifier<AlbumState> {
  AlbumNotifier(this._ref) : super(const AlbumState()) {
    _restore();
  }

  final Ref _ref;

  Future<void> _restore() async {
    try {
      final memoryService = await _ref.read(memoryServiceProvider.future);
      final storedVersion =
          memoryService.getAlbumValue<int>(
            _schemaVersionKey,
            defaultValue: 1,
          ) ??
          1;
      final stored = memoryService.getAlbumValue<List>(
        _shotsKey,
        defaultValue: const [],
      );

      if (stored == null || stored.isEmpty) {
        await memoryService.setAlbumValue(
          _schemaVersionKey,
          _currentShotsSchemaVersion,
        );
        return;
      }

      var rawShots = stored
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();

      if (storedVersion < _currentShotsSchemaVersion) {
        rawShots = _migrateShots(rawShots, fromVersion: storedVersion);
        await memoryService.setAlbumValue(_shotsKey, rawShots);
        await memoryService.setAlbumValue(
          _schemaVersionKey,
          _currentShotsSchemaVersion,
        );
      }

      final shots = rawShots.map((m) => Shot.fromMap(m)).toList();
      state = AlbumState(shots: shots);
    } catch (e, st) {
      ErrorReportingService.instance.report(
        e,
        st,
        context: 'AlbumNotifier: restore from Hive',
      );
    }
  }

  /// Migrates raw stored shot maps forward from [fromVersion] to
  /// [_currentShotsSchemaVersion], one version step at a time.
  List<Map<String, dynamic>> _migrateShots(
    List<Map<String, dynamic>> shots, {
    required int fromVersion,
  }) {
    var migrated = shots;

    if (fromVersion < 2) {
      // v1 -> v2: referenceImagePath/toleranceSettings were introduced.
      // Shot.fromMap already defaults missing keys to null, so no value
      // transform is required — this step exists to make the version bump
      // explicit and give future migrations a documented place to live.
      migrated = migrated
          .map(
            (m) => {
              ...m,
              'referenceImagePath': m['referenceImagePath'],
              'toleranceSettings': m['toleranceSettings'],
            },
          )
          .toList();
    }

    return migrated;
  }

  Future<void> _persist() async {
    try {
      final memoryService = await _ref.read(memoryServiceProvider.future);
      await memoryService.setAlbumValue(
        _shotsKey,
        state.shots.map((s) => s.toMap()).toList(),
      );
      await memoryService.setAlbumValue(
        _schemaVersionKey,
        _currentShotsSchemaVersion,
      );
    } catch (e, st) {
      ErrorReportingService.instance.report(
        e,
        st,
        context: 'AlbumNotifier: persist to Hive',
      );
    }
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
      } catch (e, st) {
        ErrorReportingService.instance.report(
          e,
          st,
          context: 'AlbumNotifier: delete shot file',
        );
      }
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
