// features/voice_director/domain/models/coaching_decision.dart

/// Which underlying signal a coaching decision is about. Mirrors the 13
/// `_evaluate*` methods in `ReferenceComparisonEngine`.
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
}

/// Which direction the subject needs to move in, for attributes that have
/// a safe two-sided phrasing. `bodyRatio`, `symmetry`, and `hue` are
/// single-direction by design (see `LIMITATIONS_AND_ROADMAP.md`/
/// `FILE_REFERENCE.md` — no safe way to derive a direction from the
/// available math) and always report `none`; so does `expression`, which
/// uses `targetExpression` instead.
enum CoachingDirection { increase, decrease, left, right, none }

/// Which priority tier the decision came from — mirrors
/// `ReferenceComparisonEngine.evaluate()`'s three-tier fallthrough
/// (Pose & Face -> Composition -> Lighting/Color).
enum CoachingTier { poseAndFace, composition, lighting }

enum CoachingSeverityBand { mild, moderate, strong }

/// The reliable, rule-based output of `ComparisonMath`/
/// `ReferenceComparisonEngine`'s attribute/severity selection, decoupled
/// from the phrase text itself.
///
/// `fallbackPhrase` is today's exact hand-authored string — used verbatim
/// while there's no AI phrase generation yet (Phase 0/1), and again
/// whenever generation is slow, unavailable, or unsupported once Phase 2
/// wires a model into the live path. Everything else here is what a
/// future phrase-generation step would need to build natural-language
/// text instead of picking from the fixed phrase bank.
class CoachingDecision {
  const CoachingDecision({
    required this.attribute,
    required this.direction,
    required this.tier,
    required this.normalizedSeverity,
    required this.fallbackPhrase,
    this.targetExpression,
  });

  /// Severity-band boundaries. Single source of truth, shared with
  /// `ReferenceComparisonEngine`'s `_tieredPhrase`, so `severityBand` (and
  /// therefore `dedupeKey`) always agrees with which tiered phrase
  /// (mild/moderate/strong) was actually picked.
  static const double mildSeverityCeiling = 0.4;
  static const double moderateSeverityCeiling = 0.75;

  final CoachingAttribute attribute;
  final CoachingDirection direction;
  final CoachingTier tier;
  final double normalizedSeverity;
  final String fallbackPhrase;

  /// Only set for [CoachingAttribute.expression] — the reference's target
  /// expression label (e.g. `'smiling'`). Null for every other attribute.
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

  /// Identity used to de-duplicate repeated coaching prompts. Based on
  /// *what* the decision is (attribute + direction + severity band, or
  /// attribute + target expression) rather than the phrase text — so once
  /// Phase 2 generates variable phrasing for the same decision, dedupe
  /// keeps working correctly instead of re-speaking every time the wording
  /// happens to change.
  ///
  /// Today, phrase text is a deterministic function of exactly these same
  /// inputs (see `_tieredPhrase`/`_evaluateExpression`), so switching
  /// dedupe from phrase-string-equality to this key is behavior-identical
  /// right now — see `voice_providers.dart`.
  String get dedupeKey {
    if (attribute == CoachingAttribute.expression) {
      return '${attribute.name}:${targetExpression ?? ''}';
    }
    return '${attribute.name}:${direction.name}:${severityBand.name}';
  }
}
