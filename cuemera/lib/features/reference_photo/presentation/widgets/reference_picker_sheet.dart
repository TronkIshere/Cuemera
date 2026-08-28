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
import '../../../../core/pose/landmark_gate.dart';
import '../../../../shared/widgets/loading_indicator.dart';
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
    final profile = profileAsync.valueOrNull;
    final hasNoDetection =
        !profileAsync.isLoading &&
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
                        color: colors.textMuted.withValues(alpha: 0.15),
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
                      color: colors.textMuted.withValues(alpha: 0.1),
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
                    data: (value) => value == null
                        ? const SizedBox.shrink()
                        : ToleranceSliders(colors: colors),
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

  static const List<List<int>> _skeletonConnections = [
    [kLeftShoulder, kRightShoulder],
    [kLeftShoulder, kLeftElbow],
    [kLeftElbow, kLeftWrist],
    [kRightShoulder, kRightElbow],
    [kRightElbow, kRightWrist],
    [kLeftShoulder, kLeftHip],
    [kRightShoulder, kRightHip],
    [kLeftHip, kRightHip],
    [kLeftHip, kLeftKnee],
    [kLeftKnee, kLeftAnkle],
    [kRightHip, kRightKnee],
    [kRightKnee, kRightAnkle],
    [kNose, kLeftEye],
    [kNose, kRightEye],
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
    if (pose == null) {
      if (kDebugMode) debugPrint('ReferenceAnalysisPainter pose=null');
    } else {
      for (final connection in _skeletonConnections) {
        final start = usablePointAt(pose, connection[0]);
        final end = usablePointAt(pose, connection[1]);
        if (start != null && end != null) {
          canvas.drawLine(mapPoint(start), mapPoint(end), linePaint);
        }
      }
      for (var i = 0; i < kGatedLandmarkOrder.length; i++) {
        final point = usablePointAt(pose, i);
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

class ToleranceSliders extends ConsumerWidget {
  const ToleranceSliders({super.key, required this.colors});

  final AppColors colors;

  Widget _slider(String label, double value, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.caption(colors)),
        Slider(
          value: value.clamp(0.0, 1.0),
          min: 0.0,
          max: 1.0,
          activeColor: colors.accent,
          inactiveColor: colors.textMuted.withValues(alpha: 0.3),
          onChanged: onChanged,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tolerance = ref.watch(toleranceSettingsProvider);
    final notifier = ref.read(toleranceSettingsProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _slider(
          'Pose strictness',
          1.0 - tolerance.poseTolerance,
          (value) =>
              notifier.state = tolerance.copyWith(poseTolerance: 1.0 - value),
        ),
        _slider(
          'Composition strictness',
          1.0 - tolerance.compositionTolerance,
          (value) => notifier.state = tolerance.copyWith(
            compositionTolerance: 1.0 - value,
          ),
        ),
        _slider(
          'Expression strictness',
          1.0 - tolerance.expressionTolerance,
          (value) => notifier.state = tolerance.copyWith(
            expressionTolerance: 1.0 - value,
          ),
        ),
        _slider(
          'Color strictness',
          1.0 - tolerance.colorTolerance,
          (value) =>
              notifier.state = tolerance.copyWith(colorTolerance: 1.0 - value),
        ),
        _slider(
          'Body rotation strictness',
          1.0 - tolerance.bodyYawTolerance,
          (value) => notifier.state = tolerance.copyWith(
            bodyYawTolerance: 1.0 - value,
          ),
        ),
      ],
    );
  }
}
