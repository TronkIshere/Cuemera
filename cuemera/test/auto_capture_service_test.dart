// test/auto_capture_service_test.dart
import 'package:cuemera/features/capture/services/auto_capture_service.dart';
import 'package:cuemera/features/scene_analysis/domain/models/scene_profile.dart';
import 'package:cuemera/features/scene_analysis/domain/models/subject_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AutoCaptureService.shouldCapture', () {
    late AutoCaptureService service;

    setUp(() {
      service = AutoCaptureService();
    });

    SubjectProfile validSubject() {
      return SubjectProfile(
        eyesOpen: true,
        shoulderAngleDegrees: 5,
        faceAngleDegrees: 5,
        timestamp: DateTime.now(),
      );
    }

    SceneProfile validScene() {
      return const SceneProfile(
        brightness: 0.6,
        negativeSpaceScore: 0.5,
        symmetryScore: 0.5,
        backgroundClutterCount: 2,
      );
    }

    test('returns false when eyesOpen is false', () {
      final subject = validSubject().copyWith(eyesOpen: false);
      final result = service.shouldCapture(subject, validScene(), 1.0);
      expect(result, false);
    });

    test('returns false when brightness too low', () {
      final scene = validScene().copyWith(brightness: 0.1);
      final result = service.shouldCapture(validSubject(), scene, 1.0);
      expect(result, false);
    });

    test(
      'returns false when all other conditions pass but trackingProgress is below threshold',
      () {
        final result = service.shouldCapture(validSubject(), validScene(), 0.5);
        expect(result, false);
      },
    );

    test(
      'returns true when trackingProgress is above threshold with all else passing',
      () {
        final result = service.shouldCapture(
          validSubject(),
          validScene(),
          0.95,
        );
        expect(result, true);
      },
    );

    test(
      'returns false when trackingProgress is exactly at threshold minus epsilon',
      () {
        final result = service.shouldCapture(
          validSubject(),
          validScene(),
          0.89,
        );
        expect(result, false);
      },
    );

    test('returns true when trackingProgress is exactly at threshold', () {
      final result = service.shouldCapture(validSubject(), validScene(), 0.9);
      expect(result, true);
    });
  });
}
