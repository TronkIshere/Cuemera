// features/voice_director/domain/coaching_state_machine.dart
//
// Replaces the flat Timer/lastDedupeKey/generationEpoch trio in
// voice_providers.dart with the state machine designed in the audit's §12:
//
//   OBSERVE -> VERIFY -> SELECT_PRIORITY -> INSTRUCT -> WAIT -> REOBSERVE
//   -> VERIFY_IMPROVEMENT -> CONFIRM / ESCALATE / ABANDON -> NEXT (-> OBSERVE)
//
// This file is written as a pull-based state machine (the caller drives it
// forward by calling its methods with fresh measurements) rather than
// wired directly to Riverpod providers, since voice_providers.dart's exact
// current provider graph wasn't available to review directly (see the
// audit's integration-fidelity note in §20). voice_providers.dart's
// eventual job is to own one instance of this class and call its methods
// from ref.listen callbacks / a periodic timer, per the audit's §19 plan
// for that file.
//
// This is also the component that owns SessionMemory — root-cause,
// eligibility, and priority all *read* session memory; this file is the
// only one that *writes* it, per the audit's §10 rationale for keeping
// session memory as shared state rather than one more pipeline stage.

import 'package:cuemera/features/voice_director/domain/action_plan.dart';
import 'package:cuemera/features/voice_director/domain/adaptive_correction_model.dart';
import 'package:cuemera/features/voice_director/domain/coaching_eligibility.dart';
import 'package:cuemera/features/voice_director/domain/correction_feedback.dart';
import 'package:cuemera/features/voice_director/domain/root_cause_engine.dart';
import 'package:cuemera/features/voice_director/models/coaching_decision.dart';

enum CoachingState {
  observe,
  verify,
  selectPriority,
  instruct,
  wait,
  reobserve,
  verifyImprovement,
  confirm,
  escalate,
  abandon,
}

class SessionMemory {
  final Map<CoachingAttribute, int> attemptCounts = {};
  final Map<CoachingAttribute, int> reversalCounts = {};
  final Set<CoachingAttribute> suppressedForSession = {};
  final Map<CoachingAttribute, DateTime> lastResolvedAt = {};

  static const int maxAttemptsBeforeAbandon = 3;

  static const int maxReversalsBeforeSuppression = 2;

  bool isSuppressed(CoachingAttribute attribute) =>
      suppressedForSession.contains(attribute);

  void recordAttempt(CoachingAttribute attribute) {
    attemptCounts[attribute] = (attemptCounts[attribute] ?? 0) + 1;
  }

  /// Returns true if this attribute should now be abandoned for the
  /// session (caller uses this to decide ABANDON vs. another ESCALATE/retry).
  bool recordOutcomeAndCheckAbandon(
    CoachingAttribute attribute,
    CorrectionOutcome outcome,
  ) {
    if (outcome == CorrectionOutcome.improved) {
      lastResolvedAt[attribute] = DateTime.now();
      attemptCounts[attribute] = 0;
      return false;
    }
    if (outcome == CorrectionOutcome.reversed) {
      reversalCounts[attribute] = (reversalCounts[attribute] ?? 0) + 1;
      if (reversalCounts[attribute]! >= maxReversalsBeforeSuppression) {
        suppressedForSession.add(attribute);
        return true;
      }
    }
    return (attemptCounts[attribute] ?? 0) >= maxAttemptsBeforeAbandon;
  }

  bool inPostResolutionGrace(
    CoachingAttribute attribute,
    DateTime now,
    Duration grace,
  ) {
    final resolvedAt = lastResolvedAt[attribute];
    if (resolvedAt == null) return false;
    return now.difference(resolvedAt) < grace;
  }
}

class EligibilityContext {
  const EligibilityContext({
    required this.subjectFullyInFrame,
    required this.detectorsAgree,
    required this.temporallyEligible,
  });

  final bool subjectFullyInFrame;
  final bool detectorsAgree;
  final bool temporallyEligible;
}

class CoachingStepOutput {
  const CoachingStepOutput({
    required this.state,
    this.planToSpeak,
    this.debugLine,
  });
  final CoachingState state;

  final ActionPlan? planToSpeak;
  final String? debugLine;
}

class CoachingStateMachine {
  CoachingStateMachine({
    CoachingEligibility? eligibility,
    RootCauseEngine? rootCause,
    ResponsivenessModel? responsiveness,
    this.postResolutionGrace = const Duration(seconds: 3),
    this.maxWaitRetries = 2,
  }) : eligibility = eligibility ?? const CoachingEligibility(),
       rootCause = rootCause ?? const RootCauseEngine(),
       responsiveness = responsiveness ?? ResponsivenessModel();

  final CoachingEligibility eligibility;
  final RootCauseEngine rootCause;
  final ResponsivenessModel responsiveness;
  final SessionMemory sessionMemory = SessionMemory();

  final Duration postResolutionGrace;
  final int maxWaitRetries;

  CoachingState _state = CoachingState.observe;
  ActionPlan? _currentPlan;
  CorrectionRecord? _openRecord;
  int _retriesForCurrentAttribute = 0;

