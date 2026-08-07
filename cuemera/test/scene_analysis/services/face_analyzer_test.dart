// test/scene_analysis/services/face_analyzer_test.dart
//
// CAVEAT (read before running): `Face` and `FaceContour` constructors below
// are reconstructed from the documented public API of
// google_mlkit_face_detection ^0.12.0 (per pubspec.yaml) — this container
// has no network access and no Flutter SDK installed, so the package source
// could not be fetched or compiled against to confirm field names directly.
// FILE_REFERENCE.md already notes `Face` has a confirmed public constructor;
// `FaceContour` was flagged as unconfirmed. If `flutter test` reports a
// constructor/field mismatch, the fix is mechanical — align the helper
// builders below (`_face`, `_contour`) with the real signatures; the test
// *logic* (what each case asserts) does not depend on that detail.
import 'dart:math' show Point;
import 'dart:ui' show Rect;

import 'package:cuemera/features/scene_analysis/domain/models/subject_profile.dart';
import 'package:cuemera/features/scene_analysis/services/face_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

FaceContour _contour(FaceContourType type, List<Point<int>> points) {
  return FaceContour(type: type, points: points);
}

Face _face({
  double? headEulerAngleX,
  double? headEulerAngleY,
  double? headEulerAngleZ,
  double? smilingProbability,
  double? leftEyeOpenProbability,
  double? rightEyeOpenProbability,
  Map<FaceContourType, FaceContour?> contours = const {},
}) {
  return Face(
    boundingBox: const Rect.fromLTWH(0, 0, 100, 100),
    landmarks: const {},
    contours: contours,
    headEulerAngleX: headEulerAngleX,
    headEulerAngleY: headEulerAngleY,
    headEulerAngleZ: headEulerAngleZ,
    smilingProbability: smilingProbability,
    leftEyeOpenProbability: leftEyeOpenProbability,
    rightEyeOpenProbability: rightEyeOpenProbability,
  );
}

SubjectProfile _previous({
  double? faceAngleDegrees,
  double? mouthOpenRatio,
  String? expression,
}) {
  return SubjectProfile(
    faceAngleDegrees: faceAngleDegrees,
    mouthOpenRatio: mouthOpenRatio,
    expression: expression,
    timestamp: DateTime.now(),
  );
}

