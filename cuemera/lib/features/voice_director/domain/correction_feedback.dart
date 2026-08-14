// features/voice_director/domain/correction_feedback.dart

import 'package:cuemera/features/voice_director/models/coaching_decision.dart';

enum CorrectionOutcome { improved, overshot, reversed, unchanged, unmeasurable }

class CorrectionRecord {
  CorrectionRecord({
    required this.attribute,
    required this.preMeasurement,
    required this.referenceTarget,
    required this.expectedDirection,
    required this.instructedAt,
    this.noiseFloor = 0.5,
  });

  final CoachingAttribute attribute;
  final double preMeasurement;
  final double? referenceTarget;
  final CoachingDirection expectedDirection;
  final DateTime instructedAt;

  final double noiseFloor;

  double? postMeasurement;
  DateTime? reobservedAt;
  CorrectionOutcome? outcome;

  bool get isClosed => outcome != null;

  void close({
    required double? measuredValue,
    required bool measurementConfident,
  }) {
    if (measuredValue == null || !measurementConfident) {
      outcome = CorrectionOutcome.unmeasurable;
      return;
    }
    postMeasurement = measuredValue;
    reobservedAt = DateTime.now();
    outcome = _classify();
  }

  CorrectionOutcome _classify() {
    final movement = postMeasurement! - preMeasurement;
    if (movement.abs() < noiseFloor) return CorrectionOutcome.unchanged;

    final target = referenceTarget;
    if (target == null) {
      if (expectedDirection == CoachingDirection.none)
        return CorrectionOutcome.improved;
      final expectedSign = _directionSign(expectedDirection);
      final movedExpectedWay =
          expectedSign == 0 || movement.sign == expectedSign;
      return movedExpectedWay
          ? CorrectionOutcome.improved
          : CorrectionOutcome.reversed;
    }

    final preDist = (preMeasurement - target).abs();
    final postDist = (postMeasurement! - target).abs();
    final preSide = (preMeasurement - target).sign;
    final postSide = (postMeasurement! - target).sign;
    final crossedTarget = preSide != 0 && postSide != 0 && preSide != postSide;

    if (crossedTarget) {
      return postDist > noiseFloor * 2
          ? CorrectionOutcome.overshot
          : CorrectionOutcome.improved;
    }
    if (postDist < preDist) return CorrectionOutcome.improved;
    return CorrectionOutcome.reversed;
  }

  double _directionSign(CoachingDirection direction) {
    switch (direction) {
      case CoachingDirection.increase:
      case CoachingDirection.right:
        return 1.0;
      case CoachingDirection.decrease:
      case CoachingDirection.left:
        return -1.0;
      case CoachingDirection.none:
        return 0.0;
    }
  }

  String debugLine() =>
      'RESULT: attribute=${attribute.name} before=${preMeasurement.toStringAsFixed(2)} '
      'after=${postMeasurement?.toStringAsFixed(2) ?? 'n/a'} '
      'improved=${outcome == CorrectionOutcome.improved}';
}
