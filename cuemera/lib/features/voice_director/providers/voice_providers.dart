// features/voice_director/providers/voice_providers.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/app_tts_service.dart';
import '../../../core/services/sherpa_tts_service.dart' show TtsEmphasis;
import '../../reference_photo/providers/reference_providers.dart';
import '../../scene_analysis/providers/scene_providers.dart';
import '../../settings/providers/ai_coaching_providers.dart';
import '../domain/priority_engine.dart';
import '../domain/reference_comparison_engine.dart';
import 'coaching_phrase_model_providers.dart';

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

final displayedCoachingPhraseProvider = StateProvider<String?>((ref) => null);

const _generationTimeout = Duration(seconds: 3);
const _maxConsecutiveFailuresBeforeUnavailable = 3;

final voiceDirectorListenerProvider = Provider.autoDispose<void>((ref) {
  final ttsService = ref.watch(appTtsServiceProvider);
  final phraseModel = ref.watch(coachingPhraseModelServiceProvider);

  String? lastDedupeKey;
  Timer? debounceTimer;
  int consecutiveFailures = 0;
  int generationEpoch = 0;

  TtsEmphasis emphasisFor(severityBand) {
    try {
      switch (severityBand.name) {
        case 'strong':
          return TtsEmphasis.strong;
        case 'moderate':
          return TtsEmphasis.moderate;
        default:
          return TtsEmphasis.mild;
      }
    } catch (_) {
      return TtsEmphasis.mild;
    }
  }

  Future<void> speakForDecision(PriorityAction action, int epoch) async {
    final emphasis = emphasisFor(action.decision.severityBand);
    final aiUnavailable = ref.read(coachingAiUnavailableProvider);
    final aiCoachingEnabled = ref.read(
      aiCoachingSettingsProvider.select((s) => s.enabled),
    );

    if (aiUnavailable ||
        !aiCoachingEnabled ||
        phraseModel == null ||
        !phraseModel.isReady) {
      ref.read(displayedCoachingPhraseProvider.notifier).state = action.phrase;
      ttsService.speak(action.phrase, emphasis: emphasis);
      return;
    }

    final stopwatch = Stopwatch()..start();
    String? generated;
    try {
      generated = await phraseModel
          .generate(action.decision)
          .timeout(_generationTimeout);
    } catch (_) {
      generated = null;
    }
    stopwatch.stop();

    lastPhraseGenerationLatencyMs = stopwatch.elapsedMilliseconds;
    lastPhraseGenerationSucceeded = generated != null;
    debugPrint(
      'coaching_phrase_generation: ${stopwatch.elapsedMilliseconds}ms, '
      'attribute=${action.decision.attribute.name}, '
      'succeeded=${generated != null}',
    );

    if (epoch != generationEpoch) return;

    if (generated != null) {
      consecutiveFailures = 0;
      ref.read(displayedCoachingPhraseProvider.notifier).state = generated;
      ttsService.speak(generated, emphasis: emphasis);
      return;
    }

    consecutiveFailures++;
    if (consecutiveFailures >= _maxConsecutiveFailuresBeforeUnavailable) {
      ref.read(coachingAiUnavailableProvider.notifier).state = true;
    }
    ref.read(displayedCoachingPhraseProvider.notifier).state = action.phrase;
    ttsService.speak(action.phrase, emphasis: emphasis);
  }

  ref.listen<PriorityAction?>(nextActionProvider, (previous, next) {
    if (next == null) return;
    if (next.decision.dedupeKey == lastDedupeKey) return;

    debounceTimer?.cancel();
    debounceTimer = Timer(const Duration(milliseconds: 400), () {
      if (ttsService.isSpeaking) return;
      lastDedupeKey = next.decision.dedupeKey;
      generationEpoch++;
      speakForDecision(next, generationEpoch);
    });
  });

  ref.onDispose(() {
    debounceTimer?.cancel();
  });
});
