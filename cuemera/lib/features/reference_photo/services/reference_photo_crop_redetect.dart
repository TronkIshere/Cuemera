// features/reference_photo/services/reference_photo_crop_redetect.dart
//
// Phase 2 of REFERENCE_TRUST_FILTER_SOLUTION.md: crop the reference photo to
// the segmentation mask's subject bounding box, then re-run pose detection
// on the crop alone. Only attempted when Phase 0/Phase 1 (landmark_gate.dart,
// landmark_trust_classifier.dart) leave enough extremities untrusted -- the
// crop removes surrounding UI chrome from what the detector sees, rather
// than cleaning up a hallucinated point after the fact.
//
// Not device-verified. shouldAttemptCropRedetect's trigger fraction and the
// merge policy below are first-pass judgement calls, not tuned against the
// five failing screenshots referenced in LIMITATIONS_AND_ROADMAP.md -- watch
// the kDebugMode log this emits against those before trusting it in
// production.

import 'dart:io';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';
import 'package:image/image.dart' as img;

import '../../../core/pose/landmark_gate.dart';
import '../../../core/services/error_reporting_service.dart';
import 'landmark_trust_classifier.dart';

const List<PoseLandmarkType> _extremityTypes = [
  PoseLandmarkType.leftElbow,
  PoseLandmarkType.rightElbow,
  PoseLandmarkType.leftWrist,
  PoseLandmarkType.rightWrist,
  PoseLandmarkType.leftKnee,
  PoseLandmarkType.rightKnee,
  PoseLandmarkType.leftAnkle,
  PoseLandmarkType.rightAnkle,
];

bool shouldAttemptCropRedetect(PoseLandmarkGate gate) {
  var untrusted = 0;
  for (final type in _extremityTypes) {
    if (!gate.isTrustedType(type)) untrusted++;
  }
  return untrusted >= (_extremityTypes.length / 3).ceil();
}

class CropRedetectOutcome {
  final PoseLandmarkGate gate;
  final bool attempted;
  final bool changedAnyLandmark;

  const CropRedetectOutcome({
    required this.gate,
    required this.attempted,
    required this.changedAnyLandmark,
  });
}

