// features/settings/presentation/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/theme_preference_service.dart';
import '../../../../shared/widgets/app_background.dart';
import '../../providers/ai_coaching_providers.dart';
import '../../providers/coaching_v2_settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final themeMode = ref.watch(themeModeProvider);
    final themeNotifier = ref.read(themeModeProvider.notifier);
    final isDarkMode = themeMode == ThemeMode.dark;

    final aiCoaching = ref.watch(aiCoachingSettingsProvider);
    final aiCoachingNotifier = ref.read(aiCoachingSettingsProvider.notifier);

    final coachingV2 = ref.watch(coachingV2SettingsProvider);
    final coachingV2Notifier = ref.read(coachingV2SettingsProvider.notifier);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text('Settings', style: AppTypography.heading2(colors)),
      ),
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: [
                _SettingsCard(
                  colors: colors,
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
                        onChanged: (value) => themeNotifier.setDarkMode(value),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _SettingsCard(
                  colors: colors,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  AppStrings.settingsAiCoachingLabel,
                                  style: AppTypography.body(
                                    colors,
                                  ).copyWith(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  AppStrings.settingsAiCoachingSubtitle,
                                  style: AppTypography.caption(
                                    colors,
                                  ).copyWith(color: colors.textMuted),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: aiCoaching.enabled,
                            onChanged: aiCoaching.isInstalling
                                ? null
                                : (value) =>
                                      aiCoachingNotifier.setEnabled(value),
                          ),
                        ],
                      ),
                      if (aiCoaching.isInstalling) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colors.accent,
                                value: aiCoaching.installProgress != null
                                    ? aiCoaching.installProgress! / 100
                                    : null,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              aiCoaching.installProgress != null
                                  ? '${AppStrings.settingsAiCoachingInstalling}'
                                        ' — ${aiCoaching.installProgress}%'
                                  : AppStrings.settingsAiCoachingInstalling,
                              style: AppTypography.caption(
                                colors,
                              ).copyWith(color: colors.textMuted),
                            ),
                          ],
                        ),
                      ],
                      if (aiCoaching.installError != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          aiCoaching.installError!,
                          style: AppTypography.caption(
                            colors,
                          ).copyWith(color: colors.warning),
                        ),
                      ],
                      if (aiCoaching.enabled &&
                          !aiCoaching.isInstalling &&
                          aiCoaching.aiUnavailable) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                'AI coaching paused after repeated errors — using standard coaching for now.',
                                style: AppTypography.caption(
                                  colors,
                                ).copyWith(color: colors.warning),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            GestureDetector(
                              onTap: () => aiCoachingNotifier.setEnabled(true),
                              child: Text(
                                'Retry',
                                style: AppTypography.caption(colors).copyWith(
                                  color: colors.accent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _SettingsCard(
                  colors: colors,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Coaching v2 (experimental)',
                              style: AppTypography.body(
                                colors,
                              ).copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'State-machine-driven coaching with '
                              'closed-loop follow-up. Not yet '
                              'device-verified — off by default.',
                              style: AppTypography.caption(
                                colors,
                              ).copyWith(color: colors.textMuted),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: coachingV2.enabled,
                        onChanged: (value) =>
                            coachingV2Notifier.setEnabled(value),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.colors, required this.child});

  final AppColors colors;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.textMuted.withOpacity(0.15)),
      ),
      child: child,
    );
  }
}
