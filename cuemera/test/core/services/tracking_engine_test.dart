// test/core/services/tracking_engine_test.dart
import 'package:cuemera/core/services/tracking_engine.dart';
import 'package:cuemera/features/reference_photo/domain/models/detection_thresholds.dart';
import 'package:cuemera/features/reference_photo/domain/models/tolerance_settings.dart';
import 'package:cuemera/features/scene_analysis/domain/models/scene_profile.dart';
import 'package:cuemera/features/scene_analysis/domain/models/subject_profile.dart';
import 'package:flutter_test/flutter_test.dart';

SubjectProfile _subject({
  double? bodyRatio,
  double? faceAngleDegrees,
  double? faceAngleXDegrees,
  double? faceAngleZDegrees,
  double? mouthOpenRatio,
  double? eyeOpenRatio,
  double? shoulderAngleDegrees,
  bool? eyesOpen,
  String? expression,
}) {
  return SubjectProfile(
    bodyRatio: bodyRatio,
    faceAngleDegrees: faceAngleDegrees,
    faceAngleXDegrees: faceAngleXDegrees,
    faceAngleZDegrees: faceAngleZDegrees,
    mouthOpenRatio: mouthOpenRatio,
    eyeOpenRatio: eyeOpenRatio,
    shoulderAngleDegrees: shoulderAngleDegrees,
    eyesOpen: eyesOpen,
    expression: expression,
    timestamp: DateTime.now(),
  );
}

SceneProfile _scene({
  double brightness = 0.5,
  int backgroundClutterCount = 0,
  double? depthEstimate,
}) {
  return SceneProfile(
    brightness: brightness,
    negativeSpaceScore: 0.5,
    symmetryScore: 0.5,
    backgroundClutterCount: backgroundClutterCount,
    depthEstimate: depthEstimate,
  );
}