Future<CropRedetectOutcome> reconcileWithCrop({
  required PoseLandmarkGate originalGate,
  required img.Image decoded,
  required SegmentationMask mask,
}) async {
  if (!shouldAttemptCropRedetect(originalGate)) {
    return CropRedetectOutcome(
      gate: originalGate,
      attempted: false,
      changedAnyLandmark: false,
    );
  }

  final box = computeSubjectBoundingBox(
    mask: mask,
    imageWidth: decoded.width,
    imageHeight: decoded.height,
  );
  if (box == null || box.width <= 0 || box.height <= 0) {
    // No usable foreground region to crop to -- e.g. estimateNegativeSpace
    // would also read this mask as all-background. Nothing for Phase 2 to
    // work with.
    return CropRedetectOutcome(
      gate: originalGate,
      attempted: false,
      changedAnyLandmark: false,
    );
  }

  String? tempPath;
  Map<PoseLandmarkType, PoseLandmark>? cropLandmarks;
  final poseDetector = PoseDetector(options: PoseDetectorOptions());
  try {
    final cropped = img.copyCrop(
      decoded,
      x: box.left,
      y: box.top,
      width: box.width,
      height: box.height,
    );
    final bytes = img.encodeJpg(cropped, quality: 92);
    tempPath =
        '${Directory.systemTemp.path}/'
        'cuemera_crop_redetect_${DateTime.now().microsecondsSinceEpoch}.jpg';
    await File(tempPath).writeAsBytes(bytes);

    final poses = await poseDetector.processImage(
      InputImage.fromFilePath(tempPath),
    );
    if (poses.isNotEmpty) cropLandmarks = poses.first.landmarks;
  } catch (e, st) {
    ErrorReportingService.instance.report(
      e,
      st,
      context: 'ReferenceImageAnalyzer: crop re-detection',
    );
  } finally {
    await poseDetector.close();
    if (tempPath != null) {
      try {
        final file = File(tempPath);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Best-effort cleanup; a stray temp file isn't worth surfacing.
      }
    }
  }

  if (cropLandmarks == null || cropLandmarks.isEmpty) {
    return CropRedetectOutcome(
      gate: originalGate,
      attempted: true,
      changedAnyLandmark: false,
    );
  }

  if (kDebugMode) {
    final lines = <String>[];
    for (var i = 0; i < kGatedLandmarkOrder.length; i++) {
      final landmark = cropLandmarks[kGatedLandmarkOrder[i]];
      lines.add(
        landmark == null
            ? '${kGatedLandmarkNames[i]}=absent'
            : '${kGatedLandmarkNames[i]}='
                  'x=${landmark.x.toStringAsFixed(1)},'
                  'y=${landmark.y.toStringAsFixed(1)},'
                  'likelihood=${landmark.likelihood.toStringAsFixed(3)}',
      );
    }
    debugPrint(
      'ReferenceImageAnalyzer raw crop-redetect pose (crop-local coords, '
      'crop=${box.width}x${box.height}): ${lines.join(' ')}',
    );
  }

  final shifted = <PoseLandmarkType, RawLandmark>{
    for (final entry in cropLandmarks.entries)
      entry.key: RawLandmark(
        x: entry.value.x + box.left,
        y: entry.value.y + box.top,
        z: entry.value.z,
        likelihood: entry.value.likelihood,
      ),
  };

  if (kDebugMode) {
    final shiftedPoints = <Offset?>[
      for (final type in kGatedLandmarkOrder)
        shifted[type] != null
            ? Offset(shifted[type]!.x, shifted[type]!.y)
            : null,
    ];
    final rawConfidence = debugSampleRawMaskConfidence(
      points: shiftedPoints,
      mask: mask,
      imageWidth: decoded.width.toDouble(),
      imageHeight: decoded.height.toDouble(),
    );
    final lines = [
      for (final entry in rawConfidence.entries)
        '${kGatedLandmarkNames[entry.key]}=${entry.value.toStringAsFixed(3)}',
    ];
    debugPrint(
      'ReferenceImageAnalyzer raw crop-redetect mask confidence '
      '(shifted to original-photo coords): ${lines.join(' ')}',
    );
  }

  final likelihoodCropGate = PoseLandmarkGate.fromRawLandmarks(shifted);
  final cropMaskSignal = sampleMaskTrust(
    points: likelihoodCropGate.confidentPoints,
    mask: mask,
    imageWidth: decoded.width.toDouble(),
    imageHeight: decoded.height.toDouble(),
  );
  final cropGate = cropMaskSignal.bypassed
      ? likelihoodCropGate
      : PoseLandmarkGate.fromRawLandmarks(shifted, maskSignal: cropMaskSignal);

  final merged = <PoseLandmarkType, RawLandmark>{};
  final recovered = <PoseLandmarkType>[];
  for (final type in kGatedLandmarkOrder) {
    final originalValue = originalGate.landmark(type);
    if (originalValue != null) {
      merged[type] = originalValue;
      continue;
    }
    if (cropGate.isTrustedType(type)) {
      final cropValue = shifted[type];
      if (cropValue != null) {
        merged[type] = cropValue;
        recovered.add(type);
      }
    }
  }

  if (recovered.isEmpty) {
    return CropRedetectOutcome(
      gate: originalGate,
      attempted: true,
      changedAnyLandmark: false,
    );
  }

  final likelihoodMergedGate = PoseLandmarkGate.fromRawLandmarks(merged);
  final mergedMaskSignal = sampleMaskTrust(
    points: likelihoodMergedGate.confidentPoints,
    mask: mask,
    imageWidth: decoded.width.toDouble(),
    imageHeight: decoded.height.toDouble(),
  );
  final mergedGate = mergedMaskSignal.bypassed
      ? likelihoodMergedGate
      : PoseLandmarkGate.fromRawLandmarks(merged, maskSignal: mergedMaskSignal);

  final confirmedRecovered = recovered
      .where((t) => mergedGate.isTrustedType(t))
      .toList();

  if (kDebugMode) {
    debugPrint(
      'ReferenceImageAnalyzer crop-redetect: box=(${box.left},${box.top},'
      '${box.width}x${box.height}) candidateRecovered=${recovered.map((t) => t.name).toList()} '
      'confirmedRecovered=${confirmedRecovered.map((t) => t.name).toList()}',
    );
  }

  return CropRedetectOutcome(
    gate: mergedGate,
    attempted: true,
    changedAnyLandmark: confirmedRecovered.isNotEmpty,
  );
}
