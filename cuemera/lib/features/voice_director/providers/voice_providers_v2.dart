// features/voice_director/providers/voice_providers_v2.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/app_tts_service.dart';
import '../../../core/services/error_reporting_service.dart';
import '../../../core/services/sherpa_tts_service.dart' show TtsEmphasis;
import '../../reference_photo/domain/models/reference_profile.dart';
import '../../reference_photo/providers/reference_providers.dart';
import '../../scene_analysis/domain/models/scene_profile.dart';
import '../../scene_analysis/domain/models/subject_profile.dart';
import '../../scene_analysis/providers/scene_providers.dart';
import '../../settings/providers/ai_coaching_providers.dart';
import '../../settings/providers/coaching_v2_settings_provider.dart';
import '../domain/action_plan.dart';
import '../domain/coaching_state_machine.dart';
import '../models/coaching_decision.dart';
import '../services/llm_contract.dart';
import '../services/llm_output_validator.dart';
import 'coaching_phrase_model_providers.dart';
import 'voice_providers.dart'
    show displayedCoachingPhraseProvider, referenceComparisonEngineProvider;

const _llmValidatorV2 = LlmOutputValidator();

const _generationTimeoutV2 = Duration(seconds: 5);
const _minLlmGenerationIntervalV2 = Duration(seconds: 3);

const _attributeSettleWindow = Duration(seconds: 2);

final coachingStateMachineProvider = Provider.autoDispose<CoachingStateMachine>(
  (ref) => CoachingStateMachine(),
);

double? currentMeasurementFor(
  CoachingAttribute attribute,
  SubjectProfile subject,
  SceneProfile scene,
) {
  switch (attribute) {
    case CoachingAttribute.shoulderAngle:
      return subject.shoulderAngleDegrees;
    case CoachingAttribute.facePitch:
      return subject.faceAngleXDegrees;
    case CoachingAttribute.faceRoll:
      return subject.faceAngleZDegrees;
    case CoachingAttribute.faceYaw:
      return subject.faceAngleDegrees;
    case CoachingAttribute.bodyRatio:
      return subject.bodyRatio;
    case CoachingAttribute.mouthOpen:
      return subject.mouthOpenRatio;
    case CoachingAttribute.eyeOpen:
      return subject.eyeOpenRatio;
    case CoachingAttribute.expression:
      return null;
    case CoachingAttribute.shoulderBalance:
      return subject.shoulderBalanceRatio;
    case CoachingAttribute.shoulderSpan:
      return subject.shoulderSpanRatio;
    case CoachingAttribute.bodyYaw:
      return subject.bodyYawEstimate;
    case CoachingAttribute.rightArmPosition:
    case CoachingAttribute.leftArmPosition:
      return null;
    case CoachingAttribute.negativeSpace:
      return scene.negativeSpaceScore;
    case CoachingAttribute.symmetry:
      return scene.symmetryScore;
    case CoachingAttribute.backgroundClutter:
      return scene.backgroundClutterCount.toDouble();
    case CoachingAttribute.brightness:
      return scene.brightness;
    case CoachingAttribute.warmth:
      return scene.liveWarmthScore;
    case CoachingAttribute.hue:
      return scene.liveDominantHue;
    case CoachingAttribute.lightDirection:
      return scene.lightDirectionDegrees;
    case CoachingAttribute.subjectPosition:
      return scene.subjectHorizontalPosition;
  }
}

double? referenceMeasurementFor(
  CoachingAttribute attribute,
  ReferenceProfile reference,
) {
  switch (attribute) {
    case CoachingAttribute.shoulderAngle:
      return reference.shoulderAngleDegrees;
    case CoachingAttribute.facePitch:
      return reference.faceAngleXDegrees;
    case CoachingAttribute.faceRoll:
      return reference.faceAngleZDegrees;
    case CoachingAttribute.faceYaw:
      return reference.faceAngleDegrees;
    case CoachingAttribute.bodyRatio:
      return reference.bodyRatio;
    case CoachingAttribute.mouthOpen:
      return reference.mouthOpenRatio;
    case CoachingAttribute.eyeOpen:
      return reference.eyeOpenRatio;
    case CoachingAttribute.expression:
      return null;
    case CoachingAttribute.shoulderBalance:
      return reference.shoulderBalanceRatio;
    case CoachingAttribute.shoulderSpan:
      return reference.shoulderSpanRatio;
    case CoachingAttribute.bodyYaw:
      return reference.bodyYawEstimate;
    case CoachingAttribute.rightArmPosition:
    case CoachingAttribute.leftArmPosition:
      return null;
    case CoachingAttribute.negativeSpace:
      return reference.negativeSpaceScore;
    case CoachingAttribute.symmetry:
      return reference.symmetryScore;
    case CoachingAttribute.backgroundClutter:
      return reference.backgroundClutterCount?.toDouble();
    case CoachingAttribute.brightness:
      return reference.overallBrightness;
    case CoachingAttribute.warmth:
      return reference.warmthScore;
    case CoachingAttribute.hue:
      return reference.dominantHue;
    case CoachingAttribute.lightDirection:
      return reference.lightDirectionDegrees;
    case CoachingAttribute.subjectPosition:
      return reference.subjectHorizontalPosition;
  }
}

