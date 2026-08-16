// core/pose/landmark_gate.dart
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'landmark_trust_model.dart';

const double kMinLandmarkLikelihood = 0.6;

/// Plain (x, y, z, likelihood) tuple, independent of ML Kit's [PoseLandmark]
/// so a landmark recovered by [reconcileWithCrop] (which shifts a
/// crop-local detection back into the original photo's coordinate space)
/// can be represented the same way as a landmark ML Kit detected directly.
class RawLandmark {
  final double x;
  final double y;
  final double z;
  final double likelihood;

  const RawLandmark({
    required this.x,
    required this.y,
    required this.z,
    required this.likelihood,
  });

  factory RawLandmark.fromPoseLandmark(PoseLandmark landmark) => RawLandmark(
    x: landmark.x,
    y: landmark.y,
    z: landmark.z,
    likelihood: landmark.likelihood,
  );
}

const int kNose = 0;
const int kLeftEye = 1;
const int kRightEye = 2;
const int kLeftShoulder = 3;
const int kRightShoulder = 4;
const int kLeftElbow = 5;
const int kRightElbow = 6;
const int kLeftWrist = 7;
const int kRightWrist = 8;
const int kLeftHip = 9;
const int kRightHip = 10;
const int kLeftKnee = 11;
const int kRightKnee = 12;
const int kLeftAnkle = 13;
const int kRightAnkle = 14;

