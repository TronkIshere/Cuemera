import 'package:cuemera/features/voice_director/models/coaching_decision.dart';

class AttributeEvaluation {
  const AttributeEvaluation({
    required this.deviationExceedsThreshold,
    required this.decision,
  });

  final bool deviationExceedsThreshold;
  final CoachingDecision decision;

  String get phrase => decision.fallbackPhrase;
}

String tieredPhrase(
  double normalizedSeverity, {
  required String mild,
  required String moderate,
  required String strong,
}) {
  if (normalizedSeverity < CoachingDecision.mildSeverityCeiling) return mild;
  if (normalizedSeverity < CoachingDecision.moderateSeverityCeiling) {
    return moderate;
  }
  return strong;
}
