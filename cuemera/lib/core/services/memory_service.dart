// core/services/memory_service.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

class MemoryService {
  static const String habitsBoxName = 'shooting_habits';
  static const String albumBoxName = 'album_state';

  late Box _habitsBox;
  late Box _albumBox;

  Future<void> init() async {
    await Hive.initFlutter();
    _habitsBox = await Hive.openBox(habitsBoxName);
    _albumBox = await Hive.openBox(albumBoxName);
  }

  T? getHabit<T>(String key, {T? defaultValue}) {
    return _habitsBox.get(key, defaultValue: defaultValue) as T?;
  }

  Future<void> setHabit<T>(String key, T value) async {
    await _habitsBox.put(key, value);
  }

  Future<void> saveHabit(String key, dynamic value) async {
    await _habitsBox.put(key, value);
  }

  Future<void> recordCorrection(String correctionType) async {
    final corrections =
        _habitsBox.get('corrections', defaultValue: <String, int>{}) as Map;
    final current = (corrections[correctionType] as int?) ?? 0;
    corrections[correctionType] = current + 1;
    await _habitsBox.put('corrections', corrections);
  }

  Map<String, int> getFrequentCorrections() {
    final corrections =
        _habitsBox.get('corrections', defaultValue: <String, int>{}) as Map;
    return corrections.map(
      (key, value) => MapEntry(key as String, value as int),
    );
  }

  T? getAlbumValue<T>(String key, {T? defaultValue}) {
    return _albumBox.get(key, defaultValue: defaultValue) as T?;
  }

  Future<void> setAlbumValue<T>(String key, T value) async {
    await _albumBox.put(key, value);
  }

  Future<void> clearHabits() async {
    await _habitsBox.clear();
  }

  Future<void> clearAlbum() async {
    await _albumBox.clear();
  }
}

final memoryServiceProvider = FutureProvider<MemoryService>((ref) async {
  final service = MemoryService();
  await service.init();
  return service;
});
