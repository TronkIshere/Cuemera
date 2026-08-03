// features/camera_session/presentation/widgets/camera_top_nav_bar.dart
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';

class CameraTopNavBar extends StatelessWidget {
  const CameraTopNavBar({
    super.key,
    required this.colors,
    required this.onAdjustmentsTap,
    required this.onModeSelectorTap,
    required this.onReferencePhotoTap,
  });

  final AppColors colors;
  final VoidCallback onAdjustmentsTap;
  final VoidCallback onModeSelectorTap;
  final VoidCallback onReferencePhotoTap;

  Widget _icon(IconData icon, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.surface.withOpacity(0.7),
          border: Border.all(color: colors.accent.withOpacity(0.35)),
        ),
        child: Icon(icon, size: 18, color: colors.accent),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surface.withOpacity(0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.accent.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _icon(Icons.tune, onAdjustmentsTap),
          _icon(Icons.grid_view_outlined, onModeSelectorTap),
          _icon(Icons.image_outlined, onReferencePhotoTap),
        ],
      ),
    );
  }
}
