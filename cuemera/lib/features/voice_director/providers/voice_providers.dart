// features/voice_director/providers/voice_providers.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/confidence/confidence.dart';
import '../../../core/services/app_tts_service.dart';
import '../../../core/services/error_reporting_service.dart';
import '../../../core/services/sherpa_tts_service.dart' show TtsEmphasis;
import '../../reference_photo/providers/reference_providers.dart';
import '../../scene_analysis/providers/scene_providers.dart';
import '../../settings/providers/ai_coaching_providers.dart';
import '../domain/action_plan.dart';
import '../domain/reference_comparison_engine.dart';
import '../services/llm_contract.dart';
import '../services/llm_output_validator.dart';
import 'coaching_phrase_model_providers.dart';

const _llmValidator = LlmOutputValidator();

final referenceComparisonEngineProvider = Provider<ReferenceComparisonEngine>(
  (ref) => ReferenceComparisonEngine(),
);

final nextActionProvider = Provider<PriorityAction?>((ref) {
  final subject = ref.watch(subjectProfileProvider);
  final scene = ref.watch(sceneProfileProvider);
  final referenceAsync = ref.watch(referenceProfileProvider);
  final tolerance = ref.watch(toleranceSettingsProvider);
  final engine = ref.watch(referenceComparisonEngineProvider);
  final isFrontCamera = ref.watch(isFrontCameraProvider);

  final reference = referenceAsync.valueOrNull;
  if (reference == null) return null;

  return engine.evaluate(
    subject: subject,
    scene: scene,
    reference: reference,
    tolerance: tolerance,
    isFrontCamera: isFrontCamera,
  );
});

final displayedCoachingPhraseProvider = StateProvider<String?>((ref) => null);

const _generationTimeout = Duration(seconds: 5);
const _minLlmGenerationInterval = Duration(seconds: 3);

final voiceDirectorListenerProvider = Provider.autoDispose<void>((ref) {
  final ttsService = ref.watch(appTtsServiceProvider);
  final phraseModel = ref.watch(coachingPhraseModelServiceProvider);
  final lifecycle = ref.watch(modelLifecycleManagerProvider);

  String? lastDedupeKey;
  Timer? debounceTimer;
  Timer? pendingRetryTimer;
  int generationEpoch = 0;
  DateTime? lastGenerationAttemptAt;
  PriorityAction? pendingAction;

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
    final aiUnavailable = ref.read(
      aiCoachingSettingsProvider.select((s) => s.aiUnavailable),
    );
    final aiCoachingEnabled = ref.read(
      aiCoachingSettingsProvider.select((s) => s.enabled),
    );

    if (kDebugMode) {
      debugPrint(
        'ai_gate: aiUnavailable=$aiUnavailable, enabled=$aiCoachingEnabled, '
        'modelNull=${phraseModel == null}, lifecycleState=${lifecycle.state.name}',
      );
    }

    final now = DateTime.now();
    final llmCadenceOk =
        lastGenerationAttemptAt == null ||
        now.difference(lastGenerationAttemptAt!) >= _minLlmGenerationInterval;

    if (aiUnavailable ||
        !aiCoachingEnabled ||
        phraseModel == null ||
        !lifecycle.canAttemptGeneration ||
        !llmCadenceOk) {
      if (kDebugMode) {
        debugPrint(
          aiUnavailable ||
                  !aiCoachingEnabled ||
                  phraseModel == null ||
                  !lifecycle.canAttemptGeneration
              ? 'ai_gate: fallback to rule-based phrase'
              : 'ai_gate: llm cadence floor not met, fallback to rule-based phrase',
        );
      }
      ref.read(displayedCoachingPhraseProvider.notifier).state = action.phrase;
      ttsService.speak(action.phrase, emphasis: emphasis);
      return;
    }
    lastGenerationAttemptAt = now;

    final stopwatch = Stopwatch()..start();
    String? generated;
    try {
      generated = await lifecycle
          .generate(phraseModel, action.decision)
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
    if (kDebugMode) {
      debugPrint(
        'coaching_phrase_generation: ${stopwatch.elapsedMilliseconds}ms, '
        'attribute=${action.decision.attribute.name}, '
        'succeeded=${generated != null}',
      );
    }

    if (epoch != generationEpoch) return;

    if (generated != null) {
      final validation = _llmValidator.validate(
        generated,
        LlmCoachingContract.fromDecision(action.decision),
      );
      if (kDebugMode) {
        debugPrint('ai_gate: generated="$generated" ${validation.debugLine()}');
      }

      if (validation.passed) {
        ref.read(displayedCoachingPhraseProvider.notifier).state = generated;
        ttsService.speak(generated, emphasis: emphasis);
        return;
      }

      ErrorReportingService.instance.report(
        StateError('llm output failed validation: ${validation.failure.name}'),
        StackTrace.current,
        context: 'voice_providers: validation failed',
      );
      ref.read(displayedCoachingPhraseProvider.notifier).state = action.phrase;
      ttsService.speak(action.phrase, emphasis: emphasis);
      return;
    }

    if (kDebugMode) {
      debugPrint(
        'ai_gate: generate() failed, lifecycleState=${lifecycle.state.name}',
      );
    }
    ref.read(displayedCoachingPhraseProvider.notifier).state = action.phrase;
    ttsService.speak(action.phrase, emphasis: emphasis);
  }

  void trySpeak(PriorityAction action) {
    if (ttsService.isSpeaking) {
      pendingAction = action;
      pendingRetryTimer ??= Timer.periodic(const Duration(milliseconds: 250), (
        _,
      ) {
        final queued = pendingAction;
        if (queued == null || ttsService.isSpeaking) return;
        pendingAction = null;
        pendingRetryTimer?.cancel();
        pendingRetryTimer = null;
        lastDedupeKey = queued.decision.dedupeKey;
        generationEpoch++;
        speakForDecision(queued, generationEpoch);
      });
      return;
    }
    lastDedupeKey = action.decision.dedupeKey;
    generationEpoch++;
    speakForDecision(action, generationEpoch);
  }

  ref.listen<PriorityAction?>(nextActionProvider, (previous, next) {
    if (next == null) return;
    if (next.decision.dedupeKey == lastDedupeKey) return;
    if (pendingAction?.decision.dedupeKey == next.decision.dedupeKey) return;

    if (next.confidence < ConfidenceFloors.eligibleToSpeak) {
      if (kDebugMode) {
        debugPrint(
          'confidence_gate: ${next.decision.attribute.name} confidence='
          '${next.confidence.toStringAsFixed(2)} below eligibleToSpeak '
          '(${ConfidenceFloors.eligibleToSpeak}) — not speaking',
        );
      }
      return;
    }

    debounceTimer?.cancel();
    debounceTimer = Timer(const Duration(milliseconds: 400), () {
      trySpeak(next);
    });
  });

  ref.onDispose(() {
    debounceTimer?.cancel();
    pendingRetryTimer?.cancel();
  });
});
