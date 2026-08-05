// features/capture/presentation/widgets/shot_type_picker_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../album/domain/models/album_state.dart';
import '../../providers/capture_providers.dart';

class ShotTypePickerSheet extends ConsumerWidget {
  const ShotTypePickerSheet({super.key});

  String _label(String shotType) {
    return shotType
        .split('_')
        .map(
          (word) =>
              word.isEmpty ? word : word[0].toUpperCase() + word.substring(1),
        )
        .join(' ');
  }

  IconData _icon(String shotType) {
    switch (shotType) {
      case 'hero':
        return Icons.portrait_outlined;
      case 'half_body':
        return Icons.accessibility_new_outlined;
      case 'walking':
        return Icons.directions_walk_outlined;
      case 'close_up':
        return Icons.face_retouching_natural_outlined;
      case 'detail':
        return Icons.center_focus_strong_outlined;
      default:
        return Icons.camera_alt_outlined;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final selected = ref.watch(selectedShotTypeProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Shot Type', style: AppTypography.heading2(colors)),
            const SizedBox(height: AppSpacing.md),
            for (final shotType in AlbumState.shotTypes)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  ref.read(selectedShotTypeProvider.notifier).state = shotType;
                  Navigator.of(context).pop();
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: shotType == selected
                        ? colors.accent.withOpacity(0.15)
                        : colors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: shotType == selected
                          ? colors.accent
                          : colors.textMuted.withOpacity(0.15),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _icon(shotType),
                        size: 20,
                        color: shotType == selected
                            ? colors.accent
                            : colors.textMuted,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          _label(shotType),
                          style: AppTypography.body(colors),
                        ),
                      ),
                      if (shotType == selected)
                        Icon(Icons.check, size: 18, color: colors.accent),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
