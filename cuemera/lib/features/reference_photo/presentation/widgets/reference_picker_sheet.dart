// features/reference_photo/presentation/widgets/reference_picker_sheet.dart
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
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
                        : _ToleranceSliders(
                            colors: colors,
                            tolerance: tolerance,
                            ref: ref,
                          ),
                    loading: () => Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                      ),
                      child: Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation(colors.accent),
                        ),
                      ),
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
    if (pose != null) {
      for (final connection in _skeletonConnections) {
        final start = connection[0] < pose.length ? pose[connection[0]] : null;
        final end = connection[1] < pose.length ? pose[connection[1]] : null;
        if (start != null && end != null) {
          canvas.drawLine(mapPoint(start), mapPoint(end), linePaint);
        }
      }
      for (final point in pose) {
        if (point != null) {
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

  @override
  bool shouldRepaint(covariant ReferenceAnalysisPainter oldDelegate) {
    return oldDelegate.poseLandmarkPoints != poseLandmarkPoints ||
        oldDelegate.faceContourPoints != faceContourPoints ||
        oldDelegate.imageWidth != imageWidth ||
        oldDelegate.imageHeight != imageHeight;
  }
}

class _ToleranceSliders extends StatelessWidget {
  const _ToleranceSliders({
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
