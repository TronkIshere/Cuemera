// features/voice_director/domain/models/coaching_decision.dart

enum CoachingAttribute {
  shoulderAngle,
  facePitch,
  faceRoll,
  faceYaw,
  bodyRatio,
  mouthOpen,
  eyeOpen,
  expression,
  negativeSpace,
  symmetry,
  backgroundClutter,
  brightness,
  warmth,
  hue,
  shoulderBalance,
  shoulderSpan,
  bodyYaw,
}

enum CoachingDirection { increase, decrease, left, right, none }

enum CoachingTier { poseAndFace, composition, lighting }

enum CoachingSeverityBand { mild, moderate, strong }

class CoachingDecision {
  const CoachingDecision({
    required this.attribute,
    required this.direction,
    required this.tier,
    required this.normalizedSeverity,
    required this.fallbackPhrase,
    this.targetExpression,
  });

  static const double mildSeverityCeiling = 0.4;
  static const double moderateSeverityCeiling = 0.75;

  final CoachingAttribute attribute;
  final CoachingDirection direction;
  final CoachingTier tier;
  final double normalizedSeverity;
  final String fallbackPhrase;

  final String? targetExpression;

  CoachingSeverityBand get severityBand {
    if (normalizedSeverity < mildSeverityCeiling) {
      return CoachingSeverityBand.mild;
    }
    if (normalizedSeverity < moderateSeverityCeiling) {
      return CoachingSeverityBand.moderate;
    }
    return CoachingSeverityBand.strong;
  }

  String get dedupeKey {
    if (attribute == CoachingAttribute.expression) {
      return '${attribute.name}:${targetExpression ?? ''}';
    }
    return '${attribute.name}:${direction.name}:${severityBand.name}';
  }
}
