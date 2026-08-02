// features/voice_director/providers/voice_providers.dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/tts_service.dart';
import '../../goal_selection/providers/goal_providers.dart';
import '../../scene_analysis/providers/scene_providers.dart';
import '../domain/priority_engine.dart';

final nextActionProvider = Provider<PriorityAction?>((ref) {
  final subject = ref.watch(subjectProfileProvider);
  final scene = ref.watch(sceneProfileProvider);
  final goal = ref.watch(selectedGoalProvider);

  if (goal == null) return null;

  return getNextAction(subject, scene, goal);
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
