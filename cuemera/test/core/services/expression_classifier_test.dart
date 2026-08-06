// test/core/services/expression_classifier_test.dart
import 'package:cuemera/core/services/expression_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('classifyExpression — null handling', () {
    test('returns null when smilingProbability is null', () {
      expect(
        classifyExpression(
          smilingProbability: null,
          leftEyeOpenProbability: 0.9,
          rightEyeOpenProbability: 0.9,
        ),
        isNull,
      );
    });

    test('falls back to the smile-only ladder when both eyes are null', () {
      expect(
        classifyExpression(
          smilingProbability: 0.9,
          leftEyeOpenProbability: null,
          rightEyeOpenProbability: null,
        ),
        'big_smile',
      );
    });
  });

  group('classifyExpression — wink detection', () {
    test('detects a wink when the left eye is open and the right is not', () {
      // smilingProbability alone would say 'smiling' (0.7 > 0.6) — wink
      // must take priority over the smile ladder.
      expect(
        classifyExpression(
          smilingProbability: 0.7,
          leftEyeOpenProbability: 0.9,
          rightEyeOpenProbability: 0.1,
        ),
        'wink',
      );
    });

    test('detects a wink when the right eye is open and the left is not', () {
      expect(
        classifyExpression(
          smilingProbability: 0.7,
          leftEyeOpenProbability: 0.2,
          rightEyeOpenProbability: 0.8,
        ),
        'wink',
      );
    });

    test('does not fire when both eyes are on the same side of 0.5', () {
      final bothOpen = classifyExpression(
        smilingProbability: 0.9,
        leftEyeOpenProbability: 0.9,
        rightEyeOpenProbability: 0.8,
      );
      final bothClosed = classifyExpression(
        smilingProbability: 0.9,
        leftEyeOpenProbability: 0.3,
        rightEyeOpenProbability: 0.4,
      );

      expect(bothOpen, isNot('wink'));
      expect(bothClosed, isNot('wink'));
    });
  });

  group('classifyExpression — eyes-closed detection', () {
    test(
      'returns eyes_closed when average eye-open is low and not smiling',
      () {
        expect(
          classifyExpression(
            smilingProbability: 0.2,
            leftEyeOpenProbability: 0.1,
            rightEyeOpenProbability: 0.1,
          ),
          'eyes_closed',
        );
      },
    );

    test(
      'returns laughing_eyes_closed when average eye-open is low and smiling',
      () {
        expect(
          classifyExpression(
            smilingProbability: 0.9,
            leftEyeOpenProbability: 0.1,
            rightEyeOpenProbability: 0.1,
          ),
          'laughing_eyes_closed',
        );
      },
    );

    test('averages from a single eye when the other is null', () {
      expect(
        classifyExpression(
          smilingProbability: 0.2,
          leftEyeOpenProbability: 0.1,
          rightEyeOpenProbability: null,
        ),
        'eyes_closed',
      );
    });
  });

  group('classifyExpression — smile ladder boundaries', () {
    // classifyExpression's leftEyeOpenProbability/rightEyeOpenProbability
    // are `required` even though their type is nullable — every call must
    // pass them explicitly (null is fine as the value, omitting the
    // argument is not). This helper does that for the boundary tests
    // below, which only care about smilingProbability.
    String? smileOnly(double smiling) {
      return classifyExpression(
        smilingProbability: smiling,
        leftEyeOpenProbability: null,
        rightEyeOpenProbability: null,
      );
    }

    // All comparisons in the classifier are strict (>), so a value exactly
    // at a boundary falls into the *lower* tier, not the upper one.
    test('0.86 is big_smile, 0.85 exactly is not', () {
      expect(smileOnly(0.86), 'big_smile');
      expect(smileOnly(0.85), 'smiling');
    });

    test('0.61 is smiling, 0.6 exactly is not', () {
      expect(smileOnly(0.61), 'smiling');
      expect(smileOnly(0.6), 'slight_smile');
    });

    test('0.36 is slight_smile, 0.35 exactly is not', () {
      expect(smileOnly(0.36), 'slight_smile');
      expect(smileOnly(0.35), 'neutral');
    });

    test('0.16 is neutral, 0.15 exactly is not', () {
      expect(smileOnly(0.16), 'neutral');
      expect(smileOnly(0.15), 'serious');
    });

    test('0.0 is serious', () {
      expect(smileOnly(0.0), 'serious');
    });
  });
}
