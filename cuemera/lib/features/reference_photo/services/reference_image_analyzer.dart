// features/reference_photo/services/reference_image_analyzer.dart
import 'dart:io';
import 'dart:math';

import 'package:cuemera/features/reference_photo/domain/models/reference_profile.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, visibleForTesting;
import 'package:flutter/material.dart' show HSLColor, Offset;
import 'package:flutter/painting.dart' show FileImage;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';
import 'package:image/image.dart' as img;
import 'package:palette_generator/palette_generator.dart';

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

  const _PoseAnalysisResult({
    this.bodyRatio,
    this.shoulderAngleDegrees,
    this.shoulderBalanceRatio,
    this.shoulderSpanRatio,
    this.bodyYawEstimate,
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
  /// Hip-to-ankle guard, kept alongside `PoseLandmarkGate`'s
  /// knee-to-ankle segment budgets: the two catch different framings.
  static const double _maxExtremityExtrapolationMultiplier = 4.0;

  Future<ReferenceProfile> analyze(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);

    // None of these five steps depends on another's result, so they run
    // concurrently instead of sequentially. Only the mask-dependent scores
    // below (which need both `mask` and `decoded`) wait on more than one.
    final results = await Future.wait<Object?>([
      _detectPose(inputImage),
      _analyzeFace(inputImage),
      _runSegmentation(inputImage),
      _decodeImageFile(imagePath),
      _analyzePalette(imagePath),
    ]);

    final landmarks = results[0] as Map<PoseLandmarkType, PoseLandmark>?;
    final faceResult = results[1] as _FaceAnalysisResult;
    final mask = results[2] as SegmentationMask?;
    final decodedResult = results[3] as _DecodedImageResult;
    final paletteResult = results[4] as _PaletteAnalysisResult;

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
    );
  }

  Future<Map<PoseLandmarkType, PoseLandmark>?> _detectPose(
    InputImage inputImage,
  ) async {
    Map<PoseLandmarkType, PoseLandmark>? landmarks;
    final poseDetector = PoseDetector(options: PoseDetectorOptions());
    try {
      final poses = await poseDetector.processImage(inputImage);
      if (poses.isNotEmpty) landmarks = poses.first.landmarks;
    } catch (e, st) {
      ErrorReportingService.instance.report(
        e,
        st,
        context: 'ReferenceImageAnalyzer: pose detection',
      );
    } finally {
      await poseDetector.close();
    }

    // Debug-only, raw library output -- logged here, before _derivePose
    // touches it with any of our own gating code, specifically so this can
    // be read on its own: if ML Kit itself reports e.g. a high-likelihood
    // ankle sitting inside on-screen UI text, that's the pose model
    // hallucinating, not a bug in this codebase. Compare against the
    // gated `gate.describe()` line _derivePose logs afterward -- if the
    // same landmark is high-likelihood here but absent/suspect there, the
    // gate did its job; if it's still trusted there, look at our code next.
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
                      'z=${landmark.z.toStringAsFixed(1)},'
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

    // Debug-only, raw library output for the mask side: dimensions and
    // aspect ratio as ML Kit actually returned them, plus a raw
    // (ungated -- see debugSampleRawMaskConfidence's doc comment)
    // confidence sample at every landmark ML Kit reported, regardless of
    // likelihood. This is the number to check against maskMatchesImageSpace
    // silently returning MaskTrustSignal.none: if the aspect ratios printed
    // here clearly don't match, that's the enableRawSizeMask coordinate-
    // space mismatch the solution doc warned about (a library-behavior
    // fact, not a bug); if they do match but a landmark you can see sitting
    // on background pixels still samples a high raw confidence, that's the
    // SelfieSegmentation model itself being fooled by screenshot UI chrome
    // (also a model limitation, not our code); only a raw confidence that
    // looks wrong for what the sampled pixel actually shows points at a bug
    // in our own coordinate math.
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

        // Debug-only: the subject bounding box sampleMaskTrust now checks
        // landmarks against (landmark_trust_classifier.dart), plus which
        // of the raw points fall outside it. Compare this against the
        // knee/ankle x,y in the "raw pose" line above: if a landmark that
        // sampled high local confidence turns out to be outside this box,
        // the new box check should catch it next run; if it's inside the
        // box too, the box check won't help and a different signal is
        // needed.
        final box = computeSubjectBoundingBox(
          mask: mask,
          imageWidth: imageWidth.round(),
          imageHeight: imageHeight.round(),
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

    final likelihoodGate = PoseLandmarkGate.fromLandmarks(landmarks: landmarks);

    var maskSignal = MaskTrustSignal.none;
    if (mask != null && imageWidth != null && imageHeight != null) {
      maskSignal = sampleMaskTrust(
        points: likelihoodGate.confidentPoints,
        mask: mask,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
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

    // Phase 2 (REFERENCE_TRUST_FILTER_SOLUTION.md): if enough extremities
    // are still untrusted after Phase 0/1, and there's a mask and a decoded
    // bitmap to crop, try recovering them from a second detection pass on
    // just the subject's bounding box -- see
    // reference_photo_crop_redetect.dart. A photo with no mask (e.g.
    // segmentation itself failed) or no decoded bitmap (decode failed)
    // simply skips this and keeps the Phase 0/1 result, same as before.
    if (mask != null && decodedResult.decoded != null) {
      final outcome = await reconcileWithCrop(
        originalGate: gate,
        decoded: decodedResult.decoded!,
        mask: mask,
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

      // Sign convention: positive means the left shoulder sits lower
      // (larger y) than the right. Normalized by shoulder-width so it
      // stays scale-invariant regardless of subject distance.
      shoulderBalanceRatio = scale > 0
          ? (leftShoulder.y - rightShoulder.y) / scale
          : null;

      // z is ML Kit's experimental depth value (same unit as x/y, origin
      // at the hip, "less accurate than x and y" per Google's docs). This
      // mirrors the shoulderAngleDegrees formula above but swaps y for z,
      // so a rotated torso (one shoulder closer to camera) reads as a
      // nonzero angle. Left/right sign is unverified on a physical device
      // — see ReferenceComparisonEngine._bodyYawDirectionIsMirrored.
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
        // Shoulder width relative to torso height: bigger means broader/
        // more spread shoulders, smaller means narrower/hunched,
        // independent of the subject's distance from camera.
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
    // Bug fix, confirmed via a real device log on the Vogue test photo:
    // enableRawSizeMask: true was returning the segmentation model's raw
    // internal output resolution (a fixed 256x256 square) with no relation
    // to the actual photo's dimensions (1080x2372, aspect 0.455 vs. the
    // mask's 1.000) -- not "the image's resolution, just computed via a
    // faster path" as the option name suggests. maskMatchesImageSpace
    // correctly detected this and disabled mask-based trust entirely
    // (bypassed: true) rather than sampling garbage, but that only proved
    // the bug existed -- it didn't fix it, since Phase 0/1's likelihood +
    // geometry alone can't reject a hallucinated-but-anatomically-
    // plausible skeleton (see REFERENCE_TRUST_FILTER_SOLUTION.md). Raw
    // mode exists to skip ML Kit's own resize-to-image-dimensions step for
    // per-frame latency; this analyzer runs once per reference photo, not
    // per frame, so there's no latency reason to pay that coordinate-
    // mapping complexity here. Removed -- ML Kit now returns a mask
    // already scaled to the input image's own dimensions.
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
    img.Image? decoded;
    double? imageWidth;
    double? imageHeight;
    try {
      final bytes = await File(imagePath).readAsBytes();
      if (kDebugMode) {
        // LIMITATIONS_AND_ROADMAP.md §"Possible non-determinism": the same
        // source photo, picked twice, was once seen to produce two
        // different outcomes. Before chasing a provider race, check
        // whether the two picks are even the same bytes -- image_picker
        // frequently writes a fresh temp path per pick, sometimes with
        // re-encoding, even for the identical gallery asset. Log a cheap
        // fingerprint alongside the raw detection output on each pass; if
        // two repeated picks show different fingerprints, this was never a
        // state bug.
        debugPrint(
          'ReferenceImageAnalyzer analyze: path=$imagePath '
          'bytes=${bytes.length} fingerprint=${_cheapFingerprint(bytes)}',
        );
      }
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

  /// Not a real hash — a cheap rolling checksum over the byte length plus a
  /// sparse sample of the file, only meant to tell "same picked file twice"
  /// apart from "different file, same photo" in a debug log. Don't use this
  /// for anything that needs actual collision resistance.
  String _cheapFingerprint(List<int> bytes) {
    var acc = bytes.length;
    final step = bytes.length > 4096 ? bytes.length ~/ 4096 : 1;
    for (var i = 0; i < bytes.length; i += step) {
      acc = (acc * 31 + bytes[i]) & 0x7fffffff;
    }
    return acc.toRadixString(16);
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
