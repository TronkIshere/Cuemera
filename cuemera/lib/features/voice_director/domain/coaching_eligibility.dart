// features/voice_director/domain/coaching_eligibility.dart
//
// The concrete mechanism behind "the system must prefer silence over giving
// an incorrect instruction." Today, nothing in the pipeline can produce
// DO_NOT_COACH — every _evaluate* method's only escape hatch is a raw
// nullable field being null (D6 in the audit). This file is the missing
// gate, meant to sit between root_cause_engine.dart's collapsed candidates
// and action_plan.dart's pickBest()/pickAcrossTiers() — cheap checks first,
// so it can eliminate most candidates before the O(n log n) priority sort
// ever runs (see the audit's §10 rationale for this ordering).

import 'package:cuemera/core/confidence/confidence.dart';
import 'package:cuemera/features/voice_director/domain/action_plan.dart';

enum IneligibilityReason {
  none,
  confidenceTooLow,
  subjectPartiallyOutOfFrame,
  detectorDisagreement,
  notPersistentEnough,
  inCooldown,
  notSubjectControllable,
}

class EligibilityResult {
  const EligibilityResult.eligible()
    : eligible = true,
      reason = IneligibilityReason.none;

  const EligibilityResult.ineligible(this.reason) : eligible = false;

  final bool eligible;
  final IneligibilityReason reason;

  String debugLine(String attributeName) =>
      'ELIGIBILITY: candidate=$attributeName eligible=$eligible reason=${reason.name}';
}

class CoachingEligibility {
  const CoachingEligibility({
    this.confidenceFloor = ConfidenceFloors.eligibleToSpeak,
    this.cameraFacingChannelEnabled = false,
  });

  final double confidenceFloor;

  final bool cameraFacingChannelEnabled;

  EligibilityResult evaluate({
    required double decisionConfidence,
    required ActionControllability controllability,
    required bool subjectFullyInFrame,
    required bool detectorsAgree,
    required bool temporallyEligible,
    required bool inCooldown,
  }) {
    if (controllability == ActionControllability.doNotCoach) {
      return const EligibilityResult.ineligible(
        IneligibilityReason.notSubjectControllable,
      );
    }

    if (!cameraFacingChannelEnabled &&
        controllability != ActionControllability.subjectAction) {
      return const EligibilityResult.ineligible(
        IneligibilityReason.notSubjectControllable,
      );
    }

    if (decisionConfidence < confidenceFloor) {
      return const EligibilityResult.ineligible(
        IneligibilityReason.confidenceTooLow,
      );
    }

    if (controllability == ActionControllability.subjectAction &&
        !subjectFullyInFrame) {
      return const EligibilityResult.ineligible(
        IneligibilityReason.subjectPartiallyOutOfFrame,
      );
    }

    if (!detectorsAgree) {
      return const EligibilityResult.ineligible(
        IneligibilityReason.detectorDisagreement,
      );
    }

    if (!temporallyEligible) {
      return const EligibilityResult.ineligible(
        IneligibilityReason.notPersistentEnough,
      );
    }

    if (inCooldown) {
      return const EligibilityResult.ineligible(IneligibilityReason.inCooldown);
    }

    return const EligibilityResult.eligible();
  }

  EligibilityResult evaluatePlan(
    ActionPlan plan, {
    required bool subjectFullyInFrame,
    required bool detectorsAgree,
    required bool temporallyEligible,
    required bool inCooldown,
  }) {
    return evaluate(
      decisionConfidence: plan.confidence,
      controllability: plan.controllability,
      subjectFullyInFrame: subjectFullyInFrame,
      detectorsAgree: detectorsAgree,
      temporallyEligible: temporallyEligible,
      inCooldown: inCooldown,
    );
  }
}