void main() {
  group('smoothSubject — EMA', () {
    test('moves partway from previous toward raw by emaAlpha', () {
      final engine = TrackingEngine(
        thresholds: DetectionThresholds.defaultValues.copyWith(
          debounceFrames: 1, // isolate EMA behavior from debounce
        ),
      );
      final previous = _subject(faceAngleDegrees: 0.0);
      final raw = _subject(faceAngleDegrees: 10.0);

      final smoothed = engine.smoothSubject(raw, previous);

      // defaultValues.emaAlpha = 0.3 -> 0 + 0.3 * (10 - 0) = 3.0
      expect(smoothed.faceAngleDegrees, closeTo(3.0, 1e-9));
    });

    test('passes raw straight through when there is no previous value', () {
      final engine = TrackingEngine();
      final previous = _subject(); // faceAngleDegrees null
      final raw = _subject(faceAngleDegrees: 15.0);

      final smoothed = engine.smoothSubject(raw, previous);
      expect(smoothed.faceAngleDegrees, 15.0);
    });

    // Previously dropped entirely by smoothSubject's return constructor —
    // faceAngleXDegrees/faceAngleZDegrees/mouthOpenRatio/eyeOpenRatio were
    // always null on the smoothed output regardless of what raw contained.
    test('EMA-smooths faceAngleXDegrees the same way as faceAngleDegrees', () {
      final engine = TrackingEngine(
        thresholds: DetectionThresholds.defaultValues.copyWith(
          debounceFrames: 1,
        ),
      );
      final previous = _subject(faceAngleXDegrees: 0.0);
      final raw = _subject(faceAngleXDegrees: 10.0);

      final smoothed = engine.smoothSubject(raw, previous);
      expect(smoothed.faceAngleXDegrees, closeTo(3.0, 1e-9));
    });

    test('EMA-smooths faceAngleZDegrees the same way as faceAngleDegrees', () {
      final engine = TrackingEngine(
        thresholds: DetectionThresholds.defaultValues.copyWith(
          debounceFrames: 1,
        ),
      );
      final previous = _subject(faceAngleZDegrees: 0.0);
      final raw = _subject(faceAngleZDegrees: 10.0);

      final smoothed = engine.smoothSubject(raw, previous);
      expect(smoothed.faceAngleZDegrees, closeTo(3.0, 1e-9));
    });

    test('EMA-smooths mouthOpenRatio', () {
      final engine = TrackingEngine(
        thresholds: DetectionThresholds.defaultValues.copyWith(
          debounceFrames: 1,
        ),
      );
      final previous = _subject(mouthOpenRatio: 0.0);
      final raw = _subject(mouthOpenRatio: 1.0);

      final smoothed = engine.smoothSubject(raw, previous);
      expect(smoothed.mouthOpenRatio, closeTo(0.3, 1e-9));
    });

    test('EMA-smooths eyeOpenRatio', () {
      final engine = TrackingEngine(
        thresholds: DetectionThresholds.defaultValues.copyWith(
          debounceFrames: 1,
        ),
      );
      final previous = _subject(eyeOpenRatio: 0.0);
      final raw = _subject(eyeOpenRatio: 1.0);

      final smoothed = engine.smoothSubject(raw, previous);
      expect(smoothed.eyeOpenRatio, closeTo(0.3, 1e-9));
    });
  });

  group('smoothSubject — debounce', () {
    test(
      'does not accept a changed eyesOpen value before debounceFrames streak',
      () {
        final engine = TrackingEngine(
          thresholds: DetectionThresholds.defaultValues.copyWith(
            debounceFrames: 2,
          ),
        );
        var previous = _subject(eyesOpen: true);

        // First frame reporting a flip to false: streak = 1, not yet accepted.
        previous = engine.smoothSubject(_subject(eyesOpen: false), previous);
        expect(previous.eyesOpen, true);

        // Second consecutive frame agreeing: streak = 2, now accepted.
        previous = engine.smoothSubject(_subject(eyesOpen: false), previous);
        expect(previous.eyesOpen, false);
      },
    );

    test(
      'nulls out a value after it goes missing for debounceFrames in a row',
      () {
        final engine = TrackingEngine(
          thresholds: DetectionThresholds.defaultValues.copyWith(
            debounceFrames: 2,
          ),
        );
        var previous = _subject(expression: 'smiling');

        previous = engine.smoothSubject(_subject(expression: null), previous);
        expect(previous.expression, 'smiling'); // still within grace period

        previous = engine.smoothSubject(_subject(expression: null), previous);
        expect(previous.expression, isNull); // now nulled out
      },
    );

    test(
      'nulls out mouthOpenRatio after it goes missing for debounceFrames in a row',
      () {
        final engine = TrackingEngine(
          thresholds: DetectionThresholds.defaultValues.copyWith(
            debounceFrames: 2,
          ),
        );
        var previous = _subject(mouthOpenRatio: 0.5);

        previous = engine.smoothSubject(
          _subject(mouthOpenRatio: null),
          previous,
        );
        expect(previous.mouthOpenRatio, 0.5); // still within grace period

        previous = engine.smoothSubject(
          _subject(mouthOpenRatio: null),
          previous,
        );
        expect(previous.mouthOpenRatio, isNull); // now nulled out
      },
    );

    test(
      'nulls out faceAngleZDegrees after it goes missing for debounceFrames in a row',
      () {
        final engine = TrackingEngine(
          thresholds: DetectionThresholds.defaultValues.copyWith(
            debounceFrames: 2,
          ),
        );
        var previous = _subject(faceAngleZDegrees: 12.0);

        previous = engine.smoothSubject(
          _subject(faceAngleZDegrees: null),
          previous,
        );
        expect(previous.faceAngleZDegrees, 12.0); // still within grace period

        previous = engine.smoothSubject(
          _subject(faceAngleZDegrees: null),
          previous,
        );
        expect(previous.faceAngleZDegrees, isNull); // now nulled out
      },
    );

    // Previously untested — the 4 newly-smoothed fields shared the same
    // missing-streak pattern, but only faceAngleZDegrees/mouthOpenRatio had
    // a null-out case above. faceAngleXDegrees and eyeOpenRatio use the
    // same `_faceAngleXMissingStreak`/`_eyeOpenRatioMissingStreak` counters
    // per FILE_REFERENCE.md and deserve the same direct coverage rather
    // than relying on the EMA tests above to imply it.
    test(
      'nulls out faceAngleXDegrees after it goes missing for debounceFrames in a row',
      () {
        final engine = TrackingEngine(
          thresholds: DetectionThresholds.defaultValues.copyWith(
            debounceFrames: 2,
          ),
        );
        var previous = _subject(faceAngleXDegrees: 8.0);

        previous = engine.smoothSubject(
          _subject(faceAngleXDegrees: null),
          previous,
        );
        expect(previous.faceAngleXDegrees, 8.0); // still within grace period

        previous = engine.smoothSubject(
          _subject(faceAngleXDegrees: null),
          previous,
        );
        expect(previous.faceAngleXDegrees, isNull); // now nulled out
      },
    );

    test(
      'nulls out eyeOpenRatio after it goes missing for debounceFrames in a row',
      () {
        final engine = TrackingEngine(
          thresholds: DetectionThresholds.defaultValues.copyWith(
            debounceFrames: 2,
          ),
        );
        var previous = _subject(eyeOpenRatio: 0.7);

        previous = engine.smoothSubject(_subject(eyeOpenRatio: null), previous);
        expect(previous.eyeOpenRatio, 0.7); // still within grace period

        previous = engine.smoothSubject(_subject(eyeOpenRatio: null), previous);
        expect(previous.eyeOpenRatio, isNull); // now nulled out
      },
    );
  });

  group('smoothScene', () {
    test('EMA-smooths brightness the same way as subject fields', () {
      final engine = TrackingEngine(
        thresholds: DetectionThresholds.defaultValues.copyWith(
          debounceFrames: 1,
        ),
      );
      final previous = _scene(brightness: 0.2);
      final raw = _scene(brightness: 1.0);

      final smoothed = engine.smoothScene(raw, previous);
      // 0.2 + 0.3 * (1.0 - 0.2) = 0.44
      expect(smoothed.brightness, closeTo(0.44, 1e-9));
    });

    test('debounces backgroundClutterCount changes', () {
      final engine = TrackingEngine(
        thresholds: DetectionThresholds.defaultValues.copyWith(
          debounceFrames: 2,
        ),
      );
      var previous = _scene(backgroundClutterCount: 1);

      previous = engine.smoothScene(
        _scene(backgroundClutterCount: 5),
        previous,
      );
      expect(previous.backgroundClutterCount, 1); // streak = 1, not yet

      previous = engine.smoothScene(
        _scene(backgroundClutterCount: 5),
        previous,
      );
      expect(previous.backgroundClutterCount, 5); // streak = 2, accepted
    });
  });

  group('trackingProgress — delegates to ComparisonMath (P1 #9 fix)', () {
    test('returns 1.0 when every tracked attribute matches exactly', () {
      final engine = TrackingEngine();
      final subject = _subject(
        shoulderAngleDegrees: 0.0,
        faceAngleDegrees: 0.0,
        bodyRatio: 1.0,
        eyesOpen: true,
        expression: 'smiling',
      );
      final scene = _scene(brightness: 0.5, backgroundClutterCount: 2);

      final progress = engine.trackingProgress(
        subject,
        subject,
        scene,
        scene,
        ToleranceSettings.defaultBalanced,
      );

      expect(progress, closeTo(1.0, 1e-9));
    });

    test('drops when shoulder angle is far outside tolerance', () {
      final engine = TrackingEngine();
      final target = _subject(
        shoulderAngleDegrees: 0.0,
        eyesOpen: true,
        expression: 'smiling',
      );
      final current = _subject(
        shoulderAngleDegrees: 80.0, // wildly different
        eyesOpen: true,
        expression: 'smiling',
      );
      final scene = _scene();

      final progress = engine.trackingProgress(
        current,
        target,
        scene,
        scene,
        ToleranceSettings.defaultBalanced,
      );

      expect(progress, lessThan(1.0));
    });

    test(
      'now factors in brightness and background clutter (previously ignored)',
      () {
        final engine = TrackingEngine();
        final subject = _subject(eyesOpen: true, expression: 'smiling');

        final matchingScene = _scene(
          brightness: 0.5,
          backgroundClutterCount: 2,
        );
        final mismatchedScene = _scene(
          brightness: 0.05,
          backgroundClutterCount: 10,
        );

        final progressMatching = engine.trackingProgress(
          subject,
          subject,
          matchingScene,
          matchingScene,
          ToleranceSettings.defaultBalanced,
        );
        final progressMismatched = engine.trackingProgress(
          subject,
          subject,
          mismatchedScene,
          matchingScene,
          ToleranceSettings.defaultBalanced,
        );

        expect(progressMismatched, lessThan(progressMatching));
      },
    );

    test('returns a value in [0, 1] even with no attributes populated', () {
      final engine = TrackingEngine();
      final emptySubject = _subject();
      final scene = _scene();

      final progress = engine.trackingProgress(
        emptySubject,
        emptySubject,
        scene,
        scene,
        ToleranceSettings.defaultBalanced,
      );

      expect(progress, inInclusiveRange(0.0, 1.0));
    });
  });
}