void main() {
  final analyzer = FaceAnalyzer();

  group('analyzeFace — no face detected', () {
    test('clears every face-derived field when the list is null', () {
      final previous = _previous(
        faceAngleDegrees: 12.0,
        mouthOpenRatio: 0.4,
        expression: 'smiling',
      );

      final result = analyzer.analyzeFace(null, previous);

      expect(result.faceAngleDegrees, isNull);
      expect(result.faceAngleXDegrees, isNull);
      expect(result.faceAngleZDegrees, isNull);
      expect(result.mouthOpenRatio, isNull);
      expect(result.eyeOpenRatio, isNull);
      expect(result.eyesOpen, isNull);
      expect(result.expression, isNull);
    });

    test('clears every face-derived field when the list is empty', () {
      final previous = _previous(faceAngleDegrees: 12.0);
      final result = analyzer.analyzeFace(<Face>[], previous);
      expect(result.faceAngleDegrees, isNull);
    });
  });

  group('analyzeFace — angle mapping', () {
    test('maps headEulerAngleX/Y/Z straight through', () {
      final face = _face(
        headEulerAngleX: 5.0,
        headEulerAngleY: -10.0,
        headEulerAngleZ: 3.0,
      );

      final result = analyzer.analyzeFace([face], _previous());

      expect(result.faceAngleXDegrees, 5.0);
      expect(
        result.faceAngleDegrees,
        -10.0,
      ); // faceAngleDegrees == headEulerAngleY
      expect(result.faceAngleZDegrees, 3.0);
    });
  });

  group('analyzeFace — eyesOpen', () {
    test('is true only when both eyes are open above 0.5', () {
      final result = analyzer.analyzeFace([
        _face(leftEyeOpenProbability: 0.9, rightEyeOpenProbability: 0.8),
      ], _previous());
      expect(result.eyesOpen, isTrue);
    });

    test('is false when either eye is at or below 0.5', () {
      final result = analyzer.analyzeFace([
        _face(leftEyeOpenProbability: 0.9, rightEyeOpenProbability: 0.4),
      ], _previous());
      expect(result.eyesOpen, isFalse);
    });

    test('is null when either probability is missing', () {
      final result = analyzer.analyzeFace([
        _face(leftEyeOpenProbability: 0.9, rightEyeOpenProbability: null),
      ], _previous());
      expect(result.eyesOpen, isNull);
    });
  });

  group('analyzeFace — expression delegates to classifyExpression', () {
    test('big_smile when smiling probability is high and eyes are open', () {
      final result = analyzer.analyzeFace([
        _face(
          smilingProbability: 0.95,
          leftEyeOpenProbability: 0.9,
          rightEyeOpenProbability: 0.9,
        ),
      ], _previous());
      expect(result.expression, 'big_smile');
    });

    test('null expression when smilingProbability itself is null', () {
      final result = analyzer.analyzeFace([
        _face(leftEyeOpenProbability: 0.9, rightEyeOpenProbability: 0.9),
      ], _previous());
      expect(result.expression, isNull);
    });
  });

  group('analyzeFace — mouthOpenRatio from lip contours', () {
    test('computes a ratio when all four lip contours are present', () {
      final result = analyzer.analyzeFace([
        _face(
          contours: {
            FaceContourType.upperLipTop: _contour(FaceContourType.upperLipTop, [
              const Point(10, 40),
              const Point(30, 40),
            ]),
            FaceContourType.upperLipBottom: _contour(
              FaceContourType.upperLipBottom,
              [const Point(10, 45), const Point(30, 45)],
            ),
            FaceContourType.lowerLipTop: _contour(FaceContourType.lowerLipTop, [
              const Point(10, 50),
              const Point(30, 50),
            ]),
            FaceContourType.lowerLipBottom: _contour(
              FaceContourType.lowerLipBottom,
              [const Point(10, 60), const Point(30, 60)],
            ),
          },
        ),
      ], _previous());

      // bounding box: x in [10,30] (width 20), y in [40,60] (height 20)
      // -> aspect ratio height/width = 1.0
      expect(result.mouthOpenRatio, closeTo(1.0, 1e-9));
    });

    test('is null when no lip contours are present at all', () {
      final result = analyzer.analyzeFace([_face()], _previous());
      expect(result.mouthOpenRatio, isNull);
    });
  });

  group('analyzeFace — eyeOpenRatio averaging', () {
    test('averages left and right eye ratios when both contours exist', () {
      final result = analyzer.analyzeFace([
        _face(
          contours: {
            FaceContourType.leftEye: _contour(FaceContourType.leftEye, [
              const Point(0, 0),
              const Point(20, 0),
              const Point(20, 10), // ratio 0.5
            ]),
            FaceContourType.rightEye: _contour(FaceContourType.rightEye, [
              const Point(0, 0),
              const Point(20, 0),
              const Point(20, 20), // ratio 1.0
            ]),
          },
        ),
      ], _previous());

      expect(result.eyeOpenRatio, closeTo(0.75, 1e-9));
    });

    test(
      'falls back to the single available eye when the other is missing',
      () {
        final result = analyzer.analyzeFace([
          _face(
            contours: {
              FaceContourType.leftEye: _contour(FaceContourType.leftEye, [
                const Point(0, 0),
                const Point(20, 0),
                const Point(20, 10), // ratio 0.5
              ]),
            },
          ),
        ], _previous());

        expect(result.eyeOpenRatio, closeTo(0.5, 1e-9));
      },
    );

    test('is null when neither eye contour is present', () {
      final result = analyzer.analyzeFace([_face()], _previous());
      expect(result.eyeOpenRatio, isNull);
    });
  });
}
