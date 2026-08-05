// features/reference_photo/presentation/widgets/adjustments_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../providers/reference_providers.dart';
import 'reference_picker_sheet.dart';

class AdjustmentsSheet extends ConsumerWidget {
  const AdjustmentsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final tolerance = ref.watch(toleranceSettingsProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Adjustments', style: AppTypography.heading2(colors)),
            const SizedBox(height: AppSpacing.md),
            ToleranceSliders(colors: colors, tolerance: tolerance, ref: ref),
          ],
        ),
      ),
    );
  }
}