bool attributeTemporallyEligible(
  CoachingAttribute attribute,
  SubjectProfile subject,
) {
  switch (attribute) {
    case CoachingAttribute.shoulderAngle:
      return subject.temporallyEligibleFor('shoulderAngleDegrees');
    case CoachingAttribute.shoulderBalance:
      return subject.temporallyEligibleFor('shoulderBalanceRatio');
    case CoachingAttribute.shoulderSpan:
      return subject.temporallyEligibleFor('shoulderSpanRatio');
    case CoachingAttribute.bodyYaw:
      return subject.temporallyEligibleFor('bodyYawEstimate');
    case CoachingAttribute.bodyRatio:
      return subject.temporallyEligibleFor('bodyRatio');
    // Bug found and fixed this session: face_analyzer.dart has populated
    // metricTemporalEligibility for these five fields since the
    // sixteenth session (same fields the seventeenth-session confidence
    // fix in reference_comparison_engine.dart targeted) — this function
    // just never picked it up, silently falling through to `default:
    // true` instead.
    case CoachingAttribute.facePitch:
      return subject.temporallyEligibleFor('faceAngleXDegrees');
    case CoachingAttribute.faceRoll:
      return subject.temporallyEligibleFor('faceAngleZDegrees');
    case CoachingAttribute.faceYaw:
      return subject.temporallyEligibleFor('faceAngleDegrees');
    case CoachingAttribute.mouthOpen:
      return subject.temporallyEligibleFor('mouthOpenRatio');
    case CoachingAttribute.eyeOpen:
      return subject.temporallyEligibleFor('eyeOpenRatio');
    case CoachingAttribute.rightArmPosition:
      return subject.temporallyEligibleFor('rightArmRaiseDegrees') &&
          subject.temporallyEligibleFor('rightElbowAngleDegrees');
    case CoachingAttribute.leftArmPosition:
      return subject.temporallyEligibleFor('leftArmRaiseDegrees') &&
          subject.temporallyEligibleFor('leftElbowAngleDegrees');
    default:
      return true;
  }
}

