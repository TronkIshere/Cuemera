// features/voice_director/providers/voice_providers.dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/tts_service.dart';
import '../../reference_photo/providers/reference_providers.dart';
import '../../scene_analysis/providers/scene_providers.dart';
import '../domain/priority_engine.dart';
import '../domain/reference_comparison_engine.dart';

final referenceComparisonEngineProvider = Provider<ReferenceComparisonEngine>(
  (ref) => ReferenceComparisonEngine(),
);

final nextActionProvider = Provider<PriorityAction?>((ref) {
  final subject = ref.watch(subjectProfileProvider);
  final scene = ref.watch(sceneProfileProvider);
  final referenceAsync = ref.watch(referenceProfileProvider);
  final tolerance = ref.watch(toleranceSettingsProvider);
  final engine = ref.watch(referenceComparisonEngineProvider);

  final reference = referenceAsync.valueOrNull;
  if (reference == null) return null;

  return engine.evaluate(
    subject: subject,
    scene: scene,
    reference: reference,
    tolerance: tolerance,
  );
});

final voiceDirectorListenerProvider = Provider<void>((ref) {
  final ttsService = ref.watch(ttsServiceProvider);

  String? lastPhrase;
  Timer? debounceTimer;

  ref.listen<PriorityAction?>(nextActionProvider, (previous, next) {
    if (next == null) return;
    if (next.phrase == lastPhrase) return;

    debounceTimer?.cancel();
    debounceTimer = Timer(const Duration(milliseconds: 400), () {
      lastPhrase = next.phrase;
      ttsService.speak(next.phrase);
    });
  });

  ref.onDispose(() {
    debounceTimer?.cancel();
  });
});
