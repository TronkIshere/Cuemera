// shared/widgets/score_badge.dart
import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';

class ScoreBadge extends StatelessWidget {
  const ScoreBadge({super.key, required this.score, this.size = 56});

  final int score;
  final double size;

  Color _colorFor(AppColors colors) {
    if (score >= 80) return colors.success;
    if (score >= 50) return colors.accent;
    return colors.warning;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final color = _colorFor(colors);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.15),
        border: Border.all(color: color, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        '$score',
        style: AppTypography.score(
          colors,
        ).copyWith(color: color, fontSize: size * 0.32),
      ),
    );
  }
}
