// features/goal_selection/presentation/screens/goal_selection_screen.dart
import 'dart:math' as math;

import 'package:cuemera/features/settings/presentation/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../shared/widgets/app_background.dart';
import '../../../album/presentation/screens/album_screen.dart';
import '../../../camera_session/presentation/screens/camera_screen.dart';
import '../../domain/models/photography_goal.dart';
import '../../providers/goal_providers.dart';
import '../widgets/goal_card.dart';

class GoalSelectionScreen extends ConsumerWidget {
  const GoalSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<AppColors>()!;

    return Scaffold(
      backgroundColor: colors.background,
      body: AppBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 32),
                _HomeHeader(colors: colors),
                const SizedBox(height: 32),
                EditorialMenuCard(
                  height: 140,
                  icon: Icons.camera_alt_outlined,
                  title: AppStrings.homeShootLabel,
                  subtitle: AppStrings.homeShootSubtitle,
                  colors: colors,
                  isPrimary: false,
                  onTap: () {
                    if (ref.read(selectedGoalProvider) == null) {
                      ref.read(selectedGoalProvider.notifier).state =
                          PhotographyGoal.values.first;
                    }
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CameraScreen()),
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                EditorialMenuCard(
                  height: 140,
                  icon: Icons.photo_library_outlined,
                  title: AppStrings.homeAlbumLabel,
                  subtitle: AppStrings.homeAlbumSubtitle,
                  colors: colors,
                  isPrimary: false,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AlbumScreen()),
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                EditorialMenuCard(
                  height: 140,
                  icon: Icons.settings_outlined,
                  title: AppStrings.homeSettingsLabel,
                  subtitle: AppStrings.homeSettingsSubtitle,
                  colors: colors,
                  isPrimary: false,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    );
                  },
                ),
                SizedBox(height: MediaQuery.of(context).padding.bottom + 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.colors});

  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wordmarkSize = math.min(
          38.0,
          math.max(34.0, constraints.maxWidth * 0.095),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CustomPaint(
                  size: const Size(20, 20),
                  painter: _ApertureRingPainter(color: colors.accent),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  AppStrings.appName,
                  style: TextStyle(
                    fontSize: wordmarkSize,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: colors.text,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              AppStrings.homeTagline,
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 2.4,
                fontWeight: FontWeight.w500,
                color: colors.textMuted.withOpacity(0.8),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              width: 56,
              height: 1,
              color: colors.accent.withOpacity(0.55),
            ),
          ],
        );
      },
    );
  }
}

class _ApertureRingPainter extends CustomPainter {
  _ApertureRingPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 1;

    final ringPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(center, radius, ringPaint);

    final tickPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    for (var i = 0; i < 6; i++) {
      final angle = (i / 6) * 2 * math.pi;
      final inner = Offset(
        center.dx + math.cos(angle) * (radius - 4),
        center.dy + math.sin(angle) * (radius - 4),
      );
      final outer = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      canvas.drawLine(inner, outer, tickPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ApertureRingPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