  CoachingState get state => _state;
  ActionPlan? get currentPlan => _currentPlan;

  CoachingStepOutput observe({
    required List<ActionPlan> poseAndFace,
    required List<ActionPlan> composition,
    required List<ActionPlan> lighting,
    required EligibilityContext Function(ActionPlan) contextFor,
    required int tierRotation,
    DateTime? now,
  }) {
    assert(
      _state == CoachingState.observe,
      'observe() called while a cycle is already in flight',
    );
    final at = now ?? DateTime.now();

    _state = CoachingState.verify;

    List<ActionPlan> filterEligible(List<ActionPlan> tier) {
      final collapsed = rootCause.collapse(tier);
      return collapsed.where((plan) {
        if (sessionMemory.isSuppressed(plan.decision.attribute)) return false;
        if (sessionMemory.inPostResolutionGrace(
          plan.decision.attribute,
          at,
          postResolutionGrace,
        ))
          return false;
        final ctx = contextFor(plan);
        final result = eligibility.evaluatePlan(
          plan,
          subjectFullyInFrame: ctx.subjectFullyInFrame,
          detectorsAgree: ctx.detectorsAgree,
          temporallyEligible: ctx.temporallyEligible,
          inCooldown:
              false, // per-metric cooldown already reflected in temporallyEligible
        );
        return result.eligible;
      }).toList();
    }

    final eligiblePose = filterEligible(poseAndFace);
    final eligibleComp = filterEligible(composition);
    final eligibleLight = filterEligible(lighting);

    _state = CoachingState.selectPriority;
    final chosen = pickAcrossTiers(
      poseAndFace: eligiblePose,
      composition: eligibleComp,
      lighting: eligibleLight,
      tierRotation: tierRotation,
    );

    if (chosen == null) {
      _state = CoachingState.observe;
      return const CoachingStepOutput(
        state: CoachingState.observe,
        debugLine: 'OBSERVE: nothing eligible',
      );
    }

    _currentPlan = chosen;
    _retriesForCurrentAttribute = 0;
    _state = CoachingState.instruct;
    sessionMemory.recordAttempt(chosen.decision.attribute);

    return CoachingStepOutput(
      state: CoachingState.instruct,
      planToSpeak: chosen,
      debugLine: chosen.debugLine(1, eligible: true),
    );
  }

  void instructed({
    required double preMeasurement,
    required double? referenceTarget,
    required double noiseFloor,
    DateTime? now,
  }) {
    assert(_state == CoachingState.instruct);
    final plan = _currentPlan!;
    _openRecord = CorrectionRecord(
      attribute: plan.decision.attribute,
      preMeasurement: preMeasurement,
      referenceTarget: referenceTarget,
      expectedDirection: plan.decision.direction,
      instructedAt: now ?? DateTime.now(),
      noiseFloor: noiseFloor,
    );
    _state = CoachingState.wait;
  }

  bool readyToReobserve(
    Duration elapsedSinceInstruct,
    Duration attributeSettleWindow,
  ) =>
      _state == CoachingState.wait &&
      elapsedSinceInstruct >= attributeSettleWindow;

  CorrectionOutcome reobserve({
    required double? measuredValue,
    required bool measurementConfident,
  }) {
    assert(_state == CoachingState.wait);
    _state = CoachingState.reobserve;
    final record = _openRecord!;
    record.close(
      measuredValue: measuredValue,
      measurementConfident: measurementConfident,
    );
    _state = CoachingState.verifyImprovement;

    final outcome = record.outcome!;

    if (outcome == CorrectionOutcome.unmeasurable &&
        _retriesForCurrentAttribute < maxWaitRetries) {
      _retriesForCurrentAttribute++;
      _state = CoachingState
          .wait; // give it one more settle window before giving up on measuring
      return outcome;
    }

    final plan = _currentPlan!;
    if (outcome == CorrectionOutcome.improved) {
      _state = CoachingState.confirm;
      sessionMemory.recordOutcomeAndCheckAbandon(
        plan.decision.attribute,
        outcome,
      );
      responsiveness.recordOutcome(record, plan.decision.severityBand);
    } else if (outcome == CorrectionOutcome.overshot ||
        outcome == CorrectionOutcome.reversed) {
      final shouldAbandon = sessionMemory.recordOutcomeAndCheckAbandon(
        plan.decision.attribute,
        outcome,
      );
      responsiveness.recordOutcome(record, plan.decision.severityBand);
      _state = shouldAbandon ? CoachingState.abandon : CoachingState.escalate;
    } else {
      // unchanged, or unmeasurable after exhausting retries
      final shouldAbandon = sessionMemory.recordOutcomeAndCheckAbandon(
        plan.decision.attribute,
        outcome,
      );
      _state = shouldAbandon ? CoachingState.abandon : CoachingState.escalate;
    }

    return outcome;
  }

  void next() {
    _currentPlan = null;
    _openRecord = null;
    _retriesForCurrentAttribute = 0;
    _state = CoachingState.observe;
  }
}
