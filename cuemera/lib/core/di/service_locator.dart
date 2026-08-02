// core/di/service_locator.dart
import 'package:cuemera/core/services/camera_service.dart';
import 'package:cuemera/core/services/memory_service.dart';
import 'package:cuemera/core/services/ml_kit_service.dart';
import 'package:cuemera/core/services/tts_service.dart';
import 'package:get_it/get_it.dart';

final sl = GetIt.instance;

void setupLocator() {
  sl.registerLazySingleton<CameraService>(() => CameraService());
  sl.registerLazySingleton<MlKitService>(() => MlKitService());
  sl.registerLazySingleton<TtsService>(() => TtsService());
  sl.registerLazySingleton<MemoryService>(() => MemoryService());
}
