// core/tracking/temporal_stabilizer.dart
//
// The live camera path currently has no working temporal filtering:
// PoseLandmarkGate's GateHold exists but ships with holdWindow: Duration.zero
// (per FILE_REFERENCE.md), so every frame is coached against as if pose
// detection were noiseless. This file is what should sit between per-frame
// metric extraction and CoachingDecision construction on the LIVE path only
// — never the reference-photo path, which analyzes one still image and has
// no "time" to stabilize over.
//
// Deliberately generic and dependency-free so it's unit-testable without a
// device (see the audit's §22 test list: jitter, step-change, wraparound,
// hysteresis, and recovery-after-loss fixtures all exercise this file
// directly, with no ML Kit types involved).

import 'dart:math' as math;

/// Output of one stabilizer update: the value a coaching decision should
/// actually be built from, plus how much to trust it *as a stable reading*
/// (independent of the landmark-level confidence in landmark_trust_model.dart
/// — this is "how sure are we this isn't just jitter," not "how sure are we
/// the landmark is correct").
class StabilizedMetric {
  const StabilizedMetric({
    required this.value,
    required this.temporalConfidence,
    required this.isEligible,
    required this.direction,
  });

  /// The smoothed value to use for comparison/coaching math.
  final double value;

  /// In [0, 1]. Low while a value has just changed and hasn't yet persisted
  /// long enough to trust, or while it's oscillating; high once settled.
  final double temporalConfidence;

  /// False until the minimum-persistence window has elapsed for the current
  /// value — i.e. "this has been true for long enough to say something
  /// about it," which is the concrete mechanism that stops the
  /// "Turn left... 100ms later... Turn right" scenario your prompt names:
  /// a value has to survive this window before it's allowed to participate
  /// in a coaching decision at all, regardless of how large the deviation
  /// looks on a single frame.
  final bool isEligible;

  /// -1, 0, or +1 relative to the stabilizer's reference/target — already
  /// hysteresis-adjusted (see StabilizerConfig.hysteresisMargin). Use this,
  /// not a raw `value > target` comparison, to decide CoachingDirection.
  final int direction;
}

class StabilizerConfig {
  const StabilizerConfig({
    this.smoothingWindow = const Duration(milliseconds: 350),
    this.minPersistence = const Duration(milliseconds: 250),
    this.hysteresisMargin = 0.15,
    this.cooldownAfterReport = const Duration(milliseconds: 800),
    this.holdWindowOnLoss = const Duration(milliseconds: 500),
    this.jitterNoiseFloor = 0.02,
  });

  /// Exponential-smoothing time constant. Kept short deliberately — your
  /// prompt explicitly warns against introducing latency that makes live
  /// coaching feel slow; a few hundred milliseconds is enough to reject
  /// single-frame jitter without making a real, sustained pose change feel
  /// laggy.
  final Duration smoothingWindow;

  /// How long a value must persist (post-smoothing) before it's eligible to
  /// drive a coaching decision.
  final Duration minPersistence;

  /// Schmitt-trigger-style margin, as a fraction of the threshold distance,
  /// a value must cross *beyond* the reporting boundary before the reported
  /// direction is allowed to flip. Prevents a value sitting right at the
  /// threshold from flip-flopping the spoken direction every frame.
  final double hysteresisMargin;

  /// After a value is reported (i.e. consumed into a spoken decision), how
  /// long before this same attribute is eligible to report again — the
  /// state-machine-level cooldown lives in coaching_state_machine.dart, but
  /// this floor exists at the signal level too so a rapid re-oscillation
  /// can't route around the state machine's cooldown by presenting as a
  /// "new" value the instant the old one is consumed.
  final Duration cooldownAfterReport;

  /// How long to hold the last known good value when the raw signal goes
  /// missing (occlusion, brief detector miss) before treating the metric as
  /// genuinely unavailable rather than temporarily occluded.
  final Duration holdWindowOnLoss;

  /// Deviations smaller than this, frame to frame, are treated as sensor
  /// noise rather than real motion, for the purposes of temporalConfidence
  /// only (does not affect the smoothed value itself).
  final double jitterNoiseFloor;
}

class _Sample {
  const _Sample(this.value, this.at);
  final double value;
  final DateTime at;
}

/// Linear metrics (ratios, ranges without wraparound: bodyRatio,
/// shoulderBalanceRatio, shoulderSpanRatio, mouthOpenRatio, eyeOpenRatio).
/// For angle-like quantities that wrap at ±180°, use CircularStabilizer
/// below instead — do not use this class directly on shoulderAngleDegrees,
/// faceAngleXDegrees, faceAngleZDegrees, or bodyYawEstimate.
class TemporalStabilizer {
  TemporalStabilizer([this.config = const StabilizerConfig()]);

  final StabilizerConfig config;

  double? _smoothed;
  DateTime? _lastChangeStart;
  double? _valueAtChangeStart;
  DateTime? _lastSampleAt;
  DateTime? _missingSince;
  int _lastReportedDirection = 0;
  DateTime? _lastReportedAt;

