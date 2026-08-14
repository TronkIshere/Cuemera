// core/confidence/confidence.dart
//
// The single mechanism the audit's §11 hangs everything else off: a
// confidence value that only ever narrows (never gets invented) as it moves
// from landmark -> metric -> reference -> decision -> coaching eligibility
// -> LLM-generation permission. Every combination rule here is deliberately
// `min` or multiplicative, never an average — an average lets one
// untrustworthy input hide behind several trustworthy ones, which is the
// opposite of "prefer silence over a confident wrong instruction."

class Confidence {
  const Confidence(this.value) : assert(value >= 0.0 && value <= 1.0);

  final double value;

  static const Confidence zero = Confidence(0.0);
  static const Confidence certain = Confidence(1.0);

  /// A metric is only as trustworthy as its least-trustworthy input landmark
  /// — matches core/pose/landmark_trust_model.dart's per-landmark confidence
  /// and is the combination rule for "metricConfidence" in the audit's §11.
  static Confidence minOf(Iterable<Confidence> inputs) {
    if (inputs.isEmpty) return zero;
    var lowest = 1.0;
    for (final c in inputs) {
      if (c.value < lowest) lowest = c.value;
    }
    return Confidence(lowest);
  }

  /// A landmark's confidence is the product of its independent signal
  /// components (likelihood, geometry, mask) — one bad signal pulls the
  /// whole score down hard rather than being averaged away. Kept here as a
  /// general-purpose helper; landmark_trust_model.dart's TrustedLandmark
  /// uses the same rule directly against its own named fields for clarity
  /// at that call site.
  static Confidence productOf(Iterable<Confidence> components) {
    if (components.isEmpty) return zero;
    var product = 1.0;
    for (final c in components) {
      product *= c.value;
    }
    return Confidence(product.clamp(0.0, 1.0));
  }

  /// decisionConfidence = min(subject metric confidence, reference field
  /// confidence) — a decision can never be more confident than the weaker
  /// of the two things it's comparing.
  static Confidence decisionConfidence(
    Confidence subject,
    Confidence reference,
  ) => minOf([subject, reference]);

  bool meetsFloor(double floor) => value >= floor;

  Confidence combinedWith(Confidence other, {bool multiplicative = false}) =>
      multiplicative ? productOf([this, other]) : minOf([this, other]);

  @override
  String toString() => value.toStringAsFixed(2);
}

/// Named floors used by coaching_eligibility.dart and llm gating — kept in
/// one place so tuning is a one-line change, not a grep across files.
class ConfidenceFloors {
  ConfidenceFloors._();

  /// Below this, coaching_eligibility.dart returns DO_NOT_COACH.
  static const double eligibleToSpeak = 0.5;

  /// Below this (but above eligibleToSpeak), a decision is spoken but is
  /// barred from LLM paraphrase and must use decision.fallbackPhrase
  /// verbatim — see the audit's §11 "LLM-generation permission" rule.
  static const double eligibleForLlmParaphrase = 0.7;

  /// Below this, a whole ReferenceProfile is flagged as low-confidence at
  /// pick time (see reference_image_analyzer.dart's plan in §19).
  static const double referenceUsable = 0.4;
}
