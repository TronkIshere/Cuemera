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

  final confidence = <int, double>{};
  final failed = <int>{};
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
    if (value < confidenceThreshold) failed.add(i);
  }

  if (sampled == 0) return MaskTrustSignal.none;

  return MaskTrustSignal(
    failedIndices: failed,
    confidence: confidence,
    bypassed: failed.length / sampled > bypassFraction,
  );
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
