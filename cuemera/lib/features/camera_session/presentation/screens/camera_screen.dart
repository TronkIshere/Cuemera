// features/camera_session/presentation/screens/camera_screen.dart
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/camera_service.dart';
import '../../../../core/services/ml_kit_service.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../../../../shared/widgets/score_badge.dart';
import '../../../../shared/widgets/target_zone_overlay.dart';
import '../../../album/domain/models/shot.dart';
import '../../../album/providers/album_providers.dart';
import '../../../capture/domain/shot_builder.dart';
import '../../../capture/providers/capture_providers.dart';
import '../../../editorial_score/providers/score_providers.dart';
import '../../../goal_selection/domain/models/photography_goal.dart';
import '../../../goal_selection/presentation/screens/goal_selection_screen.dart';
import '../../../goal_selection/providers/goal_providers.dart';
import '../../../scene_analysis/providers/scene_providers.dart';
import '../../../scene_analysis/services/face_analyzer.dart';
import '../../../scene_analysis/services/light_analyzer.dart';
import '../../../scene_analysis/services/pose_analyzer.dart';
import '../../../voice_director/providers/voice_providers.dart';
import '../widgets/album_button.dart';

enum _CameraInitState { loading, ready, error }

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen>
    with WidgetsBindingObserver {
  _CameraInitState _state = _CameraInitState.loading;
  String? _errorMessage;
  bool _hasCaptured = false;
  bool _showFlash = false;

  DateTime _lastProcessed = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _throttleInterval = Duration(milliseconds: 80);

  final PoseAnalyzer _poseAnalyzer = PoseAnalyzer();
  final FaceAnalyzer _faceAnalyzer = FaceAnalyzer();
  final LightAnalyzer _lightAnalyzer = LightAnalyzer();

  bool _wasStreamingBeforePause = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final goal = ref.read(selectedGoalProvider);
      if (goal == null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const GoalSelectionScreen()),
        );
        return;
      }
      _initCamera();
    });
  }

  Future<void> _initCamera() async {
    setState(() {
      _state = _CameraInitState.loading;
      _errorMessage = null;
    });

    try {
      final cameraService = ref.read(cameraServiceProvider);
      await cameraService.init();
      await cameraService.startImageStream(_onFrame);

      if (!mounted) return;
      setState(() => _state = _CameraInitState.ready);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _CameraInitState.error;
        _errorMessage = e.toString();
      });
    }
  }

  void _onFrame(CameraImage image) {
    if (!mounted) return;

    final now = DateTime.now();
    if (now.difference(_lastProcessed) < _throttleInterval) return;
    _lastProcessed = now;

    final trackingEngine = ref.read(trackingEngineProvider);

    final previousScene = ref.read(sceneProfileProvider);
    final rawScene = _lightAnalyzer.analyzeLight(image, previousScene);
    final smoothedScene = trackingEngine.smoothScene(rawScene, previousScene);
    ref.read(sceneProfileProvider.notifier).state = smoothedScene;

    final mlKitService = ref.read(mlKitServiceProvider);
    final cameraService = ref.read(cameraServiceProvider);
    final controller = cameraService.controller;
    if (controller == null) return;

    mlKitService.processImage(
      image,
      controller.description,
      InputImageRotation.rotation0deg,
    );
  }

  Future<void> _performCapture() async {
    final cameraService = ref.read(cameraServiceProvider);
    final imagePath = await cameraService.capture();
    if (!mounted) return;

    final subject = ref.read(subjectProfileProvider);
    final scene = ref.read(sceneProfileProvider);
    final goal = ref.read(selectedGoalProvider);
    if (goal == null) return;

    final shot = buildShotFromCapture(
      imagePath: imagePath,
      subject: subject,
      scene: scene,
      goal: goal,
      shotType: 'hero',
    );

    ref.read(albumStateProvider.notifier).addShot(shot);

    if (!mounted) return;
    setState(() {
      _hasCaptured = true;
      _showFlash = true;
    });

    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    setState(() => _showFlash = false);

    if (!mounted) return;
    await cameraService.startImageStream(_onFrame);
  }

  void _onAdjustmentsTap() {}

  void _onModeSelectorTap() {}

  void _onReferencePhotoTap() {}

  Future<void> _showGoalPicker(AppColors colors) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        final selectedGoal = ref.read(selectedGoalProvider);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: colors.textMuted.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                ...PhotographyGoal.values.map((goal) {
                  final isSelected = goal == selectedGoal;
                  return ListTile(
                    onTap: () {
                      ref.read(selectedGoalProvider.notifier).state = goal;
                      Navigator.of(sheetContext).pop();
                    },
                    title: Text(
                      goal.name,
                      style: AppTypography.body(colors).copyWith(
                        color: isSelected ? colors.accent : colors.text,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check, color: colors.accent, size: 18)
                        : null,
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (_state != _CameraInitState.ready) return;
    final cameraService = ref.read(cameraServiceProvider);

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _wasStreamingBeforePause =
            cameraService.controller?.value.isStreamingImages ?? false;
        cameraService.stopImageStream();
        break;
      case AppLifecycleState.resumed:
        if (mounted && _wasStreamingBeforePause) {
          cameraService.startImageStream(_onFrame);
        }
        break;
      default:
        break;
    }
  }

  @override
  void dispose() {
    final cameraService = ref.read(cameraServiceProvider);
    cameraService.stopImageStream();
    WidgetsBinding.instance.removeObserver(this);
    cameraService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;

    ref.watch(sceneAnalysisListenerProvider);
    ref.watch(voiceDirectorListenerProvider);

    ref.listen<Shot?>(capturedShotProvider, (previous, shot) {
      if (shot == null) return;
      ref.read(albumStateProvider.notifier).addShot(shot);
      if (!mounted) return;
      setState(() {
        _hasCaptured = true;
        _showFlash = true;
      });
      Future.delayed(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        setState(() => _showFlash = false);
      });
    });

    ref.watch(autoCaptureProvider);

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final cameraService = ref.read(cameraServiceProvider);
        await cameraService.stopImageStream();
        if (!mounted) return;
        Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: colors.background,
        body: _buildBody(colors),
      ),
    );
  }

  Widget _buildBody(AppColors colors) {
    switch (_state) {
      case _CameraInitState.loading:
        return Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(colors.accent),
          ),
        );
      case _CameraInitState.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _errorMessage ?? 'Camera initialization failed',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.warning),
                ),
                const SizedBox(height: AppSpacing.md),
                PrimaryButton(label: 'Retry', onPressed: _initCamera),
              ],
            ),
          ),
        );
      case _CameraInitState.ready:
        return _buildReadyBody(colors);
    }
  }

  Widget _topNavIcon({
    required AppColors colors,
    required IconData icon,
    required VoidCallback onTap,
  }) {
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

  Widget _buildTopNavBar(AppColors colors) {
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
          _topNavIcon(
            colors: colors,
            icon: Icons.tune,
            onTap: _onAdjustmentsTap,
          ),
          _topNavIcon(
            colors: colors,
            icon: Icons.grid_view_outlined,
            onTap: _onModeSelectorTap,
          ),
          _topNavIcon(
            colors: colors,
            icon: Icons.image_outlined,
            onTap: _onReferencePhotoTap,
          ),
        ],
      ),
    );
  }

  Widget _buildGoalPill(AppColors colors, PhotographyGoal? selectedGoal) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => _showGoalPicker(colors),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: colors.surface.withOpacity(0.85),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: colors.accent, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              selectedGoal?.name ?? '',
              style: AppTypography.caption(
                colors,
              ).copyWith(color: colors.accent, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: AppSpacing.xs),
            Icon(Icons.expand_more, size: 16, color: colors.accent),
          ],
        ),
      ),
    );
  }

  Widget _buildReadyBody(AppColors colors) {
    final controller = ref.read(cameraServiceProvider).controller;
    if (controller == null || !controller.value.isInitialized) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(colors.accent),
        ),
      );
    }

    final subject = ref.watch(subjectProfileProvider);
    final nextAction = ref.watch(nextActionProvider);
    final score = ref.watch(currentScoreProvider);
    final trackingProgress = ref.watch(trackingProgressProvider);
    final selectedGoal = ref.watch(selectedGoalProvider);

    final hasZone =
        subject.bodyRatio != null || subject.shoulderAngleDegrees != null;

    final topInset = MediaQuery.of(context).padding.top;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    const navBarHeight = 44.0;
    const goalPillRowHeight = 32.0;
    final clusterTop = topInset + AppSpacing.xs;
    final secondRowTop = clusterTop + navBarHeight + AppSpacing.sm;
    final phraseChipTop = secondRowTop + goalPillRowHeight + AppSpacing.sm;

    return Stack(
      fit: StackFit.expand,
      children: [
        FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: controller.value.previewSize?.height ?? 1,
            height: controller.value.previewSize?.width ?? 1,
            child: CameraPreview(controller),
          ),
        ),
        if (hasZone)
          TargetZoneOverlay(
            aligned: (subject.shoulderAngleDegrees?.abs() ?? 90) < 15,
            trackingProgress: trackingProgress,
          ),
        Positioned(
          top: clusterTop,
          left: AppSpacing.md,
          right: AppSpacing.md,
          child: _buildTopNavBar(colors),
        ),
        Positioned(
          top: secondRowTop,
          left: AppSpacing.md,
          child: _buildGoalPill(colors, selectedGoal),
        ),
        if (nextAction != null)
          Positioned(
            top: phraseChipTop,
            left: AppSpacing.md,
            right: AppSpacing.md,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: colors.surface.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: colors.accent, width: 1.5),
                ),
                child: Text(
                  nextAction.phrase,
                  style: AppTypography.body(
                    colors,
                  ).copyWith(color: colors.accent, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        Positioned(
          top: secondRowTop,
          right: AppSpacing.md,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (_hasCaptured && score != null) ...[
                ScoreBadge(score: score.overall),
                const SizedBox(height: AppSpacing.sm),
              ],
              const AlbumButton(),
            ],
          ),
        ),
        if (_showFlash) Container(color: colors.accent.withOpacity(0.5)),
        Positioned(
          bottom: bottomInset + AppSpacing.md,
          left: AppSpacing.md,
          right: AppSpacing.md,
          child: PrimaryButton(label: 'Capture', onPressed: _performCapture),
        ),
      ],
    );
  }
}
