// test/voice_director/domain/reference_comparison_engine_test.dart
import 'package:cuemera/features/reference_photo/domain/models/reference_profile.dart';
import 'package:cuemera/features/reference_photo/domain/models/tolerance_settings.dart';
import 'package:cuemera/features/scene_analysis/domain/models/scene_profile.dart';
import 'package:cuemera/features/scene_analysis/domain/models/subject_profile.dart';
import 'package:cuemera/features/voice_director/domain/priority_engine.dart';
import 'package:cuemera/features/voice_director/domain/reference_comparison_engine.dart';
import 'package:flutter_test/flutter_test.dart';

SubjectProfile _subject({
  double? bodyRatio,
  double? faceAngleXDegrees,
  double? faceAngleZDegrees,
  double? mouthOpenRatio,
  double? eyeOpenRatio,
  double? shoulderAngleDegrees,
  String? expression,
}) {
  return SubjectProfile(
    bodyRatio: bodyRatio,
    faceAngleXDegrees: faceAngleXDegrees,
    faceAngleZDegrees: faceAngleZDegrees,
    mouthOpenRatio: mouthOpenRatio,
    eyeOpenRatio: eyeOpenRatio,
    shoulderAngleDegrees: shoulderAngleDegrees,
    expression: expression,
    timestamp: DateTime.now(),
  );
}

SceneProfile _scene({
  double brightness = 0.5,
  double negativeSpaceScore = 0.5,
  double symmetryScore = 0.5,
  int backgroundClutterCount = 0,
  double? liveWarmthScore,
  double? liveDominantHue,
}) {
  return SceneProfile(
    brightness: brightness,
    negativeSpaceScore: negativeSpaceScore,
    symmetryScore: symmetryScore,
    backgroundClutterCount: backgroundClutterCount,
    liveWarmthScore: liveWarmthScore,
    liveDominantHue: liveDominantHue,
  );
}

ReferenceProfile _reference({
  double? bodyRatio,
  double? faceAngleXDegrees,
  double? faceAngleZDegrees,
  double? shoulderAngleDegrees,
  String? expression,
  double? mouthOpenRatio,
  double? eyeOpenRatio,
  double? negativeSpaceScore,
  double? symmetryScore,
  int? backgroundClutterCount,
  double? overallBrightness,
  double? warmthScore,
  double? dominantHue,
}) {
  return ReferenceProfile(
    imagePath: 'test.jpg',
    bodyRatio: bodyRatio,
    faceAngleXDegrees: faceAngleXDegrees,
    faceAngleZDegrees: faceAngleZDegrees,
    shoulderAngleDegrees: shoulderAngleDegrees,
    expression: expression,
    mouthOpenRatio: mouthOpenRatio,
    eyeOpenRatio: eyeOpenRatio,
    negativeSpaceScore: negativeSpaceScore,
    symmetryScore: symmetryScore,
    backgroundClutterCount: backgroundClutterCount,
    overallBrightness: overallBrightness,
    warmthScore: warmthScore,
    dominantHue: dominantHue,
  );
}

