// features/reference_photo/services/reference_image_analyzer.dart
import 'dart:io';
import 'dart:math';

import 'package:cuemera/features/reference_photo/domain/models/reference_profile.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart' show HSLColor, Offset;
import 'package:flutter/painting.dart' show FileImage;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';
import 'package:image/image.dart' as img;
import 'package:palette_generator/palette_generator.dart';

import '../../../core/services/error_reporting_service.dart';
import '../../../core/services/expression_classifier.dart';
import '../domain/comparison_math.dart';

class _PoseAnalysisResult {
  final double? bodyRatio;
  final double? shoulderAngleDegrees;
  final List<Offset?>? poseLandmarkPoints;

  const _PoseAnalysisResult({
    this.bodyRatio,
    this.shoulderAngleDegrees,
    this.poseLandmarkPoints,
  });
}

class _FaceAnalysisResult {
  final double? faceAngleDegrees;
  final double? faceAngleXDegrees;
  final double? faceAngleZDegrees;
  final String? expression;
  final double? smilingProbability;
  final double? leftEyeOpenProbability;
  final double? rightEyeOpenProbability;
  final List<Offset>? faceContourPoints;
  final List<Offset>? faceOvalPoints;
  final List<Offset>? leftEyeContour;
  final List<Offset>? rightEyeContour;
  final List<Offset>? leftEyebrowTopContour;
  final List<Offset>? rightEyebrowTopContour;
  final List<Offset>? upperLipTopContour;
  final List<Offset>? upperLipBottomContour;
  final List<Offset>? lowerLipTopContour;
  final List<Offset>? lowerLipBottomContour;
  final List<Offset>? noseBridgeContour;
  final List<Offset>? noseBottomContour;
  final double? mouthOpenRatio;
  final double? eyeOpenRatio;

  const _FaceAnalysisResult({
    this.faceAngleDegrees,
    this.faceAngleXDegrees,
    this.faceAngleZDegrees,
    this.expression,
    this.smilingProbability,
    this.leftEyeOpenProbability,
    this.rightEyeOpenProbability,
    this.faceContourPoints,
    this.faceOvalPoints,
    this.leftEyeContour,
    this.rightEyeContour,
    this.leftEyebrowTopContour,
    this.rightEyebrowTopContour,
    this.upperLipTopContour,
    this.upperLipBottomContour,
    this.lowerLipTopContour,
    this.lowerLipBottomContour,
    this.noseBridgeContour,
    this.noseBottomContour,
    this.mouthOpenRatio,
    this.eyeOpenRatio,
  });
}

class _DecodedImageResult {
  final img.Image? decoded;
  final double? imageWidth;
  final double? imageHeight;

  const _DecodedImageResult({this.decoded, this.imageWidth, this.imageHeight});
}

class _PaletteAnalysisResult {
  final double? dominantHue;
  final double? warmthScore;

  const _PaletteAnalysisResult({this.dominantHue, this.warmthScore});
}

class ReferenceImageAnalyzer {
  static const double _minLandmarkLikelihood = 0.6;

  /// Same guard as `ReferenceAnalysisPainter._findSuspectExtremities` in
  /// `reference_picker_sheet.dart` (see LIMITATIONS_AND_ROADMAP.md /
  /// FILE_REFERENCE.md): a wrist/ankle landmark can pass the likelihood
  /// check above yet still sit at a wildly extrapolated position when the
  /// reference photo is framed to cut off before that joint. `bodyRatio`
  /// used to trust the ankle position outright once it cleared
  /// `_minLandmarkLikelihood`, so a partial-body photo could silently
  /// skew scoring/tracking. This mirrors the preview's fix: an ankle more
  /// than 4x the shoulder-width scale away from the hip is treated as an
  /// unreliable extrapolation and `bodyRatio` is left null rather than
  /// computed from it.
  static const double _maxExtremityExtrapolationMultiplier = 4.0;

