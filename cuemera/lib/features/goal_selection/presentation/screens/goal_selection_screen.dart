// features/goal_selection/presentation/screens/goal_selection_screen.dart
import 'package:cuemera/features/settings/presentation/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../../../camera_session/presentation/screens/camera_screen.dart';
import '../../domain/models/photography_goal.dart';
import '../../providers/goal_providers.dart';
import '../widgets/goal_card.dart';

class GoalSelectionScreen extends ConsumerWidget {
  const GoalSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final selectedGoal = ref.watch(selectedGoalProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(AppStrings.appName, style: AppTypography.heading2(colors)),
        actions: [
          IconButton(
            icon: Icon(Icons.settings, color: colors.text),
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            children: [
              Expanded(
                child: GridView.builder(
                  itemCount: PhotographyGoal.values.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: AppSpacing.md,
                    mainAxisSpacing: AppSpacing.md,
                    childAspectRatio: 1.1,
                  ),
                  itemBuilder: (context, index) {
                    final goal = PhotographyGoal.values[index];
                    return GoalCard(
                      goal: goal,
                      isSelected: selectedGoal == goal,
                      onTap: () =>
                          ref.read(selectedGoalProvider.notifier).state = goal,
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              PrimaryButton(
                label: 'Bắt đầu chụp',
                enabled: selectedGoal != null,
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CameraScreen()),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