void main() {
  final engine = ReferenceComparisonEngine();
  const tolerance = ToleranceSettings.defaultBalanced;

  group('evaluate — no signal anywhere', () {
    test('returns null when subject and reference are both empty', () {
      final result = engine.evaluate(
        subject: _subject(),
        scene: _scene(),
        reference: _reference(),
        tolerance: tolerance,
      );

      expect(result, isNull);
    });

    test(
      'returns null when the only populated attribute is missing on one side',
      () {
        // reference has a shoulder angle, but subject doesn't — and
        // nothing else is populated on either side. Should skip quietly,
        // not throw and not fall back to some other attribute.
        final result = engine.evaluate(
          subject: _subject(),
          scene: _scene(),
          reference: _reference(shoulderAngleDegrees: 40.0),
          tolerance: tolerance,
        );

        expect(result, isNull);
      },
    );

    test('returns null when every attribute is within tolerance', () {
      final result = engine.evaluate(
        subject: _subject(shoulderAngleDegrees: 0.0, expression: 'smiling'),
        scene: _scene(),
        reference: _reference(
          shoulderAngleDegrees: 0.0,
          expression: 'smiling',
          negativeSpaceScore: 0.5,
          overallBrightness: 0.5,
        ),
        tolerance: tolerance,
      );

      expect(result, isNull);
    });
  });

  group('evaluate — 3-tier priority fallthrough', () {
    test(
      'falls through to the composition tier when pose/face has no signal',
      () {
        final result = engine.evaluate(
          subject: _subject(), // no pose/face data at all
          scene: _scene(negativeSpaceScore: 0.05),
          reference: _reference(
            negativeSpaceScore: 0.95, // large deviation, exceeds threshold
          ),
          tolerance: tolerance,
        );

        expect(result, isNotNull);
        expect(result!.sourceLayer, 'reference_comparison_engine');
        expect(result.phrase, contains('frame'));
      },
    );

    test(
      'falls through to the lighting tier when pose/face and composition have no signal',
      () {
        final result = engine.evaluate(
          subject: _subject(),
          scene: _scene(brightness: 0.05),
          reference: _reference(
            overallBrightness: 0.95, // large deviation, exceeds threshold
          ),
          tolerance: tolerance,
        );

        expect(result, isNotNull);
        expect(result!.phrase, contains('light'));
      },
    );

    test(
      'prioritizes a mild pose/face deviation over a much more severe lighting deviation',
      () {
        // Shoulder deviation of 30° against a 0° reference: exceeds the
        // 22.5° threshold but only at "mild" severity (30/90 = 0.33).
        // Brightness deviation of 0.9 against a 0.5 tolerance: exceeds by
        // far more in relative terms (0.9 severity) — under the old flat
        // severity race this would have won. The 3-tier design must still
        // pick the pose/face attribute regardless.
        final result = engine.evaluate(
          subject: _subject(shoulderAngleDegrees: 30.0),
          scene: _scene(brightness: 0.05),
          reference: _reference(
            shoulderAngleDegrees: 0.0,
            overallBrightness: 0.95,
          ),
          tolerance: tolerance,
        );

        expect(result, isNotNull);
        expect(result!.phrase, 'Square your shoulders just a touch');
      },
    );
  });

  group('evaluate — within-tier severity tie-break', () {
    test(
      'picks the higher-severity candidate when two pose/face attributes both exceed threshold',
      () {
        // Shoulder: deviation 50 -> normalizedSeverity 0.56 (moderate, ~6).
        // FacePitch: deviation 80 -> normalizedSeverity 0.89 (strong, ~9).
        // Both are in the same (pose/face) tier and both exceed the pose
        // threshold (22.5°) — _pickWorst must choose facePitch, the
        // higher-severity candidate, not whichever was added to the tier
        // list first.
        final result = engine.evaluate(
          subject: _subject(
            shoulderAngleDegrees: 50.0,
            faceAngleXDegrees: 80.0,
          ),
          scene: _scene(),
          reference: _reference(
            shoulderAngleDegrees: 0.0,
            faceAngleXDegrees: 0.0,
          ),
          tolerance: tolerance,
        );

        expect(
          result!.phrase,
          "Tilt your head down a lot more — you're well above the reference angle",
        );
      },
    );
  });

  group('evaluate — severity tiering', () {
    test('mild shoulder deviation gets the mild phrase', () {
      // deviation = 30, normalizedSeverity = 30/90 = 0.33 (< 0.4 ceiling)
      final result = engine.evaluate(
        subject: _subject(shoulderAngleDegrees: 30.0),
        scene: _scene(),
        reference: _reference(shoulderAngleDegrees: 0.0),
        tolerance: tolerance,
      );

      expect(result!.phrase, 'Square your shoulders just a touch');
    });

    test('moderate shoulder deviation gets the moderate phrase', () {
      // deviation = 50, normalizedSeverity = 50/90 = 0.56 (0.4–0.75 band)
      final result = engine.evaluate(
        subject: _subject(shoulderAngleDegrees: 50.0),
        scene: _scene(),
        reference: _reference(shoulderAngleDegrees: 0.0),
        tolerance: tolerance,
      );

      expect(result!.phrase, 'Square your shoulders more');
    });

    test('strong shoulder deviation gets the strong phrase', () {
      // deviation = 80, normalizedSeverity = 80/90 = 0.89 (>= 0.75 ceiling)
      final result = engine.evaluate(
        subject: _subject(shoulderAngleDegrees: 80.0),
        scene: _scene(),
        reference: _reference(shoulderAngleDegrees: 0.0),
        tolerance: tolerance,
      );

      expect(
        result!.phrase,
        "Really square up your shoulders — they're tilted well off the reference",
      );
    });

    test('phrase direction flips when the sign of the deviation flips', () {
      final subjectAhead = engine.evaluate(
        subject: _subject(shoulderAngleDegrees: 50.0),
        scene: _scene(),
        reference: _reference(shoulderAngleDegrees: 0.0),
        tolerance: tolerance,
      );
      final subjectBehind = engine.evaluate(
        subject: _subject(shoulderAngleDegrees: 0.0),
        scene: _scene(),
        reference: _reference(shoulderAngleDegrees: 50.0),
        tolerance: tolerance,
      );

      expect(subjectAhead!.phrase, isNot(equals(subjectBehind!.phrase)));
    });
  });

  group('evaluate — facePitch (previously dead-code path)', () {
    test('mild pitch deviation gets a directional chin-down phrase', () {
      // deviation = 20, normalizedSeverity = 20/90 = 0.22 (mild)
      final result = engine.evaluate(
        subject: _subject(faceAngleXDegrees: 20.0),
        scene: _scene(),
        reference: _reference(faceAngleXDegrees: 0.0),
        tolerance: tolerance,
      );

      expect(result!.phrase, 'Tilt your chin down just a touch');
    });

    test('subject below the reference angle gets the chin-up phrase', () {
      final result = engine.evaluate(
        subject: _subject(faceAngleXDegrees: 0.0),
        scene: _scene(),
        reference: _reference(faceAngleXDegrees: 20.0),
        tolerance: tolerance,
      );

      expect(result!.phrase, 'Lift your chin slightly');
    });
  });

  group('evaluate — bodyRatio', () {
    test('moderate framing deviation gets the moderate reframe phrase', () {
      // relativeDeviation = |1.5 - 1.0| / 1.0 = 0.5 -> normalizedSeverity 0.5
      final result = engine.evaluate(
        subject: _subject(bodyRatio: 1.5),
        scene: _scene(),
        reference: _reference(bodyRatio: 1.0),
        tolerance: tolerance,
      );

      expect(
        result!.phrase,
        'Adjust your framing to better match the reference proportions',
      );
    });

    test('does not fire (returns null) when reference bodyRatio is zero', () {
      // relativeDeviation returns null when referenceValue == 0 —
      // ComparisonMath's divide-by-zero guard — so this evaluator must
      // skip rather than throw.
      final result = engine.evaluate(
        subject: _subject(bodyRatio: 1.5),
        scene: _scene(),
        reference: _reference(bodyRatio: 0.0),
        tolerance: tolerance,
      );

      expect(result, isNull);
    });
  });

  group('evaluate — eyeOpen (previously dead-code path)', () {
    test(
      'subject eyes much more open than reference gets the strong phrase',
      () {
        // relativeDeviation = |0.5 - 0.2| / 0.2 = 1.5, clamped severity 1.0
        final result = engine.evaluate(
          subject: _subject(eyeOpenRatio: 0.5),
          scene: _scene(),
          reference: _reference(eyeOpenRatio: 0.2),
          tolerance: tolerance,
        );

        expect(
          result!.phrase,
          "Your eyes are much more open than the reference — relax them more",
        );
      },
    );
  });

  group('evaluate — newly-directional attributes', () {
    test('mouth-open direction: subject more open than reference', () {
      // relativeDeviation = |0.5 - 0.2| / 0.2 = 1.5, well past threshold
      final result = engine.evaluate(
        subject: _subject(mouthOpenRatio: 0.5),
        scene: _scene(),
        reference: _reference(mouthOpenRatio: 0.2),
        tolerance: tolerance,
      );

      expect(
        result!.phrase,
        "Your mouth is a lot more open than the reference — close it more",
      );
    });

    test('face-roll direction: moderate tilt gets a directional phrase', () {
      // deviation = 50, normalizedSeverity = 50/90 = 0.56 (moderate band)
      final result = engine.evaluate(
        subject: _subject(faceAngleZDegrees: 50.0),
        scene: _scene(),
        reference: _reference(faceAngleZDegrees: 0.0),
        tolerance: tolerance,
      );

      expect(result!.phrase, "Straighten your head — it's tilted to the right");
    });

    // NOTE: whether "subject tilted more toward the right" actually *is*
    // the subject's right depends on `_faceRollDirectionIsMirrored`, a
    // compile-time constant gated on physical-device verification per
    // LIMITATIONS_AND_ROADMAP.md — it is not exposed for injection, so
    // this suite (like the roadmap item) can only confirm the *current*
    // wiring is internally consistent, not which real-world direction it
    // corresponds to on a given device.
    test('face-roll: opposite sign gets the mirrored-direction phrase', () {
      final result = engine.evaluate(
        subject: _subject(faceAngleZDegrees: 0.0),
        scene: _scene(),
        reference: _reference(faceAngleZDegrees: 50.0),
        tolerance: tolerance,
      );

      expect(result!.phrase, "Straighten your head — it's tilted to the left");
    });
  });

  group('evaluate — symmetry (composition tier)', () {
    test('moderate off-center deviation gets the moderate phrase', () {
      // deviation = (0.9 - 0.3).clamp(0,1) = 0.6 -> normalizedSeverity 0.6
      final result = engine.evaluate(
        subject: _subject(),
        scene: _scene(symmetryScore: 0.3),
        reference: _reference(symmetryScore: 0.9),
        tolerance: tolerance,
      );

      expect(result!.phrase, 'Center yourself more, like the reference');
    });
  });

  group('evaluate — backgroundClutter (composition tier)', () {
    test('scene plainer than reference gets the add-interest phrase', () {
      // subjectValue = 2/10 = 0.2, referenceValue = 8/10 = 0.8
      // deviation = 0.6 -> normalizedSeverity 0.6 (moderate)
      final result = engine.evaluate(
        subject: _subject(),
        scene: _scene(backgroundClutterCount: 2),
        reference: _reference(backgroundClutterCount: 8),
        tolerance: tolerance,
      );

      expect(
        result!.phrase,
        'Add some background interest, like your reference',
      );
    });
  });

  group('evaluate — warmth (lighting tier)', () {
    test('scene cooler-than-reference direction gets the warm-up phrase', () {
      // deviation = |0.9 - 0.3| = 0.6 -> normalizedSeverity 0.6 (moderate)
      // subjectValue (0.9) > referenceValue (0.3) -> "cool down" branch
      final result = engine.evaluate(
        subject: _subject(),
        scene: _scene(liveWarmthScore: 0.9),
        reference: _reference(warmthScore: 0.3),
        tolerance: tolerance,
      );

      expect(result!.phrase, 'Cool down the tones, like your reference');
    });
  });

  group('evaluate — hue (lighting tier)', () {
    test('large circular hue deviation gets the strong match-tone phrase', () {
      // circularDeviation(0, 180, 360) = 180 (the max) -> severity 1.0
      final result = engine.evaluate(
        subject: _subject(),
        scene: _scene(liveDominantHue: 0.0),
        reference: _reference(dominantHue: 180.0),
        tolerance: tolerance,
      );

      expect(
        result!.phrase,
        "Your color tone is quite different from the reference — try to match it",
      );
    });
  });

  group('evaluate — expression phrase specificity', () {
    test('names the actual target expression instead of a generic phrase', () {
      final result = engine.evaluate(
        subject: _subject(expression: 'serious'),
        scene: _scene(),
        reference: _reference(expression: 'smiling'),
        tolerance: tolerance,
      );

      expect(
        result!.phrase,
        "Try a more 'smiling' expression, like the reference",
      );
    });

    test('does not fire when subject and reference expressions match', () {
      final result = engine.evaluate(
        subject: _subject(expression: 'smiling'),
        scene: _scene(),
        reference: _reference(expression: 'smiling'),
        tolerance: tolerance,
      );

      expect(result, isNull);
    });
  });

  group('evaluate — result shape', () {
    test('always tags the source layer', () {
      final result = engine.evaluate(
        subject: _subject(shoulderAngleDegrees: 50.0),
        scene: _scene(),
        reference: _reference(shoulderAngleDegrees: 0.0),
        tolerance: tolerance,
      );

      expect(result, isA<PriorityAction>());
      expect(result!.sourceLayer, 'reference_comparison_engine');
    });
  });
}
