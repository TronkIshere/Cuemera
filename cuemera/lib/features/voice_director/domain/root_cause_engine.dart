// features/voice_director/domain/root_cause_engine.dart
import 'package:cuemera/core/confidence/confidence.dart';
import 'package:cuemera/features/voice_director/domain/action_plan.dart';
import 'package:cuemera/features/voice_director/models/coaching_decision.dart';

enum RootCauseCluster {
  torsoRotationOrLean,
  headOrientation,
  facialExpression,
  none,
}

const Map<RootCauseCluster, List<CoachingAttribute>> kClusterMembers = {
  RootCauseCluster.torsoRotationOrLean: [
    CoachingAttribute.bodyYaw,
    CoachingAttribute.shoulderAngle,
    CoachingAttribute.shoulderBalance,
    CoachingAttribute.shoulderSpan,
  ],
  RootCauseCluster.headOrientation: [
    CoachingAttribute.facePitch,
    CoachingAttribute.faceRoll,
    CoachingAttribute.faceYaw,
  ],
  RootCauseCluster.facialExpression: [
    CoachingAttribute.mouthOpen,
    CoachingAttribute.eyeOpen,
    CoachingAttribute.expression,
  ],
};

final Map<CoachingAttribute, RootCauseCluster> kAttributeCluster = {
  for (final entry in kClusterMembers.entries)
    for (final attribute in entry.value) attribute: entry.key,
};

const Map<RootCauseCluster, CoachingAttribute?> kClusterRepresentative = {
  RootCauseCluster.torsoRotationOrLean: CoachingAttribute.bodyYaw,
  RootCauseCluster.headOrientation: null,
  RootCauseCluster.facialExpression: CoachingAttribute.expression,
};

class RootCauseEngine {
  const RootCauseEngine();

  List<ActionPlan> collapse(List<ActionPlan> candidates) {
    final byCluster = <RootCauseCluster, List<ActionPlan>>{};
    final singletons = <ActionPlan>[];

    for (final plan in candidates) {
      final cluster =
          kAttributeCluster[plan.decision.attribute] ?? RootCauseCluster.none;
      if (cluster == RootCauseCluster.none) {
        singletons.add(plan);
      } else {
        byCluster.putIfAbsent(cluster, () => []).add(plan);
      }
    }

    final result = <ActionPlan>[...singletons];

    for (final entry in byCluster.entries) {
      final members = entry.value;
      if (members.length < 2) {
        result.addAll(members); // only one member fired — no false merge
        continue;
      }
      result.add(_collapseCluster(entry.key, members));
    }

    return result;
  }

  ActionPlan _collapseCluster(
    RootCauseCluster cluster,
    List<ActionPlan> members,
  ) {
    final fixedRepresentative = kClusterRepresentative[cluster];
    final representative = fixedRepresentative == null
        ? members.reduce(
            (a, b) =>
                a.decision.normalizedSeverity >= b.decision.normalizedSeverity
                ? a
                : b,
          )
        : members.firstWhere(
            (m) => m.decision.attribute == fixedRepresentative,
            orElse: () => members.reduce(
              (a, b) =>
                  a.decision.normalizedSeverity >= b.decision.normalizedSeverity
                  ? a
                  : b,
            ),
          );

    final maxSeverity = members
        .map((m) => m.decision.normalizedSeverity)
        .reduce((a, b) => a > b ? a : b);

    final combinedConfidence = Confidence.minOf(
      members.map((m) => Confidence(m.confidence)),
    ).value;

    final boostedDecision = CoachingDecision(
      attribute: representative.decision.attribute,
      direction: representative.decision.direction,
      tier: representative.decision.tier,
      normalizedSeverity: maxSeverity,
      fallbackPhrase: representative.decision.fallbackPhrase,
      targetExpression: representative.decision.targetExpression,
    );

    return ActionPlan(
      phrase: representative.phrase,
      decision: boostedDecision,
      sourceLayer:
          'root_cause_engine(${cluster.name}, collapsed:${members.length})',
      confidence: combinedConfidence,
      controllability: representative.controllability,
    );
  }
}
