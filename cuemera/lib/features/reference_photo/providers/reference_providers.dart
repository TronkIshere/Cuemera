// features/reference_photo/providers/reference_providers.dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/reference_profile.dart';
import '../domain/models/tolerance_settings.dart';
import '../services/reference_image_analyzer.dart';

final selectedReferenceImagePathProvider = StateProvider<String?>((ref) {
  return null;
});

class SerialAnalysisQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await task());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

final referenceAnalysisQueueProvider = Provider<SerialAnalysisQueue>((ref) {
  return SerialAnalysisQueue();
});

final referenceImageAnalyzerProvider = Provider<ReferenceImageAnalyzer>((ref) {
  return ReferenceImageAnalyzer();
});

final referenceProfileProvider = FutureProvider<ReferenceProfile?>((ref) async {
  final path = ref.watch(selectedReferenceImagePathProvider);
  if (path == null) return null;

  final analyzer = ref.watch(referenceImageAnalyzerProvider);
  final queue = ref.watch(referenceAnalysisQueueProvider);

  var disposed = false;
  ref.onDispose(() => disposed = true);

  final profile = await queue.run(() {
    if (disposed) return Future<ReferenceProfile?>.value(null);
    return analyzer.analyze(path);
  });

  if (disposed) return null;
  return profile;
});

final toleranceSettingsProvider = StateProvider<ToleranceSettings>((ref) {
  return ToleranceSettings.defaultBalanced;
});
