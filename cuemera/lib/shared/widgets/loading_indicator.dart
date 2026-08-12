// shared/widgets/loading_indicator.dart
import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';

class LoadingIndicator extends StatelessWidget {
  const LoadingIndicator({super.key, this.message, this.size = 32});

  final String? message;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            strokeWidth: size / 10,
            valueColor: AlwaysStoppedAnimation(colors.accent),
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(message!, style: AppTypography.caption(colors)),
        ],
      ],
    );
  }
}

class LoadingOverlay extends StatelessWidget {
  const LoadingOverlay({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withOpacity(0.45),
        child: Center(child: LoadingIndicator(message: message)),
      ),
    );
  }
}
