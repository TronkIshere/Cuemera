// features/reference_photo/presentation/widgets/reference_picker_sheet.dart
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../../domain/models/tolerance_settings.dart';
import '../../providers/reference_providers.dart';

class ReferencePickerSheet extends ConsumerWidget {
  const ReferencePickerSheet({super.key});

  Future<void> _pickImage(WidgetRef ref) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    ref.read(selectedReferenceImagePathProvider.notifier).state = picked.path;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final imagePath = ref.watch(selectedReferenceImagePathProvider);
    final profileAsync = ref.watch(referenceProfileProvider);
    final tolerance = ref.watch(toleranceSettingsProvider);
    final profile = profileAsync.maybeWhen(
      data: (value) => value,
      orElse: () => null,
    );
    final hasNoDetection =
        profile != null &&
        (profile.poseLandmarkPoints == null ||
            profile.poseLandmarkPoints!.every((p) => p == null)) &&
        (profile.faceContourPoints == null ||
            profile.faceContourPoints!.isEmpty);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return SafeArea(
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Reference Photo', style: AppTypography.heading2(colors)),
                const SizedBox(height: AppSpacing.md),
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _pickImage(ref),
                  child: Container(
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: colors.textMuted.withOpacity(0.15),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: imagePath != null
                        ? ConstrainedBox(
                            constraints: const BoxConstraints(
                              minHeight: 260,
                              maxHeight: 420,
                            ),
                            child: AspectRatio(
                              aspectRatio:
                                  (profile?.imageWidth != null &&
                                      profile?.imageHeight != null)
                                  ? profile!.imageWidth! / profile.imageHeight!
                                  : 3 / 4,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.file(
                                    File(imagePath),
                                    fit: BoxFit.contain,
                                  ),
                                  if (profile != null &&
                                      profile.imageWidth != null &&
                                      profile.imageHeight != null)
                                    Positioned.fill(
                                      child: CustomPaint(
                                        painter: ReferenceAnalysisPainter(
                                          poseLandmarkPoints:
                                              profile.poseLandmarkPoints,
                                          faceContourPoints:
                                              profile.faceContourPoints,
                                          imageWidth: profile.imageWidth!,
                                          imageHeight: profile.imageHeight!,
                                        ),
                                      ),
                                    ),
                                  if (profileAsync.isLoading)
                                    const LoadingOverlay(
                                      message: 'Analyzing photo...',
                                    ),
                                ],
                              ),
                            ),
                          )
                        : SizedBox(
                            height: 260,
                            child: Center(
                              child: Text(
                                'Tap to choose a reference photo',
                                style: AppTypography.bodyMuted(colors),
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                if (hasNoDetection)
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: colors.textMuted.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 18,
                          color: colors.textMuted,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            'No pose or face detected in this photo. '
                            'This works best with real photos of people, '
                            'not illustrations or drawings.',
                            style: AppTypography.caption(colors),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (imagePath != null)
                  profileAsync.when(
                    data: (profile) => profile == null
                        ? const SizedBox.shrink()
                        : ToleranceSliders(
                            colors: colors,
                            tolerance: tolerance,
                            ref: ref,
                          ),
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                      child: Center(child: LoadingIndicator()),
                    ),
                    error: (error, stackTrace) => Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm,
                      ),
                      child: Text(
                        'Could not analyze this photo, try another one',
                        style: AppTypography.caption(colors),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class ReferenceAnalysisPainter extends CustomPainter {
  ReferenceAnalysisPainter({
    required this.poseLandmarkPoints,
    required this.faceContourPoints,
    required this.imageWidth,
    required this.imageHeight,
  });

  final List<Offset?>? poseLandmarkPoints;
  final List<Offset>? faceContourPoints;
  final double imageWidth;
  final double imageHeight;

  static const int _nose = 0;
  static const int _leftEye = 1;
  static const int _rightEye = 2;
  static const int _leftShoulder = 3;
  static const int _rightShoulder = 4;
  static const int _leftElbow = 5;
  static const int _rightElbow = 6;
  static const int _leftWrist = 7;
  static const int _rightWrist = 8;
  static const int _leftHip = 9;
  static const int _rightHip = 10;
  static const int _leftKnee = 11;
  static const int _rightKnee = 12;
  static const int _leftAnkle = 13;
  static const int _rightAnkle = 14;

  static const List<String> _landmarkNames = [
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

  static const List<List<int>> _skeletonConnections = [
    [_leftShoulder, _rightShoulder],
    [_leftShoulder, _leftElbow],
    [_leftElbow, _leftWrist],
    [_rightShoulder, _rightElbow],
    [_rightElbow, _rightWrist],
    [_leftShoulder, _leftHip],
    [_rightShoulder, _rightHip],
    [_leftHip, _rightHip],
    [_leftHip, _leftKnee],
    [_leftKnee, _leftAnkle],
    [_rightHip, _rightKnee],
    [_rightKnee, _rightAnkle],
    [_nose, _leftEye],
    [_nose, _rightEye],
  ];

  static const List<List<int>> _limbChains = [
    [_leftShoulder, _leftElbow, _leftWrist],
    [_rightShoulder, _rightElbow, _rightWrist],
    [_leftHip, _leftKnee, _leftAnkle],
    [_rightHip, _rightKnee, _rightAnkle],
  ];

  static const List<List<int>> _mirroredChainIndexPairs = [
    [0, 1],
    [2, 3],
  ];

  static const List<List<int>> _symmetricPairs = [
    [_leftElbow, _rightElbow],
    [_leftWrist, _rightWrist],
    [_leftKnee, _rightKnee],
    [_leftAnkle, _rightAnkle],
  ];

  static const double _torsoHeightBodyUnits = 1.0;
  static const double _torsoSideBodyUnits = 1.02;
  static const double _shoulderWidthBodyUnits = 0.85;
  static const double _hipWidthBodyUnits = 0.65;
  static const double _eyeSpanBodyUnits = 0.15;

  static const Map<int, double> _maxSegmentBodyUnits = {
    _leftElbow: 0.75,
    _rightElbow: 0.75,
    _leftWrist: 0.72,
    _rightWrist: 0.72,
    _leftKnee: 1.15,
    _rightKnee: 1.15,
    _leftAnkle: 1.05,
    _rightAnkle: 1.05,
  };

  static const double _bodyUnitOutlierCeilingMultiplier = 2.0;
  static const double _segmentLengthSafetyMultiplier = 1.5;
  static const double _definitiveSegmentLengthMultiplier = 2.0;
  static const double _minSymmetricSeparationBodyUnits = 0.12;
  static const double _shallowOppositeSideIntrusionBodyUnits = 0.12;
  static const double _deepOppositeSideIntrusionBodyUnits = 0.45;
  static const double _maxBilateralSegmentLengthRatio = 2.5;
  static const double _maxSuspectBodyLandmarkFraction = 0.6;

  static const int _excessiveSegmentLengthEvidence = 2;
  static const int _shallowIntrusionEvidence = 1;
  static const int _deepIntrusionEvidence = 2;
  static const int _mirroredIntrusionEvidenceRelief = 1;
  static const int _symmetricCollapseEvidence = 1;
  static const int _bilateralLengthMismatchEvidence = 1;
  static const int _suspectEvidenceThreshold = 2;

  @override
  void paint(Canvas canvas, Size size) {
    if (imageWidth <= 0 || imageHeight <= 0) return;

    final scale = math.min(size.width / imageWidth, size.height / imageHeight);
    final scaledImageWidth = imageWidth * scale;
    final scaledImageHeight = imageHeight * scale;
    final offsetX = (size.width - scaledImageWidth) / 2;
    final offsetY = (size.height - scaledImageHeight) / 2;

    Offset mapPoint(Offset point) {
      return Offset(point.dx * scale + offsetX, point.dy * scale + offsetY);
    }

    final pointPaint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.fill
      ..strokeWidth = 2;

    final linePaint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final pose = poseLandmarkPoints;
    if (kDebugMode) {
      if (pose == null) {
        debugPrint('ReferenceAnalysisPainter pose=null');
      } else {
        final bodyUnit = _bodyUnit(pose);
        final suspectForLog = _findSuspectLandmarks(pose);
        debugPrint('ReferenceAnalysisPainter bodyUnit=$bodyUnit');
        for (var i = 0; i < _landmarkNames.length; i++) {
          final value = i < pose.length ? pose[i] : null;
          final status = value == null
              ? 'null'
              : suspectForLog.contains(i)
              ? 'suspect'
              : 'drawn';
          debugPrint('ReferenceAnalysisPainter ${_landmarkNames[i]}=$status');
        }
      }
    }
    if (pose != null) {
      final suspectIndices = _findSuspectLandmarks(pose);

      for (final connection in _skeletonConnections) {
        if (suspectIndices.contains(connection[0]) ||
            suspectIndices.contains(connection[1])) {
          continue;
        }
        final start = connection[0] < pose.length ? pose[connection[0]] : null;
        final end = connection[1] < pose.length ? pose[connection[1]] : null;
        if (start != null && end != null) {
          canvas.drawLine(mapPoint(start), mapPoint(end), linePaint);
        }
      }
      for (var i = 0; i < pose.length; i++) {
        final point = pose[i];
        if (point != null && !suspectIndices.contains(i)) {
          canvas.drawCircle(mapPoint(point), 3, pointPaint);
        }
      }
    }

    final face = faceContourPoints;
    if (face != null && face.length >= 4) {
      final mapped = face.map(mapPoint).toList();
      final rect = Rect.fromLTRB(
        mapped.map((p) => p.dx).reduce(math.min),
        mapped.map((p) => p.dy).reduce(math.min),
        mapped.map((p) => p.dx).reduce(math.max),
        mapped.map((p) => p.dy).reduce(math.max),
      );
      canvas.drawRect(rect, linePaint);
    }
  }

  Set<int> _findSuspectLandmarks(List<Offset?> pose) {
    final definitive = <int>{};
    for (var i = 0; i < pose.length; i++) {
      final point = pose[i];
      if (point != null && (!point.dx.isFinite || !point.dy.isFinite)) {
        definitive.add(i);
      }
    }

    final bodyUnit = _bodyUnit(pose);
    if (bodyUnit == null) return definitive;

    final evidence = <int, int>{};
    void addEvidence(int index, int weight) {
      if (weight <= 0) return;
      evidence[index] = (evidence[index] ?? 0) + weight;
    }

    final segmentLengths = <int, double>{};
    for (final chain in _limbChains) {
      for (var i = 0; i < chain.length - 1; i++) {
        final from = _usablePointAt(pose, chain[i]);
        final to = _usablePointAt(pose, chain[i + 1]);
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
      final first = _usablePointAt(pose, pair[0]);
      final second = _usablePointAt(pose, pair[1]);
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

    final centerX = _torsoCenterX(pose);
    if (centerX != null) {
      final shallowMargin = bodyUnit * _shallowOppositeSideIntrusionBodyUnits;
      final deepMargin = bodyUnit * _deepOppositeSideIntrusionBodyUnits;

      Map<int, int> intrusionEvidence(List<int> chain, double centerX) {
        final isLeftChain = chain[0] == _leftShoulder || chain[0] == _leftHip;
        final result = <int, int>{};
        for (var i = 1; i < chain.length; i++) {
          final joint = _usablePointAt(pose, chain[i]);
          if (joint == null) continue;
          final intrusion = isLeftChain
              ? centerX - joint.dx
              : joint.dx - centerX;
          if (intrusion <= shallowMargin) continue;
          result[chain[i]] = intrusion > deepMargin
              ? _deepIntrusionEvidence
              : _shallowIntrusionEvidence;
        }
        return result;
      }

      for (final indexPair in _mirroredChainIndexPairs) {
        final first = intrusionEvidence(_limbChains[indexPair[0]], centerX);
        final second = intrusionEvidence(_limbChains[indexPair[1]], centerX);
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

    for (final chain in _limbChains) {
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
    for (var i = _leftShoulder; i <= _rightAnkle && i < pose.length; i++) {
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

  Offset? _usablePointAt(List<Offset?> pose, int index) {
    if (index < 0 || index >= pose.length) return null;
    final point = pose[index];
    if (point == null || !point.dx.isFinite || !point.dy.isFinite) return null;
    return point;
  }

  double? _bodyUnit(List<Offset?> pose) {
    final candidates = <double>[];
    void addCandidate(double measured, double bodyUnits) {
      if (measured > 0) candidates.add(measured / bodyUnits);
    }

    final leftShoulder = _usablePointAt(pose, _leftShoulder);
    final rightShoulder = _usablePointAt(pose, _rightShoulder);
    final leftHip = _usablePointAt(pose, _leftHip);
    final rightHip = _usablePointAt(pose, _rightHip);
    final leftEye = _usablePointAt(pose, _leftEye);
    final rightEye = _usablePointAt(pose, _rightEye);

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

  double? _torsoCenterX(List<Offset?> pose) {
    final leftShoulder = _usablePointAt(pose, _leftShoulder);
    final rightShoulder = _usablePointAt(pose, _rightShoulder);
    if (leftShoulder != null && rightShoulder != null) {
      return (leftShoulder.dx + rightShoulder.dx) / 2;
    }

    final leftHip = _usablePointAt(pose, _leftHip);
    final rightHip = _usablePointAt(pose, _rightHip);
    if (leftHip != null && rightHip != null) {
      return (leftHip.dx + rightHip.dx) / 2;
    }

    return null;
  }

  @override
  bool shouldRepaint(covariant ReferenceAnalysisPainter oldDelegate) {
    return oldDelegate.poseLandmarkPoints != poseLandmarkPoints ||
        oldDelegate.faceContourPoints != faceContourPoints ||
        oldDelegate.imageWidth != imageWidth ||
        oldDelegate.imageHeight != imageHeight;
  }
}

class ToleranceSliders extends StatelessWidget {
  const ToleranceSliders({
    required this.colors,
    required this.tolerance,
    required this.ref,
  });

  final AppColors colors;
  final ToleranceSettings tolerance;
  final WidgetRef ref;

  Widget _slider(String label, double value, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.caption(colors)),
        Slider(
          value: value,
          min: 0.0,
          max: 1.0,
          activeColor: colors.accent,
          inactiveColor: colors.textMuted.withOpacity(0.3),
          onChanged: onChanged,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(toleranceSettingsProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _slider(
          'Pose strictness',
          tolerance.poseTolerance,
          (value) => notifier.state = tolerance.copyWith(poseTolerance: value),
        ),
        _slider(
          'Composition strictness',
          tolerance.compositionTolerance,
          (value) =>
              notifier.state = tolerance.copyWith(compositionTolerance: value),
        ),
        _slider(
          'Expression strictness',
          tolerance.expressionTolerance,
          (value) =>
              notifier.state = tolerance.copyWith(expressionTolerance: value),
        ),
        _slider(
          'Color strictness',
          tolerance.colorTolerance,
          (value) => notifier.state = tolerance.copyWith(colorTolerance: value),
        ),
      ],
    );
  }
}
