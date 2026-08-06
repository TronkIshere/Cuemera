// test/editorial_score/domain/score_calculator_test.dart
import 'package:cuemera/features/editorial_score/domain/score_calculator.dart';
import 'package:cuemera/features/reference_photo/domain/models/reference_profile.dart';
import 'package:cuemera/features/reference_photo/domain/models/tolerance_settings.dart';
import 'package:cuemera/features/scene_analysis/domain/models/scene_profile.dart';
import 'package:cuemera/features/scene_analysis/domain/models/subject_profile.dart';
import 'package:flutter_test/flutter_test.dart';

SubjectProfile _subject({
  double? bodyRatio,
  double? faceAngleDegrees,
  double? shoulderAngleDegrees,
  bool? eyesOpen,
  String? expression,
}) {
  return SubjectProfile(
    bodyRatio: bodyRatio,
    faceAngleDegrees: faceAngleDegrees,
    shoulderAngleDegrees: shoulderAngleDegrees,
    eyesOpen: eyesOpen,
    expression: expression,
    timestamp: DateTime.now(),
  );
}

SceneProfile _scene({
  double brightness = 0.5,
  double negativeSpaceScore = 0.5,
  double symmetryScore = 0.5,
  int backgroundClutterCount = 2,
  double? depthEstimate,
}) {
  return SceneProfile(
    brightness: brightness,
    negativeSpaceScore: negativeSpaceScore,
    symmetryScore: symmetryScore,
    backgroundClutterCount: backgroundClutterCount,
    depthEstimate: depthEstimate,
  );
}

ReferenceProfile _reference({
  String? expression,
  double? overallBrightness,
  int? backgroundClutterCount,
  double? negativeSpaceScore,
  double? symmetryScore,
}) {
  return ReferenceProfile(
    imagePath: '/tmp/reference.jpg',
    expression: expression,
    overallBrightness: overallBrightness,
    backgroundClutterCount: backgroundClutterCount,
    negativeSpaceScore: negativeSpaceScore,
    symmetryScore: symmetryScore,
  );
}

void main() {
  group('story score (P0 fix)', () {
    test('reads the actual depthEstimate value, not a flat constant', () {
      final subject = _subject();
      final reference = _reference();

      final lowDepth = calculateReferenceScore(
        subject,
        _scene(depthEstimate: 0.1),
        reference,
        ToleranceSettings.defaultBalanced,
      );
      final highDepth = calculateReferenceScore(
        subject,
        _scene(depthEstimate: 0.9),
        reference,
        ToleranceSettings.defaultBalanced,
      );

      // The old bug made both of these equal (flat 75). They must now differ
      // and scale with the input.
      expect(lowDepth.breakdown['story'], closeTo(10, 1));
      expect(highDepth.breakdown['story'], closeTo(90, 1));
      expect(
        lowDepth.breakdown['story'],
        isNot(equals(highDepth.breakdown['story'])),
      );
    });

    test('falls back to a neutral 50 when depthEstimate is null', () {
      final result = calculateReferenceScore(
        _subject(),
        _scene(depthEstimate: null),
        _reference(),
        ToleranceSettings.defaultBalanced,
      );
      expect(result.breakdown['story'], 50);
    });

    test(
      'never used the old flat-75 value for a populated mid-range depth',
      () {
        final result = calculateReferenceScore(
          _subject(),
          _scene(depthEstimate: 0.5),
          _reference(),
          ToleranceSettings.defaultBalanced,
        );
        expect(result.breakdown['story'], closeTo(50, 1));
        expect(result.breakdown['story'], isNot(75));
      },
    );
  });

  group('calculateReferenceScore overall', () {
    test('overall is the mean of the five equally-weighted categories', () {
      final result = calculateReferenceScore(
        _subject(expression: 'smiling'),
        _scene(depthEstimate: 1.0, backgroundClutterCount: 0),
        _reference(),
        ToleranceSettings.defaultBalanced,
      );
      final expectedMean =
          result.breakdown.values.reduce((a, b) => a + b) /
          result.breakdown.length;
      expect(result.overall, closeTo(expectedMean, 1));
    });

    test(
      'suggests improving the lowest-scoring category when it is below 60',
      () {
        final result = calculateReferenceScore(
          _subject(eyesOpen: false, expression: 'serious'),
          _scene(depthEstimate: 0.0),
          _reference(expression: 'smiling'),
          ToleranceSettings.defaultBalanced,
        );
        expect(result.nextSuggestion, isNotNull);
        expect(result.nextSuggestion, contains('Improve'));
      },
    );

    test('gives no suggestion when every category scores at or above 60', () {
      final result = calculateReferenceScore(
        _subject(expression: 'smiling'),
        _scene(
          depthEstimate: 0.7,
          backgroundClutterCount: 0,
          negativeSpaceScore: 0.7,
          symmetryScore: 0.7,
        ),
        _reference(),
        ToleranceSettings.defaultBalanced,
      );
      final allAboveThreshold = result.breakdown.values.every(
        (value) => value >= 60,
      );
      expect(
        allAboveThreshold,
        isTrue,
        reason:
            'test fixture should be tuned so every category clears 60: '
            '${result.breakdown}',
      );
      expect(result.nextSuggestion, isNull);
    });
  });

  group('expression score', () {
    test(
      'scores highest when live expression exactly matches the reference',
      () {
        final result = calculateReferenceScore(
          _subject(expression: 'smiling'),
          _scene(),
          _reference(expression: 'smiling'),
          ToleranceSettings.defaultBalanced,
        );
        expect(result.breakdown['expression'], 100);
      },
    );

    test('scores lowest when live expression does not match the reference', () {
      final result = calculateReferenceScore(
        _subject(expression: 'serious'),
        _scene(),
        _reference(expression: 'smiling'),
        ToleranceSettings.defaultBalanced,
      );
      expect(result.breakdown['expression'], lessThan(100));
    });

    test(
      'falls back to a heuristic ladder when the reference has no expression',
      () {
        final result = calculateReferenceScore(
          _subject(expression: 'smiling'),
          _scene(),
          _reference(expression: null),
          ToleranceSettings.defaultBalanced,
        );
        expect(result.breakdown['expression'], 90);
      },
    );
  });

  group('EditorialScore persistence round-trip', () {
    test('toMap/fromMap preserves overall, breakdown, and nextSuggestion', () {
      const original = EditorialScore(
        overall: 72,
        breakdown: {'composition': 80, 'lighting': 60},
        nextSuggestion: 'Improve lighting',
      );
      final restored = EditorialScore.fromMap(original.toMap());

      expect(restored.overall, original.overall);
      expect(restored.breakdown, original.breakdown);
      expect(restored.nextSuggestion, original.nextSuggestion);
    });

    test('round-trips a null nextSuggestion', () {
      const original = EditorialScore(
        overall: 90,
        breakdown: {'composition': 90},
      );
      final restored = EditorialScore.fromMap(original.toMap());
      expect(restored.nextSuggestion, isNull);
    });
  });
}
