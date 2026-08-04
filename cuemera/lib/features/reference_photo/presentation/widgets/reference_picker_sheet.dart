// features/reference_photo/presentation/widgets/reference_picker_sheet.dart
import 'dart:io';

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

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Reference Photo', style: AppTypography.heading2(colors)),
            const SizedBox(height: AppSpacing.md),
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _pickImage(ref),
              child: Container(
                height: 180,
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.textMuted.withOpacity(0.15)),
                ),
                clipBehavior: Clip.antiAlias,
                child: imagePath != null
                    ? Image.file(File(imagePath), fit: BoxFit.cover)
                    : Center(
                        child: Text(
                          'Tap to choose a reference photo',
                          style: AppTypography.bodyMuted(colors),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
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
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(colors.accent),
                    ),
                  ),
                ),
                error: (error, stackTrace) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
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
