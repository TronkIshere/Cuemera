// features/voice_director/domain/models/coaching_decision.dart

import 'package:cuemera/features/voice_director/domain/action_plan.dart'
    show ActionControllability;

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
  rightArmPosition,
  leftArmPosition,
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
    required this.confidence,
    required this.controllability,
    this.targetExpression,
  });

  static const double mildSeverityCeiling = 0.4;
  static const double moderateSeverityCeiling = 0.75;

  final CoachingAttribute attribute;
  final CoachingDirection direction;
  final CoachingTier tier;
  final double normalizedSeverity;
  final String fallbackPhrase;

  final double confidence;

  final ActionControllability controllability;

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
