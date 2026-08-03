// features/settings/presentation/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/theme_preference_service.dart';
import '../../../../shared/widgets/app_background.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final themeMode = ref.watch(themeModeProvider);
    final notifier = ref.read(themeModeProvider.notifier);
    final isDarkMode = themeMode == ThemeMode.dark;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text('Settings', style: AppTypography.heading2(colors)),
      ),
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.textMuted.withOpacity(0.15)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Dark Mode',
                      style: AppTypography.body(
                        colors,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Switch(
                    value: isDarkMode,
                    onChanged: (value) => notifier.setDarkMode(value),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
