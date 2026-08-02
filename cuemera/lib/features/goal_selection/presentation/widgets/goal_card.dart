// features/goal_selection/presentation/widgets/goal_card.dart
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../domain/models/photography_goal.dart';

class GoalCard extends StatelessWidget {
  const GoalCard({
    super.key,
    required this.goal,
    required this.isSelected,
    required this.onTap,
  });

  final PhotographyGoal goal;
  final bool isSelected;
  final VoidCallback onTap;

  IconData get _icon {
    switch (goal) {
      case PhotographyGoal.editorial:
        return Icons.camera_alt_outlined;
      case PhotographyGoal.linkedin:
        return Icons.badge_outlined;
      case PhotographyGoal.travel:
        return Icons.flight_takeoff_outlined;
      case PhotographyGoal.dating:
        return Icons.favorite_outline;
      case PhotographyGoal.beach:
        return Icons.wb_sunny_outlined;
      case PhotographyGoal.luxury:
        return Icons.diamond_outlined;
    }
  }

  String get _label {
    final name = goal.name;
    return name[0].toUpperCase() + name.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.lg,
        ),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? colors.accent
                : colors.textMuted.withOpacity(0.15),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _icon,
              size: 32,
              color: isSelected ? colors.accent : colors.textMuted,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _label,
              style: AppTypography.body(colors).copyWith(
                fontWeight: FontWeight.w600,
                color: isSelected ? colors.accent : colors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
