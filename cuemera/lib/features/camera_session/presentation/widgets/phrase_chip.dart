// features/camera_session/presentation/widgets/phrase_chip.dart
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';

class PhraseChip extends StatelessWidget {
  const PhraseChip({super.key, required this.colors, required this.phrase});

  final AppColors colors;
  final String phrase;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: colors.surface.withOpacity(0.85),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: colors.accent, width: 1.5),
        ),
        child: Text(
          phrase,
          style: AppTypography.body(
            colors,
          ).copyWith(color: colors.accent, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
