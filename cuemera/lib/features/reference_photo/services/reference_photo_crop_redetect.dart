// features/reference_photo/services/reference_photo_crop_redetect.dart

import 'dart:io';

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

const double kContradictionCropLikelihoodCeiling = 0.3;
const double kContradictionMaskConfidenceCeiling = 0.1;

bool shouldAttemptCropRedetect(PoseLandmarkGate gate) {
  var untrusted = 0;
  for (final type in _extremityTypes) {
    if (!gate.isTrustedType(type)) untrusted++;
  }
  return untrusted >= (_extremityTypes.length / 3).ceil();
}

enum LandmarkDecision { keep, reject, recover, absent }

class LandmarkVerification {
  final PoseLandmarkType type;
  final LandmarkDecision decision;
  final double? originalLikelihood;
  final double? cropLikelihood;
  final bool cropObserved;
  final bool cropOutOfFrame;
  final double? maskConfidence;
  final bool geometrySuspect;

  const LandmarkVerification({
    required this.type,
    required this.decision,
    required this.originalLikelihood,
    required this.cropLikelihood,
    required this.cropObserved,
    required this.cropOutOfFrame,
    required this.maskConfidence,
    required this.geometrySuspect,
  });
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

LandmarkVerification _verifyLandmark({
  required PoseLandmarkType type,
  required PoseLandmarkGate originalGate,
  required Map<PoseLandmarkType, PoseLandmark> cropLandmarks,
  required SubjectBoundingBox box,
}) {
  final index = PoseLandmarkGate.indexOf(type);
  final original = originalGate.confidentLandmarks[type];
  final cropLandmark = cropLandmarks[type];

  final cropOutOfFrame =
      cropLandmark != null &&
      (cropLandmark.x < 0 ||
          cropLandmark.x > box.width ||
          cropLandmark.y < 0 ||
          cropLandmark.y > box.height);

  final cropLikelihood = cropLandmark?.likelihood;
  final cropObserved =
      cropLandmark != null &&
      !cropOutOfFrame &&
      cropLikelihood != null &&
      cropLikelihood >= kMinLandmarkLikelihood;

  final maskConfidence = originalGate.maskSignal.confidence[index];
  final geometrySuspect = originalGate.suspectIndices.contains(index);

  if (original == null) {
    return LandmarkVerification(
      type: type,
      decision: cropObserved
          ? LandmarkDecision.recover
          : LandmarkDecision.absent,
      originalLikelihood: null,
      cropLikelihood: cropLikelihood,
      cropObserved: cropObserved,
      cropOutOfFrame: cropOutOfFrame,
      maskConfidence: maskConfidence,
      geometrySuspect: geometrySuspect,
    );
  }

  final cropUnobserved =
      cropLandmark == null ||
      (cropLikelihood != null &&
          cropLikelihood < kContradictionCropLikelihoodCeiling);
  final maskVeryLow =
      maskConfidence != null &&
      maskConfidence < kContradictionMaskConfidenceCeiling;
  final strongContradiction = maskVeryLow && (cropOutOfFrame || cropUnobserved);

  return LandmarkVerification(
    type: type,
    decision: strongContradiction
        ? LandmarkDecision.reject
        : LandmarkDecision.keep,
    originalLikelihood: original.likelihood,
    cropLikelihood: cropLikelihood,
    cropObserved: cropObserved,
    cropOutOfFrame: cropOutOfFrame,
    maskConfidence: maskConfidence,
    geometrySuspect: geometrySuspect,
  );
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
    return CropRedetectOutcome(
      gate: originalGate,
      attempted: false,
      changedAnyLandmark: false,
    );
  }

  String? tempPath;
  Map<PoseLandmarkType, PoseLandmark>? cropLandmarks;
  final poseDetector = PoseDetector(
    options: PoseDetectorOptions(model: PoseDetectionModel.accurate),
  );
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
      } catch (_) {}
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

  final verifications = <LandmarkVerification>[];
  final verified = <PoseLandmarkType, RawLandmark>{};

  for (final type in kGatedLandmarkOrder) {
    final verification = _verifyLandmark(
      type: type,
      originalGate: originalGate,
      cropLandmarks: cropLandmarks,
      box: box,
    );
    verifications.add(verification);

    switch (verification.decision) {
      case LandmarkDecision.keep:
        verified[type] = originalGate.confidentLandmarks[type]!;
        break;
      case LandmarkDecision.recover:
        final cropLandmark = cropLandmarks[type]!;
        verified[type] = RawLandmark(
          x: cropLandmark.x + box.left,
          y: cropLandmark.y + box.top,
          z: cropLandmark.z,
          likelihood: cropLandmark.likelihood,
        );
        break;
      case LandmarkDecision.reject:
      case LandmarkDecision.absent:
        break;
    }
  }

  if (kDebugMode) {
    for (var i = 0; i < verifications.length; i++) {
      final v = verifications[i];
      debugPrint(
        'LANDMARK_VERIFY ${kGatedLandmarkNames[i]}: '
        'originalLikelihood=${v.originalLikelihood?.toStringAsFixed(3) ?? 'null'} '
        'cropLikelihood=${v.cropLikelihood?.toStringAsFixed(3) ?? 'null'} '
        'cropObserved=${v.cropObserved} '
        'cropOutOfFrame=${v.cropOutOfFrame} '
        'maskConfidence=${v.maskConfidence?.toStringAsFixed(3) ?? 'null'} '
        'geometrySuspect=${v.geometrySuspect} '
        'decision=${v.decision.name}',
      );
    }
  }

  final recovered = verifications
      .where((v) => v.decision == LandmarkDecision.recover)
      .map((v) => v.type)
      .toList();
  final rejected = verifications
      .where((v) => v.decision == LandmarkDecision.reject)
      .map((v) => v.type)
      .toList();

  if (recovered.isEmpty && rejected.isEmpty) {
    return CropRedetectOutcome(
      gate: originalGate,
      attempted: true,
      changedAnyLandmark: false,
    );
  }

  final likelihoodMergedGate = PoseLandmarkGate.fromRawLandmarks(verified);
  final mergedMaskSignal = sampleMaskTrust(
    points: likelihoodMergedGate.confidentPoints,
    mask: mask,
    imageWidth: decoded.width.toDouble(),
    imageHeight: decoded.height.toDouble(),
  );
  final mergedGate = mergedMaskSignal.bypassed
      ? likelihoodMergedGate
      : PoseLandmarkGate.fromRawLandmarks(
          verified,
          maskSignal: mergedMaskSignal,
        );

  if (kDebugMode) {
    final confirmedRecovered = recovered
        .where((t) => mergedGate.isTrustedType(t))
        .toList();
    debugPrint(
      'ReferenceImageAnalyzer crop-redetect: box=(${box.left},${box.top},'
      '${box.width}x${box.height}) recovered=${recovered.map((t) => t.name).toList()} '
      'rejected=${rejected.map((t) => t.name).toList()} '
      'confirmedRecovered=${confirmedRecovered.map((t) => t.name).toList()}',
    );
  }

  return CropRedetectOutcome(
    gate: mergedGate,
    attempted: true,
    changedAnyLandmark: true,
  );
}