  Future<ReferenceProfile> analyze(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);

    // None of these five steps depends on another's result, so they run
    // concurrently instead of sequentially. Only the mask-dependent scores
    // below (which need both `mask` and `decoded`) wait on more than one.
    final results = await Future.wait<Object?>([
      _analyzePose(inputImage),
      _analyzeFace(inputImage),
      _runSegmentation(inputImage),
      _decodeImageFile(imagePath),
      _analyzePalette(imagePath),
    ]);

    final poseResult = results[0] as _PoseAnalysisResult;
    final faceResult = results[1] as _FaceAnalysisResult;
    final mask = results[2] as SegmentationMask?;
    final decodedResult = results[3] as _DecodedImageResult;
    final paletteResult = results[4] as _PaletteAnalysisResult;

    double? negativeSpaceScore;
    double? symmetryScore;
    int? backgroundClutterCount;
    if (mask != null) {
      negativeSpaceScore = estimateNegativeSpace(mask.confidences);
      symmetryScore = estimateSymmetry(
        width: mask.width,
        height: mask.height,
        confidences: mask.confidences,
        shoulderAngleDegrees: poseResult.shoulderAngleDegrees,
      );
      if (decodedResult.decoded != null) {
        backgroundClutterCount = estimateBackgroundClutter(
          decodedResult.decoded!,
          maskWidth: mask.width,
          maskHeight: mask.height,
          confidences: mask.confidences,
        );
      }
    }

    double? overallBrightness;
    if (decodedResult.decoded != null) {
      overallBrightness = estimateBrightness(decodedResult.decoded!);
    }