  /// Feed one new raw reading (or null if the metric was unavailable this
  /// frame — e.g. the underlying landmark dropped below trust this frame).
  /// [target] is the reference value being coached toward, used only to
  /// compute [StabilizedMetric.direction] with hysteresis; pass null if this
  /// metric isn't being compared directionally right now.
  StabilizedMetric update(double? raw, DateTime now, {double? target}) {
    if (raw == null) {
      _missingSince ??= now;
      final heldLongEnough =
          now.difference(_missingSince!) <= config.holdWindowOnLoss;
      if (heldLongEnough && _smoothed != null) {
        // Occlusion bridging: report the last known good value, but at
        // reduced confidence, and never as newly-eligible — an occluded
        // reading should not be able to trigger a *new* instruction, only
        // let an already-eligible one continue briefly through a blip.
        return StabilizedMetric(
          value: _smoothed!,
          temporalConfidence: 0.3,
          isEligible: false,
          direction: _directionFor(_smoothed!, target),
        );
      }
      // Held past the window without recovering — genuinely unavailable.
      _reset();
      return const StabilizedMetric(
        value: 0,
        temporalConfidence: 0,
        isEligible: false,
        direction: 0,
      );
    }
    _missingSince = null;

    final dt = _lastSampleAt == null
        ? Duration.zero
        : now.difference(_lastSampleAt!);
    _lastSampleAt = now;

    final alpha = _smoothingAlpha(dt);
    final previousSmoothed = _smoothed;
    _smoothed = previousSmoothed == null
        ? raw
        : previousSmoothed + alpha * (raw - previousSmoothed);

    final rawJitter = previousSmoothed == null
        ? 0.0
        : (raw - previousSmoothed).abs();
    final jitterConfidence = rawJitter <= config.jitterNoiseFloor
        ? 1.0
        : (1.0 -
                  ((rawJitter - config.jitterNoiseFloor) /
                      (config.jitterNoiseFloor * 4)))
              .clamp(0.0, 1.0);

    // Minimum-persistence: track how long the *smoothed* value has sat
    // within a small band of its current level; only report eligible once
    // that band has held for minPersistence.
    if (_valueAtChangeStart == null ||
        (_smoothed! - _valueAtChangeStart!).abs() >
            config.jitterNoiseFloor * 3) {
      _valueAtChangeStart = _smoothed;
      _lastChangeStart = now;
    }
    final persistedFor = _lastChangeStart == null
        ? Duration.zero
        : now.difference(_lastChangeStart!);
    final persistenceEligible = persistedFor >= config.minPersistence;

    final cooldownActive =
        _lastReportedAt != null &&
        now.difference(_lastReportedAt!) < config.cooldownAfterReport;

    final direction = _directionFor(_smoothed!, target);

    return StabilizedMetric(
      value: _smoothed!,
      temporalConfidence: jitterConfidence,
      isEligible: persistenceEligible && !cooldownActive,
      direction: direction,
    );
  }

  /// Call once a StabilizedMetric from this instance has actually been
  /// consumed into a spoken CoachingDecision, to start the cooldown window.
  void markReported(DateTime now) => _lastReportedAt = now;

  int _directionFor(double value, double? target) {
    if (target == null) return 0;
    final diff = value - target;
    final margin =
        config.hysteresisMargin * (target.abs() < 1e-6 ? 1.0 : target.abs());
    final boundary = _lastReportedDirection == 0
        ? 0.0
        : (_lastReportedDirection > 0 ? -margin : margin);
    final effectiveDiff = diff + boundary;
    final newDirection = effectiveDiff.abs() < 1e-9
        ? 0
        : (effectiveDiff > 0 ? 1 : -1);
    if (newDirection != 0) _lastReportedDirection = newDirection;
    return newDirection;
  }

  double _smoothingAlpha(Duration dt) {
    if (dt == Duration.zero) return 1.0;
    final tau = config.smoothingWindow.inMilliseconds.toDouble().clamp(
      1.0,
      double.infinity,
    );
    final dtMs = dt.inMilliseconds.toDouble();
    return (1.0 - math.exp(-dtMs / tau)).clamp(0.0, 1.0);
  }

  void _reset() {
    _smoothed = null;
    _lastChangeStart = null;
    _valueAtChangeStart = null;
    _missingSince = null;
    _lastReportedDirection = 0;
  }
}

/// Specialization for angle-like quantities that wrap at ±180°
/// (shoulderAngleDegrees, faceAngleXDegrees, faceAngleZDegrees,
/// bodyYawEstimate). Reuses the same wraparound-aware approach already
/// proven twice in this codebase (ComparisonMath.circularDeviation, applied
/// to fix the same bug class in both reference_comparison_engine.dart and
/// tracking_engine.dart's trackingProgress()) — but applied to *smoothing*,
/// which is a third place the same bug class can hide (see the audit's
/// tracking_engine.dart hypothesis in §19) and is not yet known to be fixed
/// there.
///
/// The core trick: average by converting to a unit vector (cos, sin) and
/// smoothing the vector components independently, then converting back with
/// atan2 — this is mathematically the correct way to smooth a circular
/// quantity and avoids the ±179°/-179° → 0° failure mode a naive linear
/// average produces.
class CircularStabilizer {
  CircularStabilizer([this.config = const StabilizerConfig()]);

