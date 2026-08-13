// features/reference_photo/services/landmark_trust_classifier.dart
import 'dart:ui' show Offset;

import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';

import '../../../core/pose/landmark_gate.dart';

const double kMaskConfidenceThreshold = 0.5;
const int kMaskSampleRadius = 2;
const double kMaskBypassFraction = 0.6;
const double kMaskAspectTolerance = 0.02;

bool maskMatchesImageSpace({
  required SegmentationMask mask,
  required double imageWidth,
  required double imageHeight,
  double tolerance = kMaskAspectTolerance,
}) {
  if (mask.width <= 0 || mask.height <= 0) return false;
  if (imageWidth <= 0 || imageHeight <= 0) return false;
  final maskAspect = mask.width / mask.height;
  final imageAspect = imageWidth / imageHeight;
  return (maskAspect - imageAspect).abs() / imageAspect <= tolerance;
}

MaskTrustSignal sampleMaskTrust({
  required List<Offset?> points,
  required SegmentationMask mask,
  required double imageWidth,
  required double imageHeight,
  double confidenceThreshold = kMaskConfidenceThreshold,
  int sampleRadius = kMaskSampleRadius,
  double bypassFraction = kMaskBypassFraction,
}) {
  if (!maskMatchesImageSpace(
    mask: mask,
    imageWidth: imageWidth,
    imageHeight: imageHeight,
  )) {
    return MaskTrustSignal.none;
  }

  // Added after a real test photo (a torso-only Instagram screenshot with
  // no legs actually pictured) showed leftKnee/rightKnee sampling HIGH
  // local mask confidence (0.7-1.0) despite being hallucinated -- the
  // model's own foreground silhouette (clothing/torso) apparently extends
  // down far enough that the hallucinated knee position still lands on
  // real "this is the subject" pixels. A local sample can only ever
  // answer "is this pixel part of the person", never "is this landmark
  // the joint it claims to be" -- those are different questions, and no
  // amount of tuning confidenceThreshold closes that gap. The subject's
  // overall bounding box (already computed for Phase 2's crop step) is an
  // independent, coarser signal: a landmark outside the box cannot be
  // real regardless of what its own local sample says, since it's outside
  // where ML Kit's own segmentation model puts the subject at all.
  //
  // Unverified against the specific case that motivated it -- this may or
  // may not actually catch that knee, since a torso/clothing silhouette
  // that extends down far enough to fool a local sample could just as
  // easily extend down far enough to be inside the bounding box too. Log
  // and check on the next test rather than assume this closes the gap.
  final box = computeSubjectBoundingBox(
    mask: mask,
    imageWidth: imageWidth.round(),
    imageHeight: imageHeight.round(),
  );

  final confidence = <int, double>{};
  final failed = <int>{};
  final outsideBox = <int>{};
  var sampled = 0;

  for (var i = 0; i < points.length; i++) {
    final point = points[i];
    if (point == null) continue;
    sampled++;
    final value = _sampleMaskConfidence(
      mask: mask,
      x: point.dx,
      y: point.dy,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      sampleRadius: sampleRadius,
    );
    confidence[i] = value;
    var isFailed = value < confidenceThreshold;
    if (box != null && !_pointWithinBox(point, box)) {
      isFailed = true;
      outsideBox.add(i);
    }
    if (isFailed) failed.add(i);
  }

  if (sampled == 0) return MaskTrustSignal.none;

  return MaskTrustSignal(
    failedIndices: failed,
    confidence: confidence,
    bypassed: failed.length / sampled > bypassFraction,
  );
}

bool _pointWithinBox(Offset point, SubjectBoundingBox box) {
  return point.dx >= box.left &&
      point.dx <= box.left + box.width &&
      point.dy >= box.top &&
      point.dy <= box.top + box.height;
}

double _sampleMaskConfidence({
  required SegmentationMask mask,
  required double x,
  required double y,
  required double imageWidth,
  required double imageHeight,
  required int sampleRadius,
}) {
  final maskX = (x / imageWidth * mask.width).round();
  final maskY = (y / imageHeight * mask.height).round();

  var total = 0.0;
  var count = 0;
  for (var dy = -sampleRadius; dy <= sampleRadius; dy++) {
    for (var dx = -sampleRadius; dx <= sampleRadius; dx++) {
      final sx = maskX + dx;
      final sy = maskY + dy;
      if (sx < 0 || sx >= mask.width || sy < 0 || sy >= mask.height) continue;
      final index = sy * mask.width + sx;
      if (index < 0 || index >= mask.confidences.length) continue;
      total += mask.confidences[index];
      count++;
    }
  }
  return count == 0 ? 0.0 : total / count;
}

/// Debug-only. Samples mask confidence at every point in [points] that is
/// non-null, with no likelihood filtering, no bypass logic, and no trust
/// decision attached -- exists purely so a debug log can show what the
/// segmentation model itself reported at a given pixel, independent of any
/// of our own gating code (kMinLandmarkLikelihood, maskBypassFraction,
/// findSuspectLandmarks, etc). Never call this from anything that decides
/// trust; it exists to let a log line be compared against the photo by eye,
/// to tell "the model itself was fooled by this pixel" (a library/model
/// limitation -- SelfieSegmentation isn't trained on screenshot UI chrome)
/// apart from "our own sampling/coordinate math is wrong" (a bug in this
/// codebase, not in ML Kit).
Map<int, double> debugSampleRawMaskConfidence({
  required List<Offset?> points,
  required SegmentationMask mask,
  required double imageWidth,
  required double imageHeight,
  int sampleRadius = kMaskSampleRadius,
}) {
  final result = <int, double>{};
  for (var i = 0; i < points.length; i++) {
    final point = points[i];
    if (point == null) continue;
    result[i] = _sampleMaskConfidence(
      mask: mask,
      x: point.dx,
      y: point.dy,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      sampleRadius: sampleRadius,
    );
  }
  return result;
}

class SubjectBoundingBox {
  final int left;
  final int top;
  final int width;
  final int height;

  const SubjectBoundingBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });
}

SubjectBoundingBox? computeSubjectBoundingBox({
  required SegmentationMask mask,
  required int imageWidth,
  required int imageHeight,
  double confidenceThreshold = kMaskConfidenceThreshold,
  double paddingFraction = 0.08,
}) {
  var minX = mask.width;
  var maxX = -1;
  var minY = mask.height;
  var maxY = -1;

  for (var y = 0; y < mask.height; y++) {
    for (var x = 0; x < mask.width; x++) {
      if (mask.confidences[y * mask.width + x] >= confidenceThreshold) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }

  if (maxX < minX || maxY < minY) return null;

  final scaleX = imageWidth / mask.width;
  final scaleY = imageHeight / mask.height;
  final padX = (maxX - minX) * scaleX * paddingFraction;
  final padY = (maxY - minY) * scaleY * paddingFraction;

  final left = ((minX * scaleX) - padX).clamp(0, imageWidth.toDouble()).round();
  final top = ((minY * scaleY) - padY).clamp(0, imageHeight.toDouble()).round();
  final right = ((maxX * scaleX) + padX)
      .clamp(0, imageWidth.toDouble())
      .round();
  final bottom = ((maxY * scaleY) + padY)
      .clamp(0, imageHeight.toDouble())
      .round();

  return SubjectBoundingBox(
    left: left,
    top: top,
    width: right - left,
    height: bottom - top,
  );
}
