// test/reference_photo/domain/comparison_math_test.dart
import 'package:cuemera/features/reference_photo/domain/comparison_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('deviation', () {
    test('returns absolute difference regardless of sign', () {
      expect(ComparisonMath.deviation(10.0, 4.0), 6.0);
      expect(ComparisonMath.deviation(4.0, 10.0), 6.0);
      expect(ComparisonMath.deviation(-5.0, 5.0), 10.0);
    });

    test('returns zero for identical values', () {
      expect(ComparisonMath.deviation(3.0, 3.0), 0.0);
    });
  });

  group('relativeDeviation', () {
    test('returns null when reference is zero (avoids divide-by-zero)', () {
      expect(ComparisonMath.relativeDeviation(5.0, 0.0), isNull);
    });

    test('computes deviation as a fraction of the reference value', () {
      // subject is 50% larger than reference
      expect(ComparisonMath.relativeDeviation(1.5, 1.0), closeTo(0.5, 1e-9));
    });

    test('is symmetric in sign but not in magnitude', () {
      expect(ComparisonMath.relativeDeviation(0.5, 1.0), closeTo(0.5, 1e-9));
    });
  });

  group('circularDeviation', () {
    test('returns the short way around a wraparound boundary', () {
      // 350 vs 10 degrees on a 360 wraparound should be 20, not 340
      expect(
        ComparisonMath.circularDeviation(350.0, 10.0, 360.0),
        closeTo(20.0, 1e-9),
      );
    });

    test('never exceeds half the wraparound', () {
      final deviation = ComparisonMath.circularDeviation(0.0, 180.0, 360.0);
      expect(deviation, lessThanOrEqualTo(180.0));
    });

    test('returns zero for identical angles', () {
      expect(ComparisonMath.circularDeviation(90.0, 90.0, 360.0), 0.0);
    });
  });

  group('threshold helpers', () {
    test('thresholdForPose scales linearly with poseTolerance', () {
      expect(ComparisonMath.thresholdForPose(0.0), 0.0);
      expect(ComparisonMath.thresholdForPose(1.0), 45.0);
      expect(ComparisonMath.thresholdForPose(0.5), 22.5);
    });

    test('thresholdForPoseRatio scales linearly with poseTolerance', () {
      expect(ComparisonMath.thresholdForPoseRatio(1.0), 0.5);
    });

    test('thresholdForComposition/Expression/Color pass through unscaled', () {
      expect(ComparisonMath.thresholdForComposition(0.3), 0.3);
      expect(ComparisonMath.thresholdForExpression(0.7), 0.7);
      expect(ComparisonMath.thresholdForColor(0.4), 0.4);
    });

    test('thresholdForHue scales by the 180-degree max deviation', () {
      expect(ComparisonMath.thresholdForHue(0.5), 90.0);
    });
  });

  group('normalizedSeverity', () {
    test('clamps to [0, 1] even when deviation exceeds maxDeviation', () {
      expect(ComparisonMath.normalizedSeverity(200.0, 90.0), 1.0);
    });

    test('returns proportional value within range', () {
      expect(ComparisonMath.normalizedSeverity(45.0, 90.0), 0.5);
    });

    test('returns zero for zero deviation', () {
      expect(ComparisonMath.normalizedSeverity(0.0, 90.0), 0.0);
    });
  });

  group('exceedsThreshold', () {
    test(
      'is false when deviation equals the threshold (not strictly greater)',
      () {
        expect(ComparisonMath.exceedsThreshold(5.0, 5.0), isFalse);
      },
    );

    test('is true only when deviation is strictly greater than threshold', () {
      expect(ComparisonMath.exceedsThreshold(5.1, 5.0), isTrue);
      expect(ComparisonMath.exceedsThreshold(4.9, 5.0), isFalse);
    });
  });

  group('similarity', () {
    test('returns 1.0 when deviation is within threshold', () {
      expect(ComparisonMath.similarity(2.0, 5.0, 10.0), 1.0);
      expect(ComparisonMath.similarity(5.0, 5.0, 10.0), 1.0); // boundary
    });

    test('returns 0.0 once deviation reaches maxDeviation', () {
      expect(ComparisonMath.similarity(10.0, 5.0, 10.0), 0.0);
    });

    test('linearly interpolates between threshold and maxDeviation', () {
      // halfway between threshold (5) and maxDeviation (10) -> 0.5
      expect(ComparisonMath.similarity(7.5, 5.0, 10.0), closeTo(0.5, 1e-9));
    });

    test('returns 0.0 when maxDeviation <= threshold (degenerate range)', () {
      expect(ComparisonMath.similarity(6.0, 5.0, 5.0), 0.0);
    });
  });

  group('boundingBoxAspectRatio', () {
    test('returns null for null or empty point lists', () {
      expect(ComparisonMath.boundingBoxAspectRatio(null), isNull);
      expect(ComparisonMath.boundingBoxAspectRatio(const []), isNull);
    });

    test('returns null when the bounding box has zero width', () {
      final points = [const Offset(5, 0), const Offset(5, 10)];
      expect(ComparisonMath.boundingBoxAspectRatio(points), isNull);
    });

    test('computes height/width of the bounding box', () {
      final points = [
        const Offset(0, 0),
        const Offset(10, 0),
        const Offset(10, 20),
        const Offset(0, 20),
      ];
      // width = 10, height = 20 -> ratio = 2.0
      expect(ComparisonMath.boundingBoxAspectRatio(points), closeTo(2.0, 1e-9));
    });
  });
}