final voiceDirectorListenerV2Provider = Provider.autoDispose<void>((ref) {
  final ttsService = ref.watch(appTtsServiceProvider);
  final phraseModel = ref.watch(coachingPhraseModelServiceProvider);
  final lifecycle = ref.watch(modelLifecycleManagerProvider);
  final engine = ref.watch(referenceComparisonEngineProvider);
  final stateMachine = ref.watch(coachingStateMachineProvider);

  int tierRotation = 0;
  int generationEpoch = 0;
  DateTime? instructedAt;
  DateTime? lastGenerationAttemptAt;

  TtsEmphasis emphasisFor(CoachingSeverityBand severityBand) {
    switch (severityBand) {
      case CoachingSeverityBand.strong:
        return TtsEmphasis.strong;
      case CoachingSeverityBand.moderate:
        return TtsEmphasis.moderate;
      case CoachingSeverityBand.mild:
        return TtsEmphasis.mild;
    }
  }

  // Bug found and fixed this session: v1 (voice_providers.dart) checks
  // ttsService.isSpeaking and queues/retries before ever calling
  // .speak(); this file called .speak() unconditionally at every call
  // site, risking talking over its own still-playing previous utterance
  // if LLM generation happened to run long. Waits rather than skips, so
  // the state machine's already-committed instructed() timing is
  // unaffected — only the actual audio output is delayed.
  Future<void> waitForTtsFree() async {
    while (ttsService.isSpeaking) {
      await Future.delayed(const Duration(milliseconds: 150));
    }
  }

  Future<void> speakPlan(ActionPlan plan, int epoch) async {
    final emphasis = emphasisFor(plan.decision.severityBand);
    final aiUnavailable = ref.read(
      aiCoachingSettingsProvider.select((s) => s.aiUnavailable),
    );
    final aiCoachingEnabled = ref.read(
      aiCoachingSettingsProvider.select((s) => s.enabled),
    );

    if (kDebugMode) {
      debugPrint(
        'ai_gate(v2): aiUnavailable=$aiUnavailable, enabled=$aiCoachingEnabled, '
        'modelNull=${phraseModel == null}, lifecycleState=${lifecycle.state.name}',
      );
    }

    final now = DateTime.now();
    final llmCadenceOk =
        lastGenerationAttemptAt == null ||
        now.difference(lastGenerationAttemptAt!) >= _minLlmGenerationIntervalV2;

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
              ? 'ai_gate(v2): fallback to rule-based phrase'
              : 'ai_gate(v2): llm cadence floor not met, fallback to rule-based phrase',
        );
      }
      ref.read(displayedCoachingPhraseProvider.notifier).state = plan.phrase;
      await waitForTtsFree();
      ttsService.speak(plan.phrase, emphasis: emphasis);
      return;
    }
    lastGenerationAttemptAt = now;

    final stopwatch = Stopwatch()..start();
    String? generated;
    try {
      generated = await lifecycle
          .generate(phraseModel, plan.decision)
          .timeout(_generationTimeoutV2);
    } on TimeoutException catch (e, st) {
      ErrorReportingService.instance.report(
        e,
        st,
        context: 'voice_providers_v2: generation timeout',
      );
      generated = null;
    } catch (e, st) {
      ErrorReportingService.instance.report(
        e,
        st,
        context: 'voice_providers_v2: generation failure',
      );
      generated = null;
    }
    stopwatch.stop();

    // Bug found and fixed this session: v1 (voice_providers.dart) tracks
    // this telemetry, v2 never did — kept them in sync so a debug overlay
    // reading these two variables gets meaningful data regardless of
    // which listener is currently active.
    lastPhraseGenerationLatencyMs = stopwatch.elapsedMilliseconds;
    lastPhraseGenerationSucceeded = generated != null;
    if (kDebugMode) {
      debugPrint(
        'coaching_phrase_generation(v2): ${stopwatch.elapsedMilliseconds}ms, '
        'attribute=${plan.decision.attribute.name}, '
        'succeeded=${generated != null}',
      );
    }

    if (epoch != generationEpoch) return;

    if (generated != null) {
      final validation = _llmValidatorV2.validate(
        generated,
        LlmCoachingContract.fromDecision(plan.decision),
      );
      if (kDebugMode) {
        debugPrint(
          'ai_gate(v2): generated="$generated" ${validation.debugLine()}',
        );
      }

      if (validation.passed) {
        ref.read(displayedCoachingPhraseProvider.notifier).state = generated;
        await waitForTtsFree();
        ttsService.speak(generated, emphasis: emphasis);
        return;
      }

      ErrorReportingService.instance.report(
        StateError('llm output failed validation: ${validation.failure.name}'),
        StackTrace.current,
        context: 'voice_providers_v2: validation failed',
      );
      ref.read(displayedCoachingPhraseProvider.notifier).state = plan.phrase;
      await waitForTtsFree();
      ttsService.speak(plan.phrase, emphasis: emphasis);
      return;
    }

    if (kDebugMode) {
      debugPrint(
        'ai_gate(v2): generate() failed, lifecycleState=${lifecycle.state.name}',
      );
    }
    ref.read(displayedCoachingPhraseProvider.notifier).state = plan.phrase;
    await waitForTtsFree();
    ttsService.speak(plan.phrase, emphasis: emphasis);
  }

  void tick() {
    final v2Enabled = ref.read(
      coachingV2SettingsProvider.select((s) => s.enabled),
    );
    if (!v2Enabled) return;

    final subject = ref.read(subjectProfileProvider);
    final scene = ref.read(sceneProfileProvider);
    final reference = ref.read(referenceProfileProvider).valueOrNull;
    final tolerance = ref.read(toleranceSettingsProvider);
    final isFrontCamera = ref.read(isFrontCameraProvider);
    if (reference == null) return;

    switch (stateMachine.state) {
      case CoachingState.observe:
        final tiers = engine.evaluateTiers(
          subject: subject,
          scene: scene,
          reference: reference,
          tolerance: tolerance,
          isFrontCamera: isFrontCamera,
        );
        final output = stateMachine.observe(
          poseAndFace: tiers.poseAndFace,
          composition: tiers.composition,
          lighting: tiers.lighting,
          contextFor: (candidate) => EligibilityContext(
            subjectFullyInFrame: subject.subjectFullyInFrame ?? true,
            detectorsAgree: subject.detectorsAgree ?? true,
            temporallyEligible: attributeTemporallyEligible(
              candidate.decision.attribute,
              subject,
            ),
          ),
          tierRotation: tierRotation,
        );

        final plan = output.planToSpeak;
        if (plan != null) {
          tierRotation++;
          final preMeasurement =
              currentMeasurementFor(plan.decision.attribute, subject, scene) ??
              0.0;
          stateMachine.instructed(
            preMeasurement: preMeasurement,
            referenceTarget: referenceMeasurementFor(
              plan.decision.attribute,
              reference,
            ),
            noiseFloor: 0.5,
          );
          instructedAt = DateTime.now();
          generationEpoch++;
          speakPlan(plan, generationEpoch);
        }
        break;

      case CoachingState.wait:
        final startedAt = instructedAt;
        if (startedAt == null) {
          stateMachine.next();
          return;
        }
        if (!stateMachine.readyToReobserve(
          DateTime.now().difference(startedAt),
          _attributeSettleWindow,
        )) {
          return;
        }
        final attribute = stateMachine.currentPlan?.decision.attribute;
        final measured = attribute == null
            ? null
            : currentMeasurementFor(attribute, subject, scene);
        stateMachine.reobserve(
          measuredValue: measured,
          measurementConfident: measured != null,
        );
        if (stateMachine.state == CoachingState.wait) {
          instructedAt = DateTime.now();
        }
        break;

      case CoachingState.confirm:
      case CoachingState.escalate:
      case CoachingState.abandon:
        instructedAt = null;
        stateMachine.next();
        break;

      default:
        break;
    }
  }

  ref.listen<SubjectProfile>(subjectProfileProvider, (previous, next) {
    tick();
  });
});
