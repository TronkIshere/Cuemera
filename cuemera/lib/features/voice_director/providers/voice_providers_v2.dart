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
import 'coaching_phrase_model_providers.dart';
import 'voice_providers.dart'
    show displayedCoachingPhraseProvider, referenceComparisonEngineProvider;

const _generationTimeoutV2 = Duration(seconds: 5);
const _maxConsecutiveFailuresBeforeUnavailableV2 = 3;

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
      return null;
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
      return null;
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
  }
}

final voiceDirectorListenerV2Provider = Provider.autoDispose<void>((ref) {
  final ttsService = ref.watch(appTtsServiceProvider);
  final phraseModel = ref.watch(coachingPhraseModelServiceProvider);
  final engine = ref.watch(referenceComparisonEngineProvider);
  final stateMachine = ref.watch(coachingStateMachineProvider);

  int tierRotation = 0;
  int consecutiveFailures = 0;
  int generationEpoch = 0;
  DateTime? instructedAt;

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

  Future<void> speakPlan(ActionPlan plan, int epoch) async {
    final emphasis = emphasisFor(plan.decision.severityBand);
    final aiUnavailable = ref.read(coachingAiUnavailableProvider);
    final aiCoachingEnabled = ref.read(
      aiCoachingSettingsProvider.select((s) => s.enabled),
    );

    debugPrint(
      'ai_gate(v2): aiUnavailable=$aiUnavailable, enabled=$aiCoachingEnabled, '
      'modelNull=${phraseModel == null}, isReady=${phraseModel?.isReady}',
    );

    if (aiUnavailable ||
        !aiCoachingEnabled ||
        phraseModel == null ||
        !phraseModel.isReady) {
      ref.read(displayedCoachingPhraseProvider.notifier).state = plan.phrase;
      ttsService.speak(plan.phrase, emphasis: emphasis);
      return;
    }

    String? generated;
    try {
      generated = await phraseModel
          .generate(plan.decision)
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

    if (epoch != generationEpoch) return;

    if (generated != null) {
      consecutiveFailures = 0;
      ref.read(displayedCoachingPhraseProvider.notifier).state = generated;
      ttsService.speak(generated, emphasis: emphasis);
      return;
    }

    consecutiveFailures++;
    if (consecutiveFailures >= _maxConsecutiveFailuresBeforeUnavailableV2) {
      ref.read(coachingAiUnavailableProvider.notifier).state = true;
    }
    ref.read(displayedCoachingPhraseProvider.notifier).state = plan.phrase;
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
    if (reference == null) return;

    switch (stateMachine.state) {
      case CoachingState.observe:
        final tiers = engine.evaluateTiers(
          subject: subject,
          scene: scene,
          reference: reference,
          tolerance: tolerance,
        );
        final output = stateMachine.observe(
          poseAndFace: tiers.poseAndFace,
          composition: tiers.composition,
          lighting: tiers.lighting,
          contextFor: (_) => const EligibilityContext(
            subjectFullyInFrame: true,
            detectorsAgree: true,
            temporallyEligible: true,
          ),
          tierRotation: tierRotation,
        );
        tierRotation++;

        final plan = output.planToSpeak;
        if (plan != null) {
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
