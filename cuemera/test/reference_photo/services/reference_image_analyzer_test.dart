// test/reference_photo/services/reference_image_analyzer_test.dart
//
// SCOPE NOTE: `ReferenceImageAnalyzer.analyze()` itself is not covered here.
// It constructs real `PoseDetector`/`FaceDetector`/`SelfieSegmenter`
// instances internally and calls their native `processImage()` methods —
// there's no injection point to substitute a fake, so a real device/platform
// channel is required to exercise it (not something a pure-Dart `flutter
// test` run can do). What *is* independently testable is the pure pixel/mask
// math the analyzer runs on the results, which is why those four helpers
// (`estimateNegativeSpace`, `estimateSymmetry`, `estimateBackgroundClutter`,
// `estimateBrightness`) were made public + `@visibleForTesting` and changed
// to take plain `List<double>`/`int` mask data instead of a real
// `SegmentationMask` — that type has no confirmed public constructor, so
// building a fake one for tests wasn't a safe option (see the compile
// failure this replaces).
import 'package:cuemera/features/reference_photo/services/reference_image_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

img.Image _solidImage(int width, int height, int r, int g, int b) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, r, g, b);
    }
  }
  return image;
}

void main() {
  final analyzer = ReferenceImageAnalyzer();

  group('estimateNegativeSpace', () {
    test('is 0.0 when the subject fills the whole mask', () {
      expect(
        analyzer.estimateNegativeSpace([0.9, 0.9, 0.9, 0.9]),
        closeTo(0.0, 1e-9),
      );
    });

    test('is 1.0 when nothing in the mask is above the subject threshold', () {
      expect(
        analyzer.estimateNegativeSpace([0.1, 0.1, 0.1, 0.1]),
        closeTo(1.0, 1e-9),
      );
    });

    test('is null when the mask has no confidence values at all', () {
      expect(analyzer.estimateNegativeSpace(const []), isNull);
    });
  });

  group('estimateSymmetry', () {
    test(
      'derives from shoulderAngleDegrees when available, ignoring the mask',
      () {
        // (1 - 22.5/45).clamp(0,1) = 0.5
        expect(
          analyzer.estimateSymmetry(
            width: 2,
            height: 2,
            confidences: [0.9, 0.1, 0.1, 0.9],
            shoulderAngleDegrees: 22.5,
          ),
          closeTo(0.5, 1e-9),
        );
      },
    );

    test(
      'falls back to mask left/right balance when shoulderAngleDegrees is null',
      () {
        // 8x8 mask, sampled every 4px -> points (0,0),(4,0),(0,4),(4,4).
        // Subject present on both left (x=0) points and both right (x=4)
        // points -> perfectly balanced.
        final confidences = List<double>.filled(64, 0.0);
        for (final (x, y) in [(0, 0), (4, 0), (0, 4), (4, 4)]) {
          confidences[y * 8 + x] = 0.9;
        }

        expect(
          analyzer.estimateSymmetry(
            width: 8,
            height: 8,
            confidences: confidences,
            shoulderAngleDegrees: null,
          ),
          closeTo(1.0, 1e-9),
        );
      },
    );

    test('reports low balance when the subject is entirely on one side', () {
      final confidences = List<double>.filled(64, 0.0);
      // Only the left-side sample points (x=0) are subject.
      confidences[0 * 8 + 0] = 0.9;
      confidences[4 * 8 + 0] = 0.9;

      expect(
        analyzer.estimateSymmetry(
          width: 8,
          height: 8,
          confidences: confidences,
          shoulderAngleDegrees: null,
        ),
        closeTo(0.0, 1e-9),
      );
    });

    test('is null when there is neither an angle nor any mask signal', () {
      expect(
        analyzer.estimateSymmetry(
          width: 0,
          height: 0,
          confidences: const [],
          shoulderAngleDegrees: null,
        ),
        isNull,
      );
    });
  });

  group('estimateBackgroundClutter', () {
    test('is 0 for a perfectly flat background', () {
      final image = _solidImage(24, 6, 128, 128, 128);
      expect(
        analyzer.estimateBackgroundClutter(
          image,
          maskWidth: 24,
          maskHeight: 6,
          confidences: List<double>.filled(24 * 6, 0.0), // all background
        ),
        0,
      );
    });

    test('is high (clamped to 10) for a sharply alternating background', () {
      final image = img.Image(width: 24, height: 6);
      // Sampled x-steps are 0, 6, 12, 18 (stepX = 6) — alternate black/white.
      for (var x = 0; x < 24; x++) {
        final onDarkStep = (x ~/ 6).isEven;
        final v = onDarkStep ? 0 : 255;
        for (var y = 0; y < 6; y++) {
          image.setPixelRgb(x, y, v, v, v);
        }
      }

      expect(
        analyzer.estimateBackgroundClutter(
          image,
          maskWidth: 24,
          maskHeight: 6,
          confidences: List<double>.filled(24 * 6, 0.0),
        ),
        10,
      );
    });

    test(
      'is null when the whole frame is masked as subject (no background samples)',
      () {
        final image = _solidImage(24, 6, 200, 200, 200);
        expect(
          analyzer.estimateBackgroundClutter(
            image,
            maskWidth: 24,
            maskHeight: 6,
            confidences: List<double>.filled(24 * 6, 0.9), // all subject
          ),
          isNull,
        );
      },
    );
  });

  group('estimateBrightness', () {
    test('is 1.0 for a fully white image', () {
      final image = _solidImage(8, 8, 255, 255, 255);
      expect(analyzer.estimateBrightness(image), closeTo(1.0, 1e-2));
    });

    test('is 0.0 for a fully black image', () {
      final image = _solidImage(8, 8, 0, 0, 0);
      expect(analyzer.estimateBrightness(image), closeTo(0.0, 1e-2));
    });

    test('is roughly 0.5 for a mid-gray image', () {
      final image = _solidImage(8, 8, 128, 128, 128);
      expect(analyzer.estimateBrightness(image), closeTo(0.5, 0.05));
    });
  });
}