    return ReferenceProfile(
      imagePath: imagePath,
      bodyRatio: poseResult.bodyRatio,
      faceAngleDegrees: faceResult.faceAngleDegrees,
      faceAngleXDegrees: faceResult.faceAngleXDegrees,
      faceAngleZDegrees: faceResult.faceAngleZDegrees,
      shoulderAngleDegrees: poseResult.shoulderAngleDegrees,
      expression: faceResult.expression,
      smilingProbability: faceResult.smilingProbability,
      leftEyeOpenProbability: faceResult.leftEyeOpenProbability,
      rightEyeOpenProbability: faceResult.rightEyeOpenProbability,
      negativeSpaceScore: negativeSpaceScore,
      symmetryScore: symmetryScore,
      backgroundClutterCount: backgroundClutterCount,
      dominantHue: paletteResult.dominantHue,
      warmthScore: paletteResult.warmthScore,
      overallBrightness: overallBrightness,
      poseLandmarkPoints: poseResult.poseLandmarkPoints,
      faceContourPoints: faceResult.faceContourPoints,
      faceOvalPoints: faceResult.faceOvalPoints,
      leftEyeContour: faceResult.leftEyeContour,
      rightEyeContour: faceResult.rightEyeContour,
      leftEyebrowTopContour: faceResult.leftEyebrowTopContour,
      rightEyebrowTopContour: faceResult.rightEyebrowTopContour,
      upperLipTopContour: faceResult.upperLipTopContour,
      upperLipBottomContour: faceResult.upperLipBottomContour,
      lowerLipTopContour: faceResult.lowerLipTopContour,
      lowerLipBottomContour: faceResult.lowerLipBottomContour,
      noseBridgeContour: faceResult.noseBridgeContour,
      noseBottomContour: faceResult.noseBottomContour,
      mouthOpenRatio: faceResult.mouthOpenRatio,
      eyeOpenRatio: faceResult.eyeOpenRatio,
      imageWidth: decodedResult.imageWidth,
      imageHeight: decodedResult.imageHeight,
    );
  }

  Future<_PoseAnalysisResult> _analyzePose(InputImage inputImage) async {
    double? bodyRatio;
    double? shoulderAngleDegrees;
    List<Offset?>? poseLandmarkPoints;
    final poseDetector = PoseDetector(options: PoseDetectorOptions());
    try {
      final poses = await poseDetector.processImage(inputImage);
      if (poses.isNotEmpty) {
        final landmarks = poses.first.landmarks;
        final leftShoulder = landmarks[PoseLandmarkType.leftShoulder];
        final rightShoulder = landmarks[PoseLandmarkType.rightShoulder];
        final leftHip = landmarks[PoseLandmarkType.leftHip];
        final leftAnkle = landmarks[PoseLandmarkType.leftAnkle];
        final nose = landmarks[PoseLandmarkType.nose];

        double? torsoScale;
        if (leftShoulder != null && rightShoulder != null) {
          final dy = rightShoulder.y - leftShoulder.y;
          final dx = rightShoulder.x - leftShoulder.x;
          shoulderAngleDegrees = atan2(dy, dx) * 180 / pi;
          torsoScale = sqrt(dx * dx + dy * dy);
        }

        final noseConfident =
            nose != null && nose.likelihood >= _minLandmarkLikelihood;
        final leftHipConfident =
            leftHip != null && leftHip.likelihood >= _minLandmarkLikelihood;
        final leftAnkleConfident =
            leftAnkle != null && leftAnkle.likelihood >= _minLandmarkLikelihood;

        if (noseConfident && leftHipConfident && leftAnkleConfident) {
          final upperLength = (leftHip.y - nose.y).abs();
          final lowerLength = (leftAnkle.y - leftHip.y).abs();
          // Bug fix: likelihood alone doesn't catch a confidently-reported
          // but implausibly-extrapolated ankle (e.g. a half-body reference
          // photo). Skip bodyRatio for this frame rather than silently
          // computing it from a bad position.
          final ankleExtrapolationSuspect =
              torsoScale != null &&
                  torsoScale > 0 &&
                  lowerLength > _maxExtremityExtrapolationMultiplier * torsoScale;
          if (lowerLength > 0 && !ankleExtrapolationSuspect) {
            bodyRatio = upperLength / lowerLength;
          }
        }

        const landmarkTypesToDraw = [
          PoseLandmarkType.nose,
          PoseLandmarkType.leftEye,
          PoseLandmarkType.rightEye,
          PoseLandmarkType.leftShoulder,
          PoseLandmarkType.rightShoulder,
          PoseLandmarkType.leftElbow,
          PoseLandmarkType.rightElbow,
          PoseLandmarkType.leftWrist,
          PoseLandmarkType.rightWrist,
          PoseLandmarkType.leftHip,
          PoseLandmarkType.rightHip,
          PoseLandmarkType.leftKnee,
          PoseLandmarkType.rightKnee,
          PoseLandmarkType.leftAnkle,
          PoseLandmarkType.rightAnkle,
        ];
        final points = <Offset?>[];
        for (final type in landmarkTypesToDraw) {
          final landmark = landmarks[type];
          final isConfident =
              landmark != null && landmark.likelihood >= _minLandmarkLikelihood;
          points.add(isConfident ? Offset(landmark.x, landmark.y) : null);
        }
        if (points.any((p) => p != null)) poseLandmarkPoints = points;
      }
    } catch (e, st) {
      ErrorReportingService.instance.report(
        e,
        st,
        context: 'ReferenceImageAnalyzer: pose detection',
      );
    } finally {
      await poseDetector.close();
    }

    return _PoseAnalysisResult(
      bodyRatio: bodyRatio,
      shoulderAngleDegrees: shoulderAngleDegrees,
      poseLandmarkPoints: poseLandmarkPoints,
    );
  }

  Future<_FaceAnalysisResult> _analyzeFace(InputImage inputImage) async {
    double? faceAngleDegrees;
    double? faceAngleXDegrees;
    double? faceAngleZDegrees;
    String? expression;
    double? smilingProbability;
    double? leftEyeOpenProbability;
    double? rightEyeOpenProbability;
    List<Offset>? faceContourPoints;
    List<Offset>? faceOvalPoints;
    List<Offset>? leftEyeContour;
    List<Offset>? rightEyeContour;
    List<Offset>? leftEyebrowTopContour;
    List<Offset>? rightEyebrowTopContour;
    List<Offset>? upperLipTopContour;
    List<Offset>? upperLipBottomContour;
    List<Offset>? lowerLipTopContour;
    List<Offset>? lowerLipBottomContour;
    List<Offset>? noseBridgeContour;
    List<Offset>? noseBottomContour;
    double? mouthOpenRatio;
    double? eyeOpenRatio;

    final faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        enableContours: true,
        enableLandmarks: true,
        enableTracking: false,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );
    try {
      final faces = await faceDetector.processImage(inputImage);
      if (faces.isNotEmpty) {
        final face = faces.first;
        faceAngleDegrees = face.headEulerAngleY;
        faceAngleXDegrees = face.headEulerAngleX;
        faceAngleZDegrees = face.headEulerAngleZ;

        smilingProbability = face.smilingProbability;
        leftEyeOpenProbability = face.leftEyeOpenProbability;
        rightEyeOpenProbability = face.rightEyeOpenProbability;

        expression = classifyExpression(
          smilingProbability: smilingProbability,
          leftEyeOpenProbability: leftEyeOpenProbability,
          rightEyeOpenProbability: rightEyeOpenProbability,
        );

        final box = face.boundingBox;
        faceContourPoints = [
          Offset(box.left, box.top),
          Offset(box.right, box.top),
          Offset(box.right, box.bottom),
          Offset(box.left, box.bottom),
        ];

        List<Offset>? contourPoints(FaceContourType type) {
          final contour = face.contours[type];
          final points = contour?.points;
          if (points == null || points.isEmpty) return null;
          return points
              .map((p) => Offset(p.x.toDouble(), p.y.toDouble()))
              .toList();
        }

        faceOvalPoints = contourPoints(FaceContourType.face);
        leftEyeContour = contourPoints(FaceContourType.leftEye);
        rightEyeContour = contourPoints(FaceContourType.rightEye);
        leftEyebrowTopContour = contourPoints(FaceContourType.leftEyebrowTop);
        rightEyebrowTopContour = contourPoints(FaceContourType.rightEyebrowTop);
        upperLipTopContour = contourPoints(FaceContourType.upperLipTop);
        upperLipBottomContour = contourPoints(FaceContourType.upperLipBottom);
        lowerLipTopContour = contourPoints(FaceContourType.lowerLipTop);
        lowerLipBottomContour = contourPoints(FaceContourType.lowerLipBottom);
        noseBridgeContour = contourPoints(FaceContourType.noseBridge);
        noseBottomContour = contourPoints(FaceContourType.noseBottom);

        mouthOpenRatio = ComparisonMath.boundingBoxAspectRatio([
          ...?upperLipTopContour,
          ...?upperLipBottomContour,
          ...?lowerLipTopContour,
          ...?lowerLipBottomContour,
        ]);

        final leftEyeRatio = ComparisonMath.boundingBoxAspectRatio(
          leftEyeContour,
        );
        final rightEyeRatio = ComparisonMath.boundingBoxAspectRatio(
          rightEyeContour,
        );
        eyeOpenRatio = (leftEyeRatio != null && rightEyeRatio != null)
            ? (leftEyeRatio + rightEyeRatio) / 2
            : (leftEyeRatio ?? rightEyeRatio);
      }
    } catch (e, st) {
      ErrorReportingService.instance.report(
        e,
        st,
        context: 'ReferenceImageAnalyzer: face detection',
      );
    } finally {
      await faceDetector.close();
    }

    return _FaceAnalysisResult(
      faceAngleDegrees: faceAngleDegrees,
      faceAngleXDegrees: faceAngleXDegrees,
      faceAngleZDegrees: faceAngleZDegrees,
      expression: expression,
      smilingProbability: smilingProbability,
      leftEyeOpenProbability: leftEyeOpenProbability,
      rightEyeOpenProbability: rightEyeOpenProbability,
      faceContourPoints: faceContourPoints,
      faceOvalPoints: faceOvalPoints,
      leftEyeContour: leftEyeContour,
      rightEyeContour: rightEyeContour,
      leftEyebrowTopContour: leftEyebrowTopContour,
      rightEyebrowTopContour: rightEyebrowTopContour,
      upperLipTopContour: upperLipTopContour,
      upperLipBottomContour: upperLipBottomContour,
      lowerLipTopContour: lowerLipTopContour,
      lowerLipBottomContour: lowerLipBottomContour,
      noseBridgeContour: noseBridgeContour,
      noseBottomContour: noseBottomContour,
      mouthOpenRatio: mouthOpenRatio,
      eyeOpenRatio: eyeOpenRatio,
    );
  }

  Future<SegmentationMask?> _runSegmentation(InputImage inputImage) async {
    SegmentationMask? mask;
    final segmenter = SelfieSegmenter(
      mode: SegmenterMode.single,
      enableRawSizeMask: true,
    );
    try {
      mask = await segmenter.processImage(inputImage);
    } catch (e, st) {
      ErrorReportingService.instance.report(
        e,
        st,
        context: 'ReferenceImageAnalyzer: segmentation',
      );
    } finally {
      await segmenter.close();
    }
    return mask;
  }

  Future<_DecodedImageResult> _decodeImageFile(String imagePath) async {
    img.Image? decoded;
    double? imageWidth;
    double? imageHeight;
    try {
      final bytes = await File(imagePath).readAsBytes();
      final rawDecoded = img.decodeImage(bytes);
      if (rawDecoded != null) {
        // img.decodeImage() reads raw sensor-orientation pixels and does
        // not apply the file's EXIF orientation tag on its own, while
        // InputImage.fromFilePath() (used for pose/face detection above)
        // does apply it. Without baking orientation here, decoded.width/
        // height (and therefore ReferenceProfile.imageWidth/imageHeight,
        // which the painter uses to scale landmark points) can end up in
        // a different coordinate space than the landmarks themselves —
        // landmarks come out correct but get mapped onto the wrong
        // canvas dimensions, which is what produced the garbled skeleton
        // lines on EXIF-rotated photos.
        decoded = img.bakeOrientation(rawDecoded);
        imageWidth = decoded.width.toDouble();
        imageHeight = decoded.height.toDouble();
      }
    } catch (e, st) {
      ErrorReportingService.instance.report(
        e,
        st,
        context: 'ReferenceImageAnalyzer: image decode',
      );
    }
    return _DecodedImageResult(
      decoded: decoded,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
    );
  }

  Future<_PaletteAnalysisResult> _analyzePalette(String imagePath) async {
    double? dominantHue;
    double? warmthScore;
    try {
      final paletteGenerator = await PaletteGenerator.fromImageProvider(
        FileImage(File(imagePath)),
      );
      final dominantColor = paletteGenerator.dominantColor?.color;
      if (dominantColor != null) {
        final hsl = HSLColor.fromColor(dominantColor);
        dominantHue = hsl.hue;
        warmthScore = ((cos((dominantHue - 60) * pi / 180) + 1) / 2).clamp(
          0.0,
          1.0,
        );
      }
    } catch (e, st) {
      ErrorReportingService.instance.report(
        e,
        st,
        context: 'ReferenceImageAnalyzer: palette generation',
      );
    }
    return _PaletteAnalysisResult(
      dominantHue: dominantHue,
      warmthScore: warmthScore,
    );
  }

  /// Public + [visibleForTesting] so it can be unit-tested directly with a
  /// plain confidences list instead of requiring a real on-device
  /// segmentation pass (or a hand-built `SegmentationMask`, which has no
  /// confirmed public constructor). Behavior is unchanged from the former
  /// `_`-prefixed, `SegmentationMask`-typed version — this is a signature
  /// change for testability only.
  @visibleForTesting
  double? estimateNegativeSpace(List<double> confidences) {
    if (confidences.isEmpty) return null;

    int subjectPixels = 0;
    for (final confidence in confidences) {
      if (confidence > 0.5) subjectPixels++;
    }

    final total = confidences.length;
    if (total == 0) return null;

    final subjectRatio = subjectPixels / total;
    return (1.0 - subjectRatio).clamp(0.0, 1.0);
  }

  @visibleForTesting
  double? estimateSymmetry({
    required int width,
    required int height,
    required List<double> confidences,
    required double? shoulderAngleDegrees,
  }) {
    if (shoulderAngleDegrees != null) {
      final angle = shoulderAngleDegrees.abs();
      return (1.0 - (angle / 45.0)).clamp(0.0, 1.0);
    }

    if (confidences.isEmpty || width <= 0 || height <= 0) return null;

    int leftSubject = 0;
    int rightSubject = 0;

    for (var y = 0; y < height; y += 4) {
      for (var x = 0; x < width; x += 4) {
        final index = y * width + x;
        if (index >= confidences.length) continue;

        if (confidences[index] > 0.5) {
          if (x < width / 2) {
            leftSubject++;
          } else {
            rightSubject++;
          }
        }
      }
    }

    final total = leftSubject + rightSubject;
    if (total == 0) return null;

    final balance = 1.0 - ((leftSubject - rightSubject).abs() / total);
    return balance.clamp(0.0, 1.0);
  }

  @visibleForTesting
  int? estimateBackgroundClutter(
      img.Image decoded, {
        required int maskWidth,
        required int maskHeight,
        required List<double> confidences,
      }) {
    final width = decoded.width;
    final height = decoded.height;
    if (width <= 0 || height <= 0 || confidences.isEmpty) return null;

    const stepX = 6;
    const stepY = 6;

    double varianceSum = 0;
    int sampleCount = 0;
    int? previousValue;

    final scaleX = maskWidth / width;
    final scaleY = maskHeight / height;

    for (var y = 0; y < height; y += stepY) {
      for (var x = 0; x < width; x += stepX) {
        final maskX = (x * scaleX).floor();
        final maskY = (y * scaleY).floor();
        final maskIndex = maskY * maskWidth + maskX;

        bool isBackground = true;
        if (maskIndex >= 0 && maskIndex < confidences.length) {
          if (confidences[maskIndex] > 0.5) isBackground = false;
        }

        if (!isBackground) {
          previousValue = null;
          continue;
        }

        final pixel = decoded.getPixel(x, y);
        final luma = (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b)
            .round();

        if (previousValue != null) {
          final diff = (luma - previousValue).abs();
          varianceSum += diff;
          sampleCount++;
        }
        previousValue = luma;
      }
      previousValue = null;
    }

    if (sampleCount == 0) return null;

    final avgVariance = varianceSum / sampleCount;
    final clutterScore = (avgVariance / 12.0).clamp(0.0, 10.0);
    return clutterScore.round();
  }

  @visibleForTesting
  double? estimateBrightness(img.Image decoded) {
    final width = decoded.width;
    final height = decoded.height;
    if (width <= 0 || height <= 0) return null;

    const stepX = 4;
    const stepY = 4;
    int sum = 0;
    int count = 0;

    for (var y = 0; y < height; y += stepY) {
      for (var x = 0; x < width; x += stepX) {
        final pixel = decoded.getPixel(x, y);
        final luma = (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b);
        sum += luma.round();
        count++;
      }
    }

    if (count == 0) return null;
    return (sum / count) / 255.0;
  }
}