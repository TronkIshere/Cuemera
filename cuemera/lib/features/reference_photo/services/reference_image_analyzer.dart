// features/reference_photo/services/reference_image_analyzer.dart
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cuemera/features/reference_photo/domain/models/reference_profile.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, visibleForTesting;
import 'package:flutter/material.dart' show Color, HSLColor, Offset;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';
import 'package:image/image.dart' as img;

import '../../../core/analysis/analysis_constants.dart';
import '../../../core/pose/landmark_gate.dart';
import '../../../core/services/error_reporting_service.dart';
import '../../../core/services/expression_classifier.dart';
import '../domain/comparison_math.dart';
import 'landmark_trust_classifier.dart';
import 'reference_photo_crop_redetect.dart';

class _PoseAnalysisResult {
  final double? bodyRatio;
  final double? shoulderAngleDegrees;
  final double? shoulderBalanceRatio;
  final double? shoulderSpanRatio;
  final double? bodyYawEstimate;
  final List<Offset?>? poseLandmarkPoints;
  final Map<String, double>? metricConfidence;

  const _PoseAnalysisResult({
    this.bodyRatio,
    this.shoulderAngleDegrees,
    this.shoulderBalanceRatio,
    this.shoulderSpanRatio,
    this.bodyYawEstimate,
    this.poseLandmarkPoints,
    this.metricConfidence,
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

img.Image? _decodeAndBakeOrientation(Uint8List bytes) {
  final raw = img.decodeImage(bytes);
  return raw == null ? null : img.bakeOrientation(raw);
}

class ReferenceImageAnalyzer {
  static const double _maxExtremityExtrapolationMultiplier = 4.0;

  Future<ReferenceProfile> analyze(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);

    final results = await Future.wait<Object?>([
      _detectPose(inputImage),
      _analyzeFace(inputImage),
      _runSegmentation(inputImage),
      _decodeImageFile(imagePath),
    ]);

    final landmarks = results[0] as Map<PoseLandmarkType, PoseLandmark>?;
    final faceResult = results[1] as _FaceAnalysisResult;
    final mask = results[2] as SegmentationMask?;
    final decodedResult = results[3] as _DecodedImageResult;

    final poseResult = await _derivePose(
      landmarks: landmarks,
      mask: mask,
      decodedResult: decodedResult,
    );

    double? negativeSpaceScore;
    double? symmetryScore;
    int? backgroundClutterCount;
    if (mask != null) {
      negativeSpaceScore = estimateNegativeSpace(mask.confidences);
      symmetryScore = estimateSymmetry(
        width: mask.width,
        height: mask.height,
        confidences: mask.confidences,
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
    _PaletteAnalysisResult paletteResult = const _PaletteAnalysisResult();
    if (decodedResult.decoded != null) {
      overallBrightness = estimateBrightness(decodedResult.decoded!);
      paletteResult = estimatePalette(decodedResult.decoded!);
    }

    if (kDebugMode) {
      final trustedPoints =
          poseResult.poseLandmarkPoints?.where((p) => p != null).length ?? 0;
      debugPrint(
        'ReferenceImageAnalyzer analyze: path=$imagePath outcome '
        'poseDetected=${landmarks != null && landmarks.isNotEmpty} '
        'trustedPoints=$trustedPoints/${kGatedLandmarkOrder.length} '
        'faceDetected=${faceResult.faceContourPoints != null}',
      );
    }

    return ReferenceProfile(
      imagePath: imagePath,
      bodyRatio: poseResult.bodyRatio,
      faceAngleDegrees: faceResult.faceAngleDegrees,
      faceAngleXDegrees: faceResult.faceAngleXDegrees,
      faceAngleZDegrees: faceResult.faceAngleZDegrees,
      shoulderAngleDegrees: poseResult.shoulderAngleDegrees,
      shoulderBalanceRatio: poseResult.shoulderBalanceRatio,
      shoulderSpanRatio: poseResult.shoulderSpanRatio,
      bodyYawEstimate: poseResult.bodyYawEstimate,
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
      metricConfidence: poseResult.metricConfidence,
    );
  }

  Future<Map<PoseLandmarkType, PoseLandmark>?> _detectPose(
    InputImage inputImage,
  ) async {
    Map<PoseLandmarkType, PoseLandmark>? landmarks;
    final poseDetector = PoseDetector(
      options: PoseDetectorOptions(model: PoseDetectionModel.accurate),
    );
    try {
      final poses = await poseDetector.processImage(inputImage);
      if (poses.length == 1) {
        landmarks = poses.first.landmarks;
      } else if (poses.length > 1) {
        // Same defensive fix as _analyzeFace's face selection: don't
        // blindly trust detection order. Uses the landmarks' own bounding
        // box as a size proxy, since Pose has no boundingBox of its own.
        double area(Map<PoseLandmarkType, PoseLandmark> lm) {
          if (lm.isEmpty) return 0;
          final xs = lm.values.map((l) => l.x);
          final ys = lm.values.map((l) => l.y);
          return (xs.reduce(max) - xs.reduce(min)) *
              (ys.reduce(max) - ys.reduce(min));
        }

        landmarks = poses
            .map((p) => p.landmarks)
            .reduce((a, b) => area(a) >= area(b) ? a : b);
        if (kDebugMode) {
          debugPrint(
            'ReferenceImageAnalyzer: ${poses.length} poses detected, '
            'picked the largest by landmark bounding-box area.',
          );
        }
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

    if (kDebugMode) {
      if (landmarks == null || landmarks.isEmpty) {
        debugPrint('ReferenceImageAnalyzer raw pose: no pose detected');
      } else {
        final lines = <String>[];
        for (var i = 0; i < kGatedLandmarkOrder.length; i++) {
          final landmark = landmarks[kGatedLandmarkOrder[i]];
          lines.add(
            landmark == null
                ? '${kGatedLandmarkNames[i]}=absent'
                : '${kGatedLandmarkNames[i]}='
                      'x=${landmark.x.toStringAsFixed(1)},'
                      'y=${landmark.y.toStringAsFixed(1)},'
                      'likelihood=${landmark.likelihood.toStringAsFixed(3)}',
          );
        }
        debugPrint('ReferenceImageAnalyzer raw pose: ${lines.join(' ')}');
      }
    }

    return landmarks;
  }

  Future<_PoseAnalysisResult> _derivePose({
    required Map<PoseLandmarkType, PoseLandmark>? landmarks,
    required SegmentationMask? mask,
    required _DecodedImageResult decodedResult,
  }) async {
    if (landmarks == null || landmarks.isEmpty) {
      return const _PoseAnalysisResult();
    }

    final imageWidth = decodedResult.imageWidth;
    final imageHeight = decodedResult.imageHeight;

    SubjectBoundingBox? box;
    if (mask != null && imageWidth != null && imageHeight != null) {
      box = computeSubjectBoundingBox(
        mask: mask,
        imageWidth: imageWidth.round(),
        imageHeight: imageHeight.round(),
      );
    }

    if (kDebugMode && mask != null) {
      final imageAspect = (imageWidth != null && imageHeight != null)
          ? imageWidth / imageHeight
          : null;
      final maskAspect = mask.height > 0 ? mask.width / mask.height : null;
      debugPrint(
        'ReferenceImageAnalyzer raw mask: maskSize=${mask.width}x${mask.height} '
        'imageSize=${imageWidth?.toStringAsFixed(0)}x${imageHeight?.toStringAsFixed(0)} '
        'maskAspect=${maskAspect?.toStringAsFixed(3)} '
        'imageAspect=${imageAspect?.toStringAsFixed(3)}',
      );
      if (imageWidth != null && imageHeight != null) {
        final rawPoints = <Offset?>[
          for (final type in kGatedLandmarkOrder)
            landmarks[type] != null
                ? Offset(landmarks[type]!.x, landmarks[type]!.y)
                : null,
        ];
        final rawConfidence = debugSampleRawMaskConfidence(
          points: rawPoints,
          mask: mask,
          imageWidth: imageWidth,
          imageHeight: imageHeight,
        );
        final lines = [
          for (final entry in rawConfidence.entries)
            '${kGatedLandmarkNames[entry.key]}=${entry.value.toStringAsFixed(3)}',
        ];
        debugPrint(
          'ReferenceImageAnalyzer raw mask confidence: ${lines.join(' ')}',
        );

        if (box == null) {
          debugPrint(
            'ReferenceImageAnalyzer raw subject box: none (mask empty)',
          );
        } else {
          final outside = <String>[];
          for (var i = 0; i < rawPoints.length; i++) {
            final point = rawPoints[i];
            if (point == null) continue;
            final within =
                point.dx >= box.left &&
                point.dx <= box.left + box.width &&
                point.dy >= box.top &&
                point.dy <= box.top + box.height;
            if (!within) outside.add(kGatedLandmarkNames[i]);
          }
          debugPrint(
            'ReferenceImageAnalyzer raw subject box: '
            'left=${box.left} top=${box.top} width=${box.width} height=${box.height} '
            'pointsOutside=$outside',
          );
        }
      }
    }

    final likelihoodGate = PoseLandmarkGate.fromLandmarks(
      landmarks: landmarks,
      maskSignal: MaskTrustSignal.none,
    );

    var maskSignal = MaskTrustSignal.none;
    if (mask != null && imageWidth != null && imageHeight != null) {
      maskSignal = sampleMaskTrust(
        points: likelihoodGate.confidentPoints,
        mask: mask,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        precomputedBox: box,
      );
    }

    var gate = maskSignal.bypassed
        ? likelihoodGate
        : PoseLandmarkGate.fromLandmarks(
            landmarks: landmarks,
            maskSignal: maskSignal,
          );

    if (kDebugMode) {
      debugPrint('ReferenceImageAnalyzer ${gate.describe()}');
    }

    if (mask != null && decodedResult.decoded != null) {
      final outcome = await reconcileWithCrop(
        originalGate: gate,
        decoded: decodedResult.decoded!,
        mask: mask,
        precomputedBox: box,
      );
      if (outcome.changedAnyLandmark) gate = outcome.gate;
    }

    double? shoulderAngleDegrees;
    double? torsoScale;
    double? shoulderBalanceRatio;
    double? shoulderSpanRatio;
    double? bodyYawEstimate;
    double? bodyRatio;

    final leftShoulder = gate.landmark(PoseLandmarkType.leftShoulder);
    final rightShoulder = gate.landmark(PoseLandmarkType.rightShoulder);

    if (leftShoulder != null && rightShoulder != null) {
      final dy = rightShoulder.y - leftShoulder.y;
      final dx = rightShoulder.x - leftShoulder.x;
      shoulderAngleDegrees = atan2(dy, dx) * 180 / pi;
      final scale = sqrt(dx * dx + dy * dy);
      torsoScale = scale;

      shoulderBalanceRatio = scale > 0
          ? (leftShoulder.y - rightShoulder.y) / scale
          : null;

      bodyYawEstimate = atan2(rightShoulder.z - leftShoulder.z, dx) * 180 / pi;

      final leftHip = gate.landmark(PoseLandmarkType.leftHip);
      final rightHip = gate.landmark(PoseLandmarkType.rightHip);
      if (leftHip != null && rightHip != null) {
        final shoulderMidX = (leftShoulder.x + rightShoulder.x) / 2;
        final shoulderMidY = (leftShoulder.y + rightShoulder.y) / 2;
        final hipMidX = (leftHip.x + rightHip.x) / 2;
        final hipMidY = (leftHip.y + rightHip.y) / 2;
        final torsoHeight = sqrt(
          pow(hipMidX - shoulderMidX, 2) + pow(hipMidY - shoulderMidY, 2),
        );
        shoulderSpanRatio = torsoHeight > 0 ? scale / torsoHeight : null;
      }
    }

    final nose = gate.landmark(PoseLandmarkType.nose);
    final bodyRatioHip = gate.landmark(PoseLandmarkType.leftHip);
    final leftAnkle = gate.landmark(PoseLandmarkType.leftAnkle);

    if (nose != null && bodyRatioHip != null && leftAnkle != null) {
      final upperLength = (bodyRatioHip.y - nose.y).abs();
      final lowerLength = (leftAnkle.y - bodyRatioHip.y).abs();
      final scale = torsoScale;
      final ankleExtrapolationSuspect =
          scale != null &&
          scale > 0 &&
          lowerLength > _maxExtremityExtrapolationMultiplier * scale;
      if (lowerLength > 0 && !ankleExtrapolationSuspect) {
        bodyRatio = upperLength / lowerLength;
      }
    }

    return _PoseAnalysisResult(
      bodyRatio: bodyRatio,
      shoulderAngleDegrees: shoulderAngleDegrees,
      shoulderBalanceRatio: shoulderBalanceRatio,
      shoulderSpanRatio: shoulderSpanRatio,
      bodyYawEstimate: bodyYawEstimate,
      poseLandmarkPoints: gate.hasTrustedPoints ? gate.trustedPoints : null,
      metricConfidence: _poseMetricConfidence(
        gate,
        shoulderAngleDegrees: shoulderAngleDegrees,
        shoulderBalanceRatio: shoulderBalanceRatio,
        shoulderSpanRatio: shoulderSpanRatio,
        bodyYawEstimate: bodyYawEstimate,
        bodyRatio: bodyRatio,
      ),
    );
  }

  /// Same metric-confidence idiom as PoseAnalyzer (live path) — kept as an
  /// identical, independent implementation rather than a shared import,
  /// since this analyzer already reconciles [gate] against crop-redetect
  /// evidence (Phase 2) before this point, unlike the live path's
  /// single-detection gate.
  Map<String, double>? _poseMetricConfidence(
    PoseLandmarkGate gate, {
    required double? shoulderAngleDegrees,
    required double? shoulderBalanceRatio,
    required double? shoulderSpanRatio,
    required double? bodyYawEstimate,
    required double? bodyRatio,
  }) {
    double minConfidence(List<PoseLandmarkType> types) {
      var lowest = 1.0;
      for (final type in types) {
        final value = gate.trust(type)?.confidence.value ?? 0.0;
        if (value < lowest) lowest = value;
      }
      return lowest;
    }

    final result = <String, double>{
      if (shoulderAngleDegrees != null)
        'shoulderAngleDegrees': minConfidence([
          PoseLandmarkType.leftShoulder,
          PoseLandmarkType.rightShoulder,
        ]),
      if (shoulderBalanceRatio != null)
        'shoulderBalanceRatio': minConfidence([
          PoseLandmarkType.leftShoulder,
          PoseLandmarkType.rightShoulder,
        ]),
      if (bodyYawEstimate != null)
        'bodyYawEstimate': minConfidence([
          PoseLandmarkType.leftShoulder,
          PoseLandmarkType.rightShoulder,
        ]),
      if (shoulderSpanRatio != null)
        'shoulderSpanRatio': minConfidence([
          PoseLandmarkType.leftShoulder,
          PoseLandmarkType.rightShoulder,
          PoseLandmarkType.leftHip,
          PoseLandmarkType.rightHip,
        ]),
      if (bodyRatio != null)
        'bodyRatio': minConfidence([
          PoseLandmarkType.nose,
          PoseLandmarkType.leftHip,
          PoseLandmarkType.leftAnkle,
        ]),
    };
    return result.isEmpty ? null : result;
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
        final face = faces.length == 1
            ? faces.first
            : faces.reduce((a, b) {
                final areaA = a.boundingBox.width * a.boundingBox.height;
                final areaB = b.boundingBox.width * b.boundingBox.height;
                return areaA >= areaB ? a : b;
              });
        if (kDebugMode && faces.length > 1) {
          debugPrint(
            'ReferenceImageAnalyzer: ${faces.length} faces detected, '
            'picked the largest by bounding-box area '
            '(${face.boundingBox.width.round()}x'
            '${face.boundingBox.height.round()}) — bug found this session: '
            'this used to always take faces.first, which could pick up a '
            'small printed/illustrated face (e.g. on a t-shirt) instead of '
            "the actual subject's much larger one.",
          );
        }
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
    final segmenter = SelfieSegmenter(mode: SegmenterMode.single);
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
    try {
      final bytes = await File(imagePath).readAsBytes();
      if (kDebugMode) {
        debugPrint(
          'ReferenceImageAnalyzer analyze: path=$imagePath '
          'bytes=${bytes.length} fingerprint=${_cheapFingerprint(bytes)}',
        );
      }
      final decoded = await Isolate.run(() => _decodeAndBakeOrientation(bytes));
      if (decoded == null) return const _DecodedImageResult();
      return _DecodedImageResult(
        decoded: decoded,
        imageWidth: decoded.width.toDouble(),
        imageHeight: decoded.height.toDouble(),
      );
    } catch (e, st) {
      ErrorReportingService.instance.report(
        e,
        st,
        context: 'ReferenceImageAnalyzer: image decode',
      );
      return const _DecodedImageResult();
    }
  }

  String _cheapFingerprint(List<int> bytes) {
    var acc = bytes.length;
    final step = bytes.length > 4096 ? bytes.length ~/ 4096 : 1;
    for (var i = 0; i < bytes.length; i += step) {
      acc = (acc * 31 + bytes[i]) & 0x7fffffff;
    }
    return acc.toRadixString(16);
  }

  /// Dominant hue / warmth from the already-decoded image, in place of a
  /// second full decode through PaletteGenerator. Trades PaletteGenerator's
  /// quantized dominant-color extraction for a circular mean of hue over
  /// samples with saturation above a low floor (skips near-grey pixels,
  /// which have no reliable hue). Sampling density matches
  /// _estimateBrightness's adaptive step, so cost does not scale with source
  /// resolution.
  @visibleForTesting
  _PaletteAnalysisResult estimatePalette(img.Image decoded) {
    final width = decoded.width;
    final height = decoded.height;
    if (width <= 0 || height <= 0) return const _PaletteAnalysisResult();

    final step = adaptiveStep(width, height, kBrightnessTargetSamples);

    double sumX = 0;
    double sumY = 0;
    int count = 0;

    for (var y = 0; y < height; y += step) {
      for (var x = 0; x < width; x += step) {
        final pixel = decoded.getPixel(x, y);
        final hsl = HSLColor.fromColor(
          Color.fromARGB(
            255,
            pixel.r.round().clamp(0, 255),
            pixel.g.round().clamp(0, 255),
            pixel.b.round().clamp(0, 255),
          ),
        );
        if (hsl.saturation < 0.15) continue;
        final hueRad = hsl.hue * pi / 180;
        sumX += cos(hueRad);
        sumY += sin(hueRad);
        count++;
      }
    }

    if (count == 0) return const _PaletteAnalysisResult();

    var hue = atan2(sumY, sumX) * 180 / pi;
    if (hue < 0) hue += 360;
    final warmth = ((cos((hue - 60) * pi / 180) + 1) / 2).clamp(0.0, 1.0);
    return _PaletteAnalysisResult(dominantHue: hue, warmthScore: warmth);
  }

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
  }) {
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

    final step = clutterStep(width);

    double varianceSum = 0;
    int sampleCount = 0;
    int? previousValue;

    final scaleX = maskWidth / width;
    final scaleY = maskHeight / height;

    for (var y = 0; y < height; y += step) {
      for (var x = 0; x < width; x += step) {
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
    return clutterScoreFromVariance(avgVariance);
  }

  @visibleForTesting
  double? estimateBrightness(img.Image decoded) {
    final width = decoded.width;
    final height = decoded.height;
    if (width <= 0 || height <= 0) return null;

    final step = adaptiveStep(width, height, kBrightnessTargetSamples);
    int sum = 0;
    int count = 0;

    for (var y = 0; y < height; y += step) {
      for (var x = 0; x < width; x += step) {
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
