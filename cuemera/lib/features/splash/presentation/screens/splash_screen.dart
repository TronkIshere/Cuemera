// features/splash/presentation/screens/splash_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/services/ml_kit_service.dart';
import '../../../../core/services/theme_preference_service.dart';
import '../../../../shared/widgets/app_background.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../../../goal_selection/presentation/screens/goal_selection_screen.dart';

final splashInitProvider = FutureProvider.autoDispose<void>((ref) async {
  await setupLocator();
  await ref.read(themeModeProvider.notifier).load();

  final cameraStatus = await Permission.camera.request();
  final micStatus = await Permission.microphone.request();

  if (!cameraStatus.isGranted || !micStatus.isGranted) {
    throw Exception('Camera and microphone permissions are required');
  }

  ref.read(mlKitServiceProvider);
});

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final initState = ref.watch(splashInitProvider);

    ref.listen<AsyncValue<void>>(splashInitProvider, (previous, next) {
      next.whenData((_) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const GoalSelectionScreen()),
        );
      });
    });

    return Scaffold(
      backgroundColor: colors.background,
      body: AppBackground(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: Image.asset(
                  'assets/images/logo.png',
                  errorBuilder: (context, error, stackTrace) {
                    return FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        AppStrings.appName,
                        maxLines: 1,
                        softWrap: false,
                        style: AppTypography.heading1(colors),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                AppStrings.appTagline,
                style: AppTypography.bodyMuted(colors),
              ),
              const SizedBox(height: AppSpacing.xl),
              initState.when(
                data: (_) => const SizedBox.shrink(),
                loading: () => CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(colors.accent),
                ),
                error: (error, stackTrace) => Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        error.toString(),
                        textAlign: TextAlign.center,
                        style: AppTypography.caption(
                          colors,
                        ).copyWith(color: colors.warning),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      PrimaryButton(
                        label: 'Retry',
                        onPressed: () => ref.invalidate(splashInitProvider),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
