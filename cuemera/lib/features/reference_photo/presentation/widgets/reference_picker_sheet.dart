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

  static const List<List<int>> _symmetricPairs = [
    [_leftElbow, _rightElbow],
    [_leftWrist, _rightWrist],
    [_leftKnee, _rightKnee],
    [_leftAnkle, _rightAnkle],
  ];

  static const double _minPlausibleSegmentScale = 0.15;
  static const double _maxPlausibleSegmentScale = 4.0;
  static const double _minPlausibleSymmetricSeparationScale = 0.2;
  static const double _maxOppositeSideIntrusionScale = 0.1;

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
        final torsoScale = _torsoScale(pose);
        final suspectForLog = _findSuspectLandmarks(pose);
        debugPrint('ReferenceAnalysisPainter torsoScale=$torsoScale');
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
    final scale = _torsoScale(pose);
    if (scale == null) return const {};

    final maxLength = scale * _maxPlausibleSegmentScale;
    final minLength = scale * _minPlausibleSegmentScale;
    final minSeparation = scale * _minPlausibleSymmetricSeparationScale;
    final suspect = <int>{};

    Offset? point(int index) => index < pose.length ? pose[index] : null;
    bool isUsable(Offset? p) => p != null && p.dx.isFinite && p.dy.isFinite;

    for (var i = 0; i < pose.length; i++) {
      if (pose[i] != null && !isUsable(pose[i])) suspect.add(i);
    }

    for (final chain in _limbChains) {
      for (var i = 0; i < chain.length - 1; i++) {
        final fromIndex = chain[i];
        final toIndex = chain[i + 1];
        if (suspect.contains(fromIndex)) {
          suspect.add(toIndex);
          continue;
        }
        final from = point(fromIndex);
        final to = point(toIndex);
        if (!isUsable(from) || !isUsable(to)) continue;
        final length = (to! - from!).distance;
        if (length > maxLength || length < minLength) {
          suspect.add(toIndex);
        }
      }
    }

    for (final pair in _symmetricPairs) {
      if (suspect.contains(pair[0]) || suspect.contains(pair[1])) continue;
      final a = point(pair[0]);
      final b = point(pair[1]);
      if (!isUsable(a) || !isUsable(b)) continue;
      if ((b! - a!).distance < minSeparation) {
        suspect.add(pair[0]);
        suspect.add(pair[1]);
      }
    }

    final torsoCenterX = _torsoCenterX(pose);
    if (torsoCenterX != null) {
      final margin = scale * _maxOppositeSideIntrusionScale;
      for (final chain in _limbChains) {
        final isLeftChain = chain[0] == _leftShoulder || chain[0] == _leftHip;
        for (var i = 1; i < chain.length; i++) {
          final jointIndex = chain[i];
          if (suspect.contains(jointIndex)) continue;
          if (suspect.contains(chain[i - 1])) {
            suspect.add(jointIndex);
            continue;
          }
          final joint = point(jointIndex);
          if (!isUsable(joint)) continue;
          if (isLeftChain && joint!.dx < torsoCenterX - margin) {
            suspect.add(jointIndex);
          } else if (!isLeftChain && joint!.dx > torsoCenterX + margin) {
            suspect.add(jointIndex);
          }
        }
      }
    }

    return suspect;
  }

  double? _torsoCenterX(List<Offset?> pose) {
    final leftShoulder = _leftShoulder < pose.length
        ? pose[_leftShoulder]
        : null;
    final rightShoulder = _rightShoulder < pose.length
        ? pose[_rightShoulder]
        : null;
    if (leftShoulder != null && rightShoulder != null) {
      return (leftShoulder.dx + rightShoulder.dx) / 2;
    }

    final leftHip = _leftHip < pose.length ? pose[_leftHip] : null;
    final rightHip = _rightHip < pose.length ? pose[_rightHip] : null;
    if (leftHip != null && rightHip != null) {
      return (leftHip.dx + rightHip.dx) / 2;
    }

    return null;
  }

  /// A stable body-scale reference (shoulder width, falling back to hip
  /// width) to judge whether a limb segment's length is plausible.
  /// Returns null when neither pair is available, in which case outlier
  /// filtering is skipped entirely rather than guessing.
  double? _torsoScale(List<Offset?> pose) {
    final leftShoulder = _leftShoulder < pose.length
        ? pose[_leftShoulder]
        : null;
    final rightShoulder = _rightShoulder < pose.length
        ? pose[_rightShoulder]
        : null;
    if (leftShoulder != null && rightShoulder != null) {
      return (rightShoulder - leftShoulder).distance;
    }

    final leftHip = _leftHip < pose.length ? pose[_leftHip] : null;
    final rightHip = _rightHip < pose.length ? pose[_rightHip] : null;
    if (leftHip != null && rightHip != null) {
      return (rightHip - leftHip).distance;
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
