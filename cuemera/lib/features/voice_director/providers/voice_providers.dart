// features/voice_director/providers/voice_providers.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/app_tts_service.dart';
import '../../../core/services/error_reporting_service.dart';
import '../../../core/services/sherpa_tts_service.dart' show TtsEmphasis;
import '../../reference_photo/providers/reference_providers.dart';
import '../../scene_analysis/providers/scene_providers.dart';
import '../../settings/providers/ai_coaching_providers.dart';
import '../domain/action_plan.dart';
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

const _generationTimeout = Duration(seconds: 5);
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

    debugPrint(
      'ai_gate: aiUnavailable=$aiUnavailable, enabled=$aiCoachingEnabled, '
      'modelNull=${phraseModel == null}, isReady=${phraseModel?.isReady}',
    );

    if (aiUnavailable ||
        !aiCoachingEnabled ||
        phraseModel == null ||
        !phraseModel.isReady) {
      debugPrint('ai_gate: fallback to rule-based phrase');
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
    } on TimeoutException catch (e, st) {
      ErrorReportingService.instance.report(
        e,
        st,
        context: 'voice_providers: generation timeout',
      );
      generated = null;
    } catch (e, st) {
      ErrorReportingService.instance.report(
        e,
        st,
        context: 'voice_providers: generation failure',
      );
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
      debugPrint('ai_gate: generated="$generated"');
      consecutiveFailures = 0;
      ref.read(displayedCoachingPhraseProvider.notifier).state = generated;
      ttsService.speak(generated, emphasis: emphasis);
      return;
    }

    consecutiveFailures++;
    debugPrint(
      'ai_gate: generate() failed, consecutiveFailures=$consecutiveFailures',
    );
    if (consecutiveFailures >= _maxConsecutiveFailuresBeforeUnavailable) {
      debugPrint('ai_gate: marking AI unavailable');
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
