// test/capture/services/auto_capture_service_test.dart
import 'package:cuemera/features/capture/services/auto_capture_service.dart';
import 'package:cuemera/features/reference_photo/domain/models/detection_thresholds.dart';
import 'package:cuemera/features/reference_photo/domain/models/reference_profile.dart';
import 'package:cuemera/features/reference_photo/domain/models/tolerance_settings.dart';
import 'package:cuemera/features/scene_analysis/domain/models/scene_profile.dart';
import 'package:cuemera/features/scene_analysis/domain/models/subject_profile.dart';
import 'package:flutter_test/flutter_test.dart';

SubjectProfile _alignedSubject({bool eyesOpen = true}) {
  return SubjectProfile(
    shoulderAngleDegrees: 0.0,
    faceAngleDegrees: 0.0,
    faceAngleXDegrees: 0.0,
    faceAngleZDegrees: 0.0,
    eyesOpen: eyesOpen,
    timestamp: DateTime.now(),
  );
}

ReferenceProfile _reference({int? backgroundClutterCount}) {
  return ReferenceProfile(
    imagePath: '/tmp/reference.jpg',
    shoulderAngleDegrees: 0.0,
    faceAngleDegrees: 0.0,
    faceAngleXDegrees: 0.0,
    faceAngleZDegrees: 0.0,
    backgroundClutterCount: backgroundClutterCount,
  );
}

SceneProfile _scene({double brightness = 0.5, int backgroundClutterCount = 0}) {
  return SceneProfile(
    brightness: brightness,
    negativeSpaceScore: 0.5,
    symmetryScore: 0.5,
    backgroundClutterCount: backgroundClutterCount,
  );
}

const _tolerance = ToleranceSettings.defaultBalanced;
const _thresholds = DetectionThresholds.defaultValues;

void main() {
  group('shouldCapture — happy path', () {
    test('returns true when every gate is satisfied', () {
      final service = AutoCaptureService();
      final result = service.shouldCapture(
        _alignedSubject(),
        _scene(),
        _reference(backgroundClutterCount: 0),
        _tolerance,
        1.0, // trackingProgress
        _thresholds,
      );
      expect(result, isTrue);
    });
  });

  group('shouldCapture — basic gates', () {
    // eyesOpen no longer gates capture: FaceAnalyzer.enableEyeAndExpressionSignals
    // is off, so eyesOpen is permanently null in production, and this gate
    // would have silently blocked every capture forever if left in place.
    // `_alignedSubject(eyesOpen: false)` is still exercised elsewhere to
    // confirm the value genuinely has no effect (see 'is unaffected by
    // eyesOpen' below); there's no longer a case where it should fail.
    test('is unaffected by eyesOpen — passes even when eyesOpen is false', () {
      final service = AutoCaptureService();
      final result = service.shouldCapture(
        _alignedSubject(eyesOpen: false),
        _scene(),
        _reference(backgroundClutterCount: 0),
        _tolerance,
        1.0,
        _thresholds,
      );
      expect(result, isTrue);
    });

    test('fails when brightness is below the minimum threshold', () {
      final service = AutoCaptureService();
      final result = service.shouldCapture(
        _alignedSubject(),
        _scene(brightness: 0.05),
        _reference(),
        _tolerance,
        1.0,
        _thresholds,
      );
      expect(result, isFalse);
    });

    test('fails when faceAngleDegrees has not been detected at all', () {
      final service = AutoCaptureService();
      final subjectWithNoFace = SubjectProfile(
        shoulderAngleDegrees: 0.0,
        eyesOpen: true,
        timestamp: DateTime.now(),
      );
      final result = service.shouldCapture(
        subjectWithNoFace,
        _scene(),
        _reference(),
        _tolerance,
        1.0,
        _thresholds,
      );
      expect(result, isFalse);
    });

    test('fails when trackingProgress is below the required minimum', () {
      final service = AutoCaptureService();
      final result = service.shouldCapture(
        _alignedSubject(),
        _scene(),
        _reference(),
        _tolerance,
        0.5, // below defaultValues.minTrackingProgressForCapture (0.9)
        _thresholds,
      );
      expect(result, isFalse);
    });
  });

  group('shouldCapture — background gate is reference-aware (P1 #7 fix)', () {
    test(
      'uses the fixed default threshold when the reference has no clutter value',
      () {
        final service = AutoCaptureService();

        final withinDefault = service.shouldCapture(
          _alignedSubject(),
          _scene(
            backgroundClutterCount: 5,
          ), // == defaultBackgroundClutterThreshold
          _reference(backgroundClutterCount: null),
          _tolerance,
          1.0,
          _thresholds,
        );
        final beyondDefault = service.shouldCapture(
          _alignedSubject(),
          _scene(backgroundClutterCount: 6),
          _reference(backgroundClutterCount: null),
          _tolerance,
          1.0,
          _thresholds,
        );

        expect(withinDefault, isTrue);
        expect(beyondDefault, isFalse);
      },
    );

    test('compares against the reference clutter value when one exists, '
        'even if the fixed default (5) would have allowed it', () {
      final service = AutoCaptureService();
      // A stricter-than-default composition tolerance, so a moderate
      // clutter deviation actually trips the threshold below.
      const strictTolerance = ToleranceSettings(
        poseTolerance: 0.5,
        compositionTolerance: 0.2,
        expressionTolerance: 0.5,
        colorTolerance: 0.5,
      );

      // Scene clutter (5) is within the OLD fixed literal (<=5, would have
      // passed), but the reference photo itself has almost no clutter (0).
      // The reference-aware gate should now fail here.
      final result = service.shouldCapture(
        _alignedSubject(),
        _scene(backgroundClutterCount: 5),
        _reference(backgroundClutterCount: 0),
        strictTolerance,
        1.0,
        _thresholds,
      );

      expect(result, isFalse);
    });

    test('passes when scene clutter closely matches a cluttered reference', () {
      final service = AutoCaptureService();

      final result = service.shouldCapture(
        _alignedSubject(),
        _scene(backgroundClutterCount: 8),
        _reference(backgroundClutterCount: 8),
        _tolerance,
        1.0,
        _thresholds,
      );

      expect(result, isTrue);
    });
  });

  group('shouldCapture — cooldown', () {
    test(
      'blocks a second capture immediately after triggerCapture()',
      () async {
        final service = AutoCaptureService();
        await service.triggerCapture();

        final result = service.shouldCapture(
          _alignedSubject(),
          _scene(),
          _reference(backgroundClutterCount: 0),
          _tolerance,
          1.0,
          _thresholds,
        );

        expect(result, isFalse);
      },
    );

    test('allows capture before any triggerCapture() has happened', () {
      final service = AutoCaptureService();
      final result = service.shouldCapture(
        _alignedSubject(),
        _scene(),
        _reference(backgroundClutterCount: 0),
        _tolerance,
        1.0,
        _thresholds,
      );
      expect(result, isTrue);
    });
  });

  group('debugConditionBreakdown', () {
    test(
      'reports each gate individually, matching shouldCapture\'s outcome',
      () {
        final service = AutoCaptureService();
        final breakdown = service.debugConditionBreakdown(
          _alignedSubject(eyesOpen: false),
          _scene(),
          _reference(),
          _tolerance,
          1.0,
          _thresholds,
        );

        // No 'eyesOpen' key: it's no longer part of the capture decision,
        // so debugConditionBreakdown no longer reports it (see
        // auto_capture_service.dart).
        expect(breakdown.containsKey('eyesOpen'), isFalse);
        // every other gate should still report its own true/false.
        expect(breakdown.containsKey('trackingProgress'), isTrue);
        expect(breakdown.containsKey('backgroundClutter'), isTrue);
      },
    );
  });
}
