// features/camera_session/presentation/screens/camera_screen.dart
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/services/camera_service.dart';
import '../../../../core/services/ml_kit_service.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../../../goal_selection/presentation/screens/goal_selection_screen.dart';
import '../../../goal_selection/providers/goal_providers.dart';
import '../../../scene_analysis/providers/scene_providers.dart';
import '../../../scene_analysis/services/face_analyzer.dart';
import '../../../scene_analysis/services/light_analyzer.dart';
import '../../../scene_analysis/services/pose_analyzer.dart';

enum _CameraInitState { loading, ready, error }

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen> {
  _CameraInitState _state = _CameraInitState.loading;
  String? _errorMessage;

  DateTime _lastProcessed = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _throttleInterval = Duration(milliseconds: 80);

  final PoseAnalyzer _poseAnalyzer = PoseAnalyzer();
  final FaceAnalyzer _faceAnalyzer = FaceAnalyzer();
  final LightAnalyzer _lightAnalyzer = LightAnalyzer();

  @override
  void initState() {
    super.initState();
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
    final now = DateTime.now();
    if (now.difference(_lastProcessed) < _throttleInterval) return;
    _lastProcessed = now;

    final scene = ref.read(sceneProfileProvider);
    final updatedScene = _lightAnalyzer.analyzeLight(image, scene);
    ref.read(sceneProfileProvider.notifier).state = updatedScene;

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

  @override
  void dispose() {
    final cameraService = ref.read(cameraServiceProvider);
    cameraService.stopImageStream();
    cameraService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    ref.watch(sceneAnalysisListenerProvider);

    return Scaffold(
      backgroundColor: colors.background,
      body: _buildBody(colors),
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
        final controller = ref.read(cameraServiceProvider).controller;
        if (controller == null || !controller.value.isInitialized) {
          return Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(colors.accent),
            ),
          );
        }
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: controller.value.previewSize?.height ?? 1,
              height: controller.value.previewSize?.width ?? 1,
              child: CameraPreview(controller),
            ),
          ),
        );
    }
  }
}
