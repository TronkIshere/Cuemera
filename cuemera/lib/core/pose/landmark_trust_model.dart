// core/pose/landmark_trust_model.dart

import '../confidence/confidence.dart';

enum LandmarkTrustState { trusted, uncertain, invalid, occluded, unstable }

enum LandmarkTrustReason {
  belowLikelihoodFloor,
  maskDisagreement,
  geometryImplausible,
  temporallyHeld,
  temporallyUnstable,
}

class TrustedLandmark {
  const TrustedLandmark({
    required this.x,
    required this.y,
    required this.z,
    required this.state,
    required this.confidence,
    this.reasons = const [],
  });

  final double x;
  final double y;
  final double z;

  final LandmarkTrustState state;

  final Confidence confidence;

  final List<LandmarkTrustReason> reasons;

  bool get isUsable =>
      state == LandmarkTrustState.trusted ||
      state == LandmarkTrustState.uncertain;

  factory TrustedLandmark.classify({
    required double x,
    required double y,
    required double z,
    required double likelihood,
    double likelihoodFloor = 0.6,
    double? maskConfidence,
    bool geometrySuspect = false,
  }) {
    if (!x.isFinite || !y.isFinite) {
      return const TrustedLandmark(
        x: 0,
        y: 0,
        z: 0,
        state: LandmarkTrustState.invalid,
        confidence: Confidence.zero,
        reasons: [LandmarkTrustReason.geometryImplausible],
      );
    }

    final reasons = <LandmarkTrustReason>[];
    final components = <Confidence>[Confidence(likelihood.clamp(0.0, 1.0))];
    if (likelihood < likelihoodFloor) {
      reasons.add(LandmarkTrustReason.belowLikelihoodFloor);
    }

    if (maskConfidence != null) {
      components.add(Confidence(maskConfidence.clamp(0.0, 1.0)));
      if (maskConfidence < 0.1) {
        reasons.add(LandmarkTrustReason.maskDisagreement);
      }
    }

    if (geometrySuspect) reasons.add(LandmarkTrustReason.geometryImplausible);

    final combined = Confidence.productOf(components);

    final LandmarkTrustState state;
    if (likelihood < likelihoodFloor ||
        (maskConfidence != null && maskConfidence < 0.1)) {
      state = LandmarkTrustState.invalid;
    } else if (geometrySuspect ||
        (maskConfidence != null && maskConfidence < 0.5)) {
      state = LandmarkTrustState.uncertain;
    } else {
      state = LandmarkTrustState.trusted;
    }

    return TrustedLandmark(
      x: x,
      y: y,
      z: z,
      state: state,
      confidence: combined,
      reasons: reasons,
    );
  }

  TrustedLandmark withTemporalVerdict({
    required bool isEligible,
    required double temporalConfidence,
  }) {
    if (state == LandmarkTrustState.invalid) return this;

    if (isEligible) {
      return TrustedLandmark(
        x: x,
        y: y,
        z: z,
        state: state,
        confidence: Confidence.productOf([
          confidence,
          Confidence(temporalConfidence.clamp(0.0, 1.0)),
        ]),
        reasons: reasons,
      );
    }

    if (temporalConfidence > 0) {
      return TrustedLandmark(
        x: x,
        y: y,
        z: z,
        state: LandmarkTrustState.occluded,
        confidence: Confidence.productOf([
          confidence,
          Confidence(temporalConfidence.clamp(0.0, 1.0)),
        ]),
        reasons: [...reasons, LandmarkTrustReason.temporallyHeld],
      );
    }

    return TrustedLandmark(
      x: x,
      y: y,
      z: z,
      state: LandmarkTrustState.unstable,
      confidence: Confidence.zero,
      reasons: [...reasons, LandmarkTrustReason.temporallyUnstable],
    );
  }

  String debugLine(String name) =>
      'POSE: landmark=$name state=${state.name} '
      'confidence=${confidence.value.toStringAsFixed(2)}'
      '${reasons.isEmpty ? '' : ' reasons=${reasons.map((r) => r.name).join(",")}'}';
}
