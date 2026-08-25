// features/scene_analysis/services/face_analyzer.dart
import 'dart:ui' show Offset;

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../../core/tracking/temporal_stabilizer.dart';
import '../../reference_photo/domain/comparison_math.dart';
import '../domain/models/subject_profile.dart';

const List<String> kFaceMetricKeys = [
  'faceAngleDegrees',
  'faceAngleXDegrees',
  'faceAngleZDegrees',
  'mouthOpenRatio',
  'eyeOpenRatio',
];

class FaceAnalyzer {
  FaceAnalyzer({StabilizerConfig? stabilizerConfig})
    : _config = stabilizerConfig ?? const StabilizerConfig() {
    _buildStabilizers();
  }

  static const bool enableEyeAndExpressionSignals = false;

  final StabilizerConfig _config;

  late CircularStabilizer _faceYawStabilizer;
  late CircularStabilizer _facePitchStabilizer;
  late CircularStabilizer _faceRollStabilizer;
  late TemporalStabilizer _mouthOpenStabilizer;
  late TemporalStabilizer _eyeOpenStabilizer;

  void _buildStabilizers() {
    _faceYawStabilizer = CircularStabilizer(_config);
    _facePitchStabilizer = CircularStabilizer(_config);
    _faceRollStabilizer = CircularStabilizer(_config);
    _mouthOpenStabilizer = TemporalStabilizer(_config);
    _eyeOpenStabilizer = TemporalStabilizer(_config);
  }

  void reset() => _buildStabilizers();

  StabilizedMetric? _resolveLinear(
    TemporalStabilizer stabilizer,
    double? raw,
    DateTime now,
  ) {
    final metric = stabilizer.update(raw, now);
    if (raw == null && metric.temporalConfidence == 0) return null;
    return metric;
  }

  StabilizedMetric? _resolveCircular(
    CircularStabilizer stabilizer,
    double? raw,
    DateTime now,
  ) {
    final metric = stabilizer.update(raw, now);
    if (raw == null && metric.temporalConfidence == 0) return null;
    return metric;
  }

  Map<String, double>? _mergeConfidence(
    Map<String, double>? previous,
    Map<String, double> faceConfidence,
  ) {
    final merged = <String, double>{};
    if (previous != null) {
      for (final entry in previous.entries) {
        if (!kFaceMetricKeys.contains(entry.key))
          merged[entry.key] = entry.value;
      }
    }
    merged.addAll(faceConfidence);
    return merged.isEmpty ? null : merged;
  }

  Map<String, bool> _mergeEligibility(
    Map<String, bool>? previous,
    Map<String, StabilizedMetric?> metrics,
  ) {
    final merged = <String, bool>{};
    if (previous != null) {
      for (final entry in previous.entries) {
        if (!kFaceMetricKeys.contains(entry.key))
          merged[entry.key] = entry.value;
      }
    }
    for (final entry in metrics.entries) {
      merged[entry.key] = entry.value?.isEligible ?? false;
    }
    return merged;
  }

  SubjectProfile _apply(
    SubjectProfile previous, {
    required double? rawYaw,
    required double? rawPitch,
    required double? rawRoll,
    required double? rawMouthOpen,
    required double? rawEyeOpen,
    required bool? eyesOpen,
    required String? expression,
    required DateTime at,
  }) {
    final yawMetric = _resolveCircular(_faceYawStabilizer, rawYaw, at);
    final pitchMetric = _resolveCircular(_facePitchStabilizer, rawPitch, at);
    final rollMetric = _resolveCircular(_faceRollStabilizer, rawRoll, at);
    final mouthMetric = _resolveLinear(_mouthOpenStabilizer, rawMouthOpen, at);
    final eyeMetric = _resolveLinear(_eyeOpenStabilizer, rawEyeOpen, at);

    final metrics = <String, StabilizedMetric?>{
      'faceAngleDegrees': yawMetric,
      'faceAngleXDegrees': pitchMetric,
      'faceAngleZDegrees': rollMetric,
      'mouthOpenRatio': mouthMetric,
      'eyeOpenRatio': eyeMetric,
    };

    final confidence = <String, double>{
      for (final entry in metrics.entries)
        if (entry.value != null)
          entry.key: entry.value!.temporalConfidence.clamp(0.0, 1.0),
    };

    return previous.copyWith(
      faceAngleDegrees: yawMetric?.value,
      faceAngleXDegrees: pitchMetric?.value,
      faceAngleZDegrees: rollMetric?.value,
      mouthOpenRatio: mouthMetric?.value,
      eyeOpenRatio: eyeMetric?.value,
      eyesOpen: eyesOpen,
      expression: expression,
      metricConfidence: _mergeConfidence(previous.metricConfidence, confidence),
      metricTemporalEligibility: _mergeEligibility(
        previous.metricTemporalEligibility,
        metrics,
      ),
      timestamp: at,
    );
  }

  SubjectProfile analyzeFace(
    dynamic mlkitFaceResult,
    SubjectProfile previous, {
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final faces = mlkitFaceResult as List<Face>?;

    if (faces == null || faces.isEmpty) {
      return _apply(
        previous,
        rawYaw: null,
        rawPitch: null,
        rawRoll: null,
        rawMouthOpen: null,
        rawEyeOpen: null,
        eyesOpen: null,
        expression: null,
        at: at,
      );
    }

    final face = faces.first;

    bool? eyesOpen;
    if (enableEyeAndExpressionSignals) {
      final leftOpen = face.leftEyeOpenProbability;
      final rightOpen = face.rightEyeOpenProbability;
      if (leftOpen != null && rightOpen != null) {
        eyesOpen = leftOpen > 0.5 && rightOpen > 0.5;
      }
    }

    List<Offset>? contourPoints(FaceContourType type) {
      final contour = face.contours[type];
      final points = contour?.points;
      if (points == null || points.isEmpty) return null;
      return points.map((p) => Offset(p.x.toDouble(), p.y.toDouble())).toList();
    }

    final lipPoints = <Offset>[
      ...?contourPoints(FaceContourType.upperLipTop),
      ...?contourPoints(FaceContourType.upperLipBottom),
      ...?contourPoints(FaceContourType.lowerLipTop),
      ...?contourPoints(FaceContourType.lowerLipBottom),
    ];
    final mouthOpenRatio = ComparisonMath.boundingBoxAspectRatio(
      lipPoints.isEmpty ? null : lipPoints,
    );

    final leftEyeRatio = ComparisonMath.boundingBoxAspectRatio(
      contourPoints(FaceContourType.leftEye),
    );
    final rightEyeRatio = ComparisonMath.boundingBoxAspectRatio(
      contourPoints(FaceContourType.rightEye),
    );
    final eyeOpenRatio = (leftEyeRatio != null && rightEyeRatio != null)
        ? (leftEyeRatio + rightEyeRatio) / 2
        : (leftEyeRatio ?? rightEyeRatio);

    return _apply(
      previous,
      rawYaw: face.headEulerAngleY,
      rawPitch: face.headEulerAngleX,
      rawRoll: face.headEulerAngleZ,
      rawMouthOpen: mouthOpenRatio,
      rawEyeOpen: eyeOpenRatio,
      eyesOpen: eyesOpen,
      expression: null,
      at: at,
    );
  }
}
