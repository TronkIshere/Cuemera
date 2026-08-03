// features/camera_session/presentation/widgets/goal_pill.dart
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../goal_selection/domain/models/photography_goal.dart';

class GoalPill extends StatelessWidget {
  const GoalPill({
    super.key,
    required this.colors,
    required this.selectedGoal,
    required this.onTap,
  });

  final AppColors colors;
  final PhotographyGoal? selectedGoal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: colors.surface.withOpacity(0.85),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: colors.accent, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              selectedGoal?.name ?? '',
              style: AppTypography.caption(
                colors,
              ).copyWith(color: colors.accent, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: AppSpacing.xs),
            Icon(Icons.expand_more, size: 16, color: colors.accent),
          ],
        ),
      ),
    );
  }
}