const List<PoseLandmarkType> kGatedLandmarkOrder = [
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

const List<String> kGatedLandmarkNames = [
  'nose',
  'leftEye',
  'rightEye',
  'leftShoulder',
  'rightShoulder',
  'leftElbow',
  'rightElbow',
  'leftWrist',
  'rightWrist',
  'leftHip',
  'rightHip',
  'leftKnee',
  'rightKnee',
  'leftAnkle',
  'rightAnkle',
];

const List<List<int>> kLimbChains = [
  [kLeftShoulder, kLeftElbow, kLeftWrist],
  [kRightShoulder, kRightElbow, kRightWrist],
  [kLeftHip, kLeftKnee, kLeftAnkle],
  [kRightHip, kRightKnee, kRightAnkle],
];

const List<List<int>> _mirroredChainIndexPairs = [
  [0, 1],
  [2, 3],
];

const List<List<int>> _symmetricPairs = [
  [kLeftElbow, kRightElbow],
  [kLeftWrist, kRightWrist],
  [kLeftKnee, kRightKnee],
  [kLeftAnkle, kRightAnkle],
];

const double _torsoHeightBodyUnits = 1.0;
const double _torsoSideBodyUnits = 1.02;
const double _shoulderWidthBodyUnits = 0.85;
const double _hipWidthBodyUnits = 0.65;
const double _eyeSpanBodyUnits = 0.15;

const Map<int, double> _maxSegmentBodyUnits = {
  kLeftElbow: 0.75,
  kRightElbow: 0.75,
  kLeftWrist: 0.72,
  kRightWrist: 0.72,
  kLeftKnee: 1.15,
  kRightKnee: 1.15,
  kLeftAnkle: 1.05,
  kRightAnkle: 1.05,
};

const double _bodyUnitOutlierCeilingMultiplier = 2.0;
const double _segmentLengthSafetyMultiplier = 1.5;
const double _definitiveSegmentLengthMultiplier = 2.0;
const double _minSymmetricSeparationBodyUnits = 0.12;
const double _shallowOppositeSideIntrusionBodyUnits = 0.12;
const double _deepOppositeSideIntrusionBodyUnits = 0.45;
const double _maxBilateralSegmentLengthRatio = 2.5;
const double _maxSuspectBodyLandmarkFraction = 0.6;

const int _excessiveSegmentLengthEvidence = 2;
const int _shallowIntrusionEvidence = 1;
const int _deepIntrusionEvidence = 2;
const int _mirroredIntrusionEvidenceRelief = 1;
const int _symmetricCollapseEvidence = 1;
const int _bilateralLengthMismatchEvidence = 1;
const int _suspectEvidenceThreshold = 2;

Offset? usablePointAt(List<Offset?> pose, int index) {
  if (index < 0 || index >= pose.length) return null;
  final point = pose[index];
  if (point == null || !point.dx.isFinite || !point.dy.isFinite) return null;
  return point;
}

double? poseBodyUnit(List<Offset?> pose) {
  final candidates = <double>[];
  void addCandidate(double measured, double bodyUnits) {
    if (measured > 0) candidates.add(measured / bodyUnits);
  }

  final leftShoulder = usablePointAt(pose, kLeftShoulder);
  final rightShoulder = usablePointAt(pose, kRightShoulder);
  final leftHip = usablePointAt(pose, kLeftHip);
  final rightHip = usablePointAt(pose, kRightHip);
  final leftEye = usablePointAt(pose, kLeftEye);
  final rightEye = usablePointAt(pose, kRightEye);

  if (leftShoulder != null && rightShoulder != null) {
    addCandidate(
      (rightShoulder - leftShoulder).distance,
      _shoulderWidthBodyUnits,
    );
  }
  if (leftHip != null && rightHip != null) {
    addCandidate((rightHip - leftHip).distance, _hipWidthBodyUnits);
  }
  if (leftShoulder != null &&
      rightShoulder != null &&
      leftHip != null &&
      rightHip != null) {
    final shoulderMid = (leftShoulder + rightShoulder) / 2;
    final hipMid = (leftHip + rightHip) / 2;
    addCandidate((hipMid - shoulderMid).distance, _torsoHeightBodyUnits);
  }
  if (leftShoulder != null && leftHip != null) {
    addCandidate((leftHip - leftShoulder).distance, _torsoSideBodyUnits);
  }
  if (rightShoulder != null && rightHip != null) {
    addCandidate((rightHip - rightShoulder).distance, _torsoSideBodyUnits);
  }
  if (leftEye != null && rightEye != null) {
    addCandidate((rightEye - leftEye).distance, _eyeSpanBodyUnits);
  }

  if (candidates.isEmpty) return null;

  candidates.sort();
  final median = candidates[candidates.length ~/ 2];
  final ceiling = median * _bodyUnitOutlierCeilingMultiplier;
  var largestPlausible = 0.0;
  for (final candidate in candidates) {
    if (candidate <= ceiling && candidate > largestPlausible) {
      largestPlausible = candidate;
    }
  }
  return largestPlausible > 0 ? largestPlausible : median;
}

double? poseTorsoCenterX(List<Offset?> pose) {
  final leftShoulder = usablePointAt(pose, kLeftShoulder);
  final rightShoulder = usablePointAt(pose, kRightShoulder);
  if (leftShoulder != null && rightShoulder != null) {
    return (leftShoulder.dx + rightShoulder.dx) / 2;
  }

  final leftHip = usablePointAt(pose, kLeftHip);
  final rightHip = usablePointAt(pose, kRightHip);
  if (leftHip != null && rightHip != null) {
    return (leftHip.dx + rightHip.dx) / 2;
  }

  return null;
}

Set<int> findSuspectLandmarks(List<Offset?> pose) {
  final definitive = <int>{};
  for (var i = 0; i < pose.length; i++) {
    final point = pose[i];
    if (point != null && (!point.dx.isFinite || !point.dy.isFinite)) {
      definitive.add(i);
    }
  }

  final bodyUnit = poseBodyUnit(pose);
  if (bodyUnit == null) return definitive;

  final evidence = <int, int>{};
  void addEvidence(int index, int weight) {
    if (weight <= 0) return;
    evidence[index] = (evidence[index] ?? 0) + weight;
  }

  final segmentLengths = <int, double>{};
  for (final chain in kLimbChains) {
    for (var i = 0; i < chain.length - 1; i++) {
      final from = usablePointAt(pose, chain[i]);
      final to = usablePointAt(pose, chain[i + 1]);
      if (from == null || to == null) continue;

      final distalIndex = chain[i + 1];
      final length = (to - from).distance;
      segmentLengths[distalIndex] = length;

      final maxBodyUnits = _maxSegmentBodyUnits[distalIndex];
      if (maxBodyUnits == null) continue;
      final maxLength =
          maxBodyUnits * bodyUnit * _segmentLengthSafetyMultiplier;
      if (length > maxLength * _definitiveSegmentLengthMultiplier) {
        definitive.add(distalIndex);
      } else if (length > maxLength) {
        addEvidence(distalIndex, _excessiveSegmentLengthEvidence);
      }
    }
  }

  for (final pair in _symmetricPairs) {
    final first = usablePointAt(pose, pair[0]);
    final second = usablePointAt(pose, pair[1]);
    if (first == null || second == null) continue;

    if ((second - first).distance <
        bodyUnit * _minSymmetricSeparationBodyUnits) {
      addEvidence(pair[0], _symmetricCollapseEvidence);
      addEvidence(pair[1], _symmetricCollapseEvidence);
    }

    final firstLength = segmentLengths[pair[0]];
    final secondLength = segmentLengths[pair[1]];
    if (firstLength != null &&
        secondLength != null &&
        firstLength > 0 &&
        secondLength > 0) {
      final longer = math.max(firstLength, secondLength);
      final shorter = math.min(firstLength, secondLength);
      if (longer / shorter > _maxBilateralSegmentLengthRatio) {
        addEvidence(
          firstLength > secondLength ? pair[0] : pair[1],
          _bilateralLengthMismatchEvidence,
        );
      }
    }
  }

  final centerX = poseTorsoCenterX(pose);
  if (centerX != null) {
    final shallowMargin = bodyUnit * _shallowOppositeSideIntrusionBodyUnits;
    final deepMargin = bodyUnit * _deepOppositeSideIntrusionBodyUnits;

    Map<int, int> intrusionEvidence(List<int> chain, double centerX) {
      final isLeftChain = chain[0] == kLeftShoulder || chain[0] == kLeftHip;
      final result = <int, int>{};
      for (var i = 1; i < chain.length; i++) {
        final joint = usablePointAt(pose, chain[i]);
        if (joint == null) continue;
        final intrusion = isLeftChain ? centerX - joint.dx : joint.dx - centerX;
        if (intrusion <= shallowMargin) continue;
        result[chain[i]] = intrusion > deepMargin
            ? _deepIntrusionEvidence
            : _shallowIntrusionEvidence;
      }
      return result;
    }

    for (final indexPair in _mirroredChainIndexPairs) {
      final first = intrusionEvidence(kLimbChains[indexPair[0]], centerX);
      final second = intrusionEvidence(kLimbChains[indexPair[1]], centerX);
      final relief = first.isNotEmpty && second.isNotEmpty
          ? _mirroredIntrusionEvidenceRelief
          : 0;
      for (final side in [first, second]) {
        side.forEach((index, weight) => addEvidence(index, weight - relief));
      }
    }
  }

  final suspect = <int>{...definitive};
  evidence.forEach((index, score) {
    if (score >= _suspectEvidenceThreshold) suspect.add(index);
  });

  for (final chain in kLimbChains) {
    var cascading = false;
    for (final index in chain) {
      if (cascading) {
        suspect.add(index);
      } else if (suspect.contains(index)) {
        cascading = true;
      }
    }
  }

  var presentBodyLandmarks = 0;
  var suspectBodyLandmarks = 0;
  for (var i = kLeftShoulder; i <= kRightAnkle && i < pose.length; i++) {
    if (pose[i] == null) continue;
    presentBodyLandmarks++;
    if (suspect.contains(i)) suspectBodyLandmarks++;
  }
  if (presentBodyLandmarks > 0 &&
      suspectBodyLandmarks >
          presentBodyLandmarks * _maxSuspectBodyLandmarkFraction) {
    return definitive;
  }

  return suspect;
}

class MaskTrustSignal {
  final Set<int> failedIndices;
  final Map<int, double> confidence;
  final bool bypassed;

  const MaskTrustSignal({
    required this.failedIndices,
    required this.confidence,
    required this.bypassed,
  });

  static const MaskTrustSignal none = MaskTrustSignal(
    failedIndices: {},
    confidence: {},
    bypassed: true,
  );
}

class PoseLandmarkGate {
  final List<Offset?> confidentPoints;
  final Set<int> suspectIndices;
  final double? bodyUnit;
  final Map<PoseLandmarkType, RawLandmark> confidentLandmarks;
  final MaskTrustSignal maskSignal;
  final Map<int, RawLandmark> _allRawByIndex;
  final double _likelihoodFloor;

  const PoseLandmarkGate._({
    required this.confidentPoints,
    required this.suspectIndices,
    required this.bodyUnit,
    required this.confidentLandmarks,
    required this.maskSignal,
    Map<int, RawLandmark> allRawByIndex = const {},
    double likelihoodFloor = kMinLandmarkLikelihood,
  }) : _allRawByIndex = allRawByIndex,
       _likelihoodFloor = likelihoodFloor;

  factory PoseLandmarkGate.fromLandmarks({
    required Map<PoseLandmarkType, PoseLandmark> landmarks,
    double minLikelihood = kMinLandmarkLikelihood,
    required MaskTrustSignal maskSignal,
  }) {
    return PoseLandmarkGate.fromRawLandmarks(
      {
        for (final entry in landmarks.entries)
          entry.key: RawLandmark.fromPoseLandmark(entry.value),
      },
      minLikelihood: minLikelihood,
      maskSignal: maskSignal,
    );
  }

  /// Same gate, for landmarks not sourced directly from ML Kit -- notably
  /// [reconcileWithCrop]'s crop-redetected points, already shifted back
  /// into the original photo's coordinate space.
  factory PoseLandmarkGate.fromRawLandmarks(
    Map<PoseLandmarkType, RawLandmark> landmarks, {
    double minLikelihood = kMinLandmarkLikelihood,
    required MaskTrustSignal maskSignal,
  }) {
    final points = <Offset?>[];
    final confident = <PoseLandmarkType, RawLandmark>{};
    final allRawByIndex = <int, RawLandmark>{};
    for (var i = 0; i < kGatedLandmarkOrder.length; i++) {
      final type = kGatedLandmarkOrder[i];
      final landmark = landmarks[type];
      if (landmark != null) allRawByIndex[i] = landmark;
      final usable =
          landmark != null &&
          landmark.likelihood >= minLikelihood &&
          landmark.x.isFinite &&
          landmark.y.isFinite;
      points.add(usable ? Offset(landmark.x, landmark.y) : null);
      if (usable) confident[type] = landmark!;
    }
    return PoseLandmarkGate._build(
      points,
      confident,
      maskSignal,
      allRawByIndex: allRawByIndex,
      likelihoodFloor: minLikelihood,
    );
  }

  factory PoseLandmarkGate.fromPoints(
    List<Offset?> points, {
    required MaskTrustSignal maskSignal,
  }) {
    final normalized = List<Offset?>.generate(
      kGatedLandmarkOrder.length,
      (i) => usablePointAt(points, i),
    );
    return PoseLandmarkGate._build(
      normalized,
      const <PoseLandmarkType, RawLandmark>{},
      maskSignal,
    );
  }

  static PoseLandmarkGate empty() => PoseLandmarkGate._(
    confidentPoints: List<Offset?>.filled(kGatedLandmarkOrder.length, null),
    suspectIndices: const {},
    bodyUnit: null,
    confidentLandmarks: const {},
    maskSignal: MaskTrustSignal.none,
  );

  static PoseLandmarkGate _build(
    List<Offset?> points,
    Map<PoseLandmarkType, RawLandmark> confident,
    MaskTrustSignal maskSignal, {
    Map<int, RawLandmark> allRawByIndex = const {},
    double likelihoodFloor = kMinLandmarkLikelihood,
  }) {
    final suspect = <int>{...findSuspectLandmarks(points)};
    if (!maskSignal.bypassed) suspect.addAll(maskSignal.failedIndices);
    return PoseLandmarkGate._(
      confidentPoints: points,
      suspectIndices: suspect,
      bodyUnit: poseBodyUnit(points),
      confidentLandmarks: confident,
      maskSignal: maskSignal,
      allRawByIndex: allRawByIndex,
      likelihoodFloor: likelihoodFloor,
    );
  }

  static int indexOf(PoseLandmarkType type) =>
      kGatedLandmarkOrder.indexOf(type);

  bool isTrusted(int index) {
    if (index < 0 || index >= confidentPoints.length) return false;
    return confidentPoints[index] != null && !suspectIndices.contains(index);
  }

  bool isTrustedType(PoseLandmarkType type) => isTrusted(indexOf(type));

  Offset? point(int index) => isTrusted(index) ? confidentPoints[index] : null;

  RawLandmark? landmark(PoseLandmarkType type) =>
      isTrustedType(type) ? confidentLandmarks[type] : null;

  bool allTrusted(Iterable<PoseLandmarkType> types) =>
      types.every(isTrustedType);

  /// Continuous, graded trust for a gated landmark by index — additive to
  /// the binary [isTrusted]/[suspectIndices] above, per the audit's §20
  /// conservative-wiring plan: existing accessors are unchanged, this is a
  /// new one built from the same underlying signals. Returns null only
  /// when this landmark was never detected at all (absent from the raw
  /// pose result) — everything else, including below-likelihood-floor
  /// landmarks, gets a real [TrustedLandmark] with a low/zero confidence
  /// rather than being silently dropped.
  TrustedLandmark? trustAt(int index) {
    final raw = _allRawByIndex[index];
    if (raw == null) return null;
    return TrustedLandmark.classify(
      x: raw.x,
      y: raw.y,
      z: raw.z,
      likelihood: raw.likelihood,
      likelihoodFloor: _likelihoodFloor,
      maskConfidence: maskSignal.bypassed ? null : maskSignal.confidence[index],
      geometrySuspect: suspectIndices.contains(index),
    );
  }

  TrustedLandmark? trust(PoseLandmarkType type) => trustAt(indexOf(type));

  List<Offset?> get trustedPoints => List<Offset?>.generate(
    confidentPoints.length,
    (i) => isTrusted(i) ? confidentPoints[i] : null,
  );

  bool get hasTrustedPoints => trustedPoints.any((p) => p != null);

  T? computeIfTrusted<T>(
    List<PoseLandmarkType> required,
    T Function(Map<PoseLandmarkType, RawLandmark> l) body,
  ) {
    final resolved = <PoseLandmarkType, RawLandmark>{};
    for (final type in required) {
      final value = landmark(type);
      if (value == null) return null;
      resolved[type] = value;
    }
    return body(resolved);
  }

  String describe() {
    final buffer = StringBuffer(
      'gate: bodyUnit=${bodyUnit?.toStringAsFixed(1) ?? 'null'} '
      'maskBypassed=${maskSignal.bypassed}',
    );
    for (var i = 0; i < kGatedLandmarkNames.length; i++) {
      final status = confidentPoints[i] == null
          ? 'lowConfidence'
          : suspectIndices.contains(i)
          ? 'suspect'
          : 'trusted';
      buffer.write(' ${kGatedLandmarkNames[i]}=$status');
    }
    return buffer.toString();
  }
}

class GateHold {
  final Duration window;
  final Map<String, _HeldValue> _held = {};

  GateHold({this.window = Duration.zero});

  double? resolve(String key, double? fresh, {DateTime? now}) {
    if (window <= Duration.zero) return fresh;
    final stamp = now ?? DateTime.now();
    if (fresh != null) {
      _held[key] = _HeldValue(fresh, stamp);
      return fresh;
    }
    final previous = _held[key];
    if (previous == null) return null;
    if (stamp.difference(previous.at) > window) {
      _held.remove(key);
      return null;
    }
    return previous.value;
  }

  void clear() => _held.clear();
}

class _HeldValue {
  final double value;
  final DateTime at;

  const _HeldValue(this.value, this.at);
}
