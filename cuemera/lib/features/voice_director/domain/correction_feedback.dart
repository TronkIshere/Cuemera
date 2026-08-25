// features/voice_director/domain/correction_feedback.dart

import 'package:cuemera/features/reference_photo/domain/comparison_math.dart';
import 'package:cuemera/features/voice_director/models/coaching_decision.dart';

enum CorrectionOutcome { improved, overshot, reversed, unchanged, unmeasurable }

const Set<CoachingAttribute> kCircularAttributes = {
  CoachingAttribute.shoulderAngle,
  CoachingAttribute.facePitch,
  CoachingAttribute.faceRoll,
  CoachingAttribute.faceYaw,
  CoachingAttribute.bodyYaw,
  CoachingAttribute.hue,
  CoachingAttribute.lightDirection,
};

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
    final circular = kCircularAttributes.contains(attribute);

    final movement = circular
        ? ComparisonMath.signedCircularDiff(
            postMeasurement!,
            preMeasurement,
            360.0,
          )
        : postMeasurement! - preMeasurement;
    final movementMagnitude = circular
        ? ComparisonMath.circularDeviation(
            postMeasurement!,
            preMeasurement,
            360.0,
          )
        : movement.abs();
    if (movementMagnitude < noiseFloor) return CorrectionOutcome.unchanged;

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

    final preDist = circular
        ? ComparisonMath.circularDeviation(preMeasurement, target, 360.0)
        : (preMeasurement - target).abs();
    final postDist = circular
        ? ComparisonMath.circularDeviation(postMeasurement!, target, 360.0)
        : (postMeasurement! - target).abs();
    final preSide = circular
        ? ComparisonMath.signedCircularDiff(preMeasurement, target, 360.0).sign
        : (preMeasurement - target).sign;
    final postSide = circular
        ? ComparisonMath.signedCircularDiff(
            postMeasurement!,
            target,
            360.0,
          ).sign
        : (postMeasurement! - target).sign;
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
