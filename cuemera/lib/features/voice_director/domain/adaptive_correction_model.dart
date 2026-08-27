// features/voice_director/domain/adaptive_correction_model.dart
//
// W7 in the audit: the system gives the same wording intensity to a subject
// who overshoots every instruction as to one who barely moves. This is the
// simplest model that could plausibly work — a per-attribute exponential
// moving average of "how far did they actually move per unit of instructed
// intensity" — deliberately not a bigger model, not cloud AI, fully local
// and session-scoped, per the constraints your prompt states explicitly.
//
// It only ever selects which pre-authored phrase tier
// (mild/moderate/strong, already authored in reference_comparison_engine.dart
// today) to use for the *next* instruction on the same attribute — it never
// invents new wording, so it introduces no new hallucination surface.

import 'package:cuemera/features/reference_photo/domain/comparison_math.dart';
import 'package:cuemera/features/voice_director/domain/correction_feedback.dart';
import 'package:cuemera/features/voice_director/models/coaching_decision.dart';

enum IntensityAdjustment { asAuthored, soften, strengthen }

class _AttributeGain {
  _AttributeGain(this.gain, this.sampleCount);
  double gain;
  int sampleCount;
}

class ResponsivenessModel {
  ResponsivenessModel({
    this.overshootThreshold = 1.3,
    this.undershootThreshold = 0.7,
    this.emaWeight = 0.3,
    this.minSamplesBeforeAdjusting = 2,
  });

  final double overshootThreshold;
  final double undershootThreshold;
  final double emaWeight;
  final int minSamplesBeforeAdjusting;

  final Map<CoachingAttribute, _AttributeGain> _gains = {};

  static double _intensityUnits(CoachingSeverityBand band) {
    switch (band) {
      case CoachingSeverityBand.mild:
        return 1.0;
      case CoachingSeverityBand.moderate:
        return 2.0;
      case CoachingSeverityBand.strong:
        return 3.0;
    }
  }

  void recordOutcome(
    CorrectionRecord record,
    CoachingSeverityBand instructedBand,
  ) {
    if (record.outcome == null ||
        record.outcome == CorrectionOutcome.unmeasurable)
      return;
    if (record.postMeasurement == null) return;

    final actualMovement = kCircularAttributes.contains(record.attribute)
        ? ComparisonMath.circularDeviation(
            record.postMeasurement!,
            record.preMeasurement,
            360.0,
          )
        : (record.postMeasurement! - record.preMeasurement).abs();
    final instructedUnits = _intensityUnits(instructedBand);
    if (instructedUnits == 0) return;
    final observedGain = actualMovement / instructedUnits;

    final existing = _gains[record.attribute];
    if (existing == null) {
      _gains[record.attribute] = _AttributeGain(observedGain, 1);
    } else {
      existing.gain =
          existing.gain * (1 - emaWeight) + observedGain * emaWeight;
      existing.sampleCount += 1;
    }
  }

  IntensityAdjustment adjustmentFor(CoachingAttribute attribute) {
    final entry = _gains[attribute];
    if (entry == null || entry.sampleCount < minSamplesBeforeAdjusting) {
      return IntensityAdjustment.asAuthored;
    }
    if (entry.gain > overshootThreshold) return IntensityAdjustment.soften;
    if (entry.gain < undershootThreshold) return IntensityAdjustment.strengthen;
    return IntensityAdjustment.asAuthored;
  }

  CoachingSeverityBand adjustedBand(
    CoachingAttribute attribute,
    CoachingSeverityBand authored,
  ) {
    final adjustment = adjustmentFor(attribute);
    const order = [
      CoachingSeverityBand.mild,
      CoachingSeverityBand.moderate,
      CoachingSeverityBand.strong,
    ];
    final index = order.indexOf(authored);

    switch (adjustment) {
      case IntensityAdjustment.soften:
        return order[(index - 1).clamp(0, order.length - 1)];
      case IntensityAdjustment.strengthen:
        return order[(index + 1).clamp(0, order.length - 1)];
      case IntensityAdjustment.asAuthored:
        return authored;
    }
  }

  void resetSession() => _gains.clear();
}