  final StabilizerConfig config;

  double? _smoothedCos;
  double? _smoothedSin;
  DateTime? _lastSampleAt;
  DateTime? _lastChangeStart;
  double? _angleAtChangeStart;
  DateTime? _missingSince;
  int _lastReportedDirection = 0;
  DateTime? _lastReportedAt;

  StabilizedMetric update(
    double? rawDegrees,
    DateTime now, {
    double? targetDegrees,
  }) {
    if (rawDegrees == null) {
      _missingSince ??= now;
      final heldLongEnough =
          now.difference(_missingSince!) <= config.holdWindowOnLoss;
      if (heldLongEnough && _smoothedCos != null) {
        final smoothedAngle = _currentAngle()!;
        return StabilizedMetric(
          value: smoothedAngle,
          temporalConfidence: 0.3,
          isEligible: false,
          direction: _directionFor(smoothedAngle, targetDegrees),
        );
      }
      _reset();
      return const StabilizedMetric(
        value: 0,
        temporalConfidence: 0,
        isEligible: false,
        direction: 0,
      );
    }
    _missingSince = null;

    final dt = _lastSampleAt == null
        ? Duration.zero
        : now.difference(_lastSampleAt!);
    _lastSampleAt = now;
    final alpha = _alpha(dt);

    final rad = rawDegrees * math.pi / 180.0;
    final rawCos = math.cos(rad);
    final rawSin = math.sin(rad);

    final previousAngle = _currentAngle();
    _smoothedCos = _smoothedCos == null
        ? rawCos
        : _smoothedCos! + alpha * (rawCos - _smoothedCos!);
    _smoothedSin = _smoothedSin == null
        ? rawSin
        : _smoothedSin! + alpha * (rawSin - _smoothedSin!);

    final smoothedAngle = _currentAngle()!;

    final jitter = previousAngle == null
        ? 0.0
        : _circularDeviation(smoothedAngle, previousAngle);
    final jitterConfidence =
        jitter <=
            config.jitterNoiseFloor *
                100 // degrees, not ratio — wider floor
        ? 1.0
        : (1.0 - ((jitter - config.jitterNoiseFloor * 100) / 20.0)).clamp(
            0.0,
            1.0,
          );

    if (_angleAtChangeStart == null ||
        _circularDeviation(smoothedAngle, _angleAtChangeStart!) > 3.0) {
      _angleAtChangeStart = smoothedAngle;
      _lastChangeStart = now;
    }
    final persistedFor = _lastChangeStart == null
        ? Duration.zero
        : now.difference(_lastChangeStart!);
    final persistenceEligible = persistedFor >= config.minPersistence;
    final cooldownActive =
        _lastReportedAt != null &&
        now.difference(_lastReportedAt!) < config.cooldownAfterReport;

    return StabilizedMetric(
      value: smoothedAngle,
      temporalConfidence: jitterConfidence,
      isEligible: persistenceEligible && !cooldownActive,
      direction: _directionFor(smoothedAngle, targetDegrees),
    );
  }

  void markReported(DateTime now) => _lastReportedAt = now;

  double? _currentAngle() {
    if (_smoothedCos == null || _smoothedSin == null) return null;
    return math.atan2(_smoothedSin!, _smoothedCos!) * 180.0 / math.pi;
  }

  /// Same wraparound math as ComparisonMath.circularDeviation, duplicated
  /// here deliberately rather than imported, so this file stays
  /// dependency-free for unit testing — the two implementations should be
  /// asserted equal by a shared test fixture once wired together for real.
  double _circularDeviation(double a, double b) {
    final diff = (a - b).abs() % 360.0;
    return diff > 180.0 ? 360.0 - diff : diff;
  }

  int _directionFor(double angle, double? target) {
    if (target == null) return 0;
    var diff = (angle - target) % 360.0;
    if (diff > 180.0) diff -= 360.0;
    if (diff < -180.0) diff += 360.0;
    const marginDegrees = 5.0;
    final boundary = _lastReportedDirection == 0
        ? 0.0
        : (_lastReportedDirection > 0 ? -marginDegrees : marginDegrees);
    final effective = diff + boundary;
    final newDirection = effective.abs() < 1e-9 ? 0 : (effective > 0 ? 1 : -1);
    if (newDirection != 0) _lastReportedDirection = newDirection;
    return newDirection;
  }

  double _alpha(Duration dt) {
    if (dt == Duration.zero) return 1.0;
    final tau = config.smoothingWindow.inMilliseconds.toDouble().clamp(
      1.0,
      double.infinity,
    );
    return (1.0 - math.exp(-dt.inMilliseconds.toDouble() / tau)).clamp(
      0.0,
      1.0,
    );
  }

  void _reset() {
    _smoothedCos = null;
    _smoothedSin = null;
    _lastChangeStart = null;
    _angleAtChangeStart = null;
    _missingSince = null;
    _lastReportedDirection = 0;
  }
}
