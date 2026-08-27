// features/camera_session/presentation/screens/camera_screen.dart
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/app_tts_service.dart';
import '../../../../core/services/camera_service.dart';
import '../../../../core/services/ml_kit_service.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../../../../shared/widgets/score_badge.dart';
import '../../../album/domain/models/shot.dart';
import '../../../album/presentation/screens/album_screen.dart';
import '../../../album/providers/album_providers.dart';
import '../../../capture/domain/shot_builder.dart';
import '../../../capture/presentation/widgets/shot_type_picker_sheet.dart';
import '../../../capture/providers/capture_providers.dart';
import '../../../editorial_score/domain/score_calculator.dart';
import '../../../reference_photo/presentation/widgets/adjustments_sheet.dart';
import '../../../reference_photo/presentation/widgets/reference_picker_sheet.dart';
import '../../../reference_photo/providers/reference_providers.dart';
import '../../../scene_analysis/providers/scene_providers.dart';
import '../../../scene_analysis/services/light_analyzer.dart';
import '../../../settings/providers/coaching_v2_settings_provider.dart';
import '../../../settings/providers/debug_overlay_settings_provider.dart';
import '../../../settings/providers/live_detection_settings_provider.dart';
import '../../../voice_director/providers/voice_providers.dart';
import '../../../voice_director/providers/voice_providers_v2.dart';
import '../widgets/camera_preview_layer.dart';
import '../widgets/camera_top_nav_bar.dart';
import '../widgets/debug_perf_overlay.dart';

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
  EditorialScore? _lastCapturedScore;
  bool _showFlash = false;
  bool _cameraDisposedForBackground = false;

  DateTime _lastProcessed = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _throttleInterval = Duration(milliseconds: 80);

  DateTime _lastDebugSnapshotLog = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _debugSnapshotLogInterval = Duration(milliseconds: 500);

  final LightAnalyzer _lightAnalyzer = LightAnalyzer();

  SegmentationMask? _latestMask;
  StreamSubscription<MlKitAnalysisResult>? _mlKitSubscription;

  double _baseZoom = 1.0;
  double _currentZoom = 1.0;
  Offset? _focusPoint;
  Timer? _focusRingTimer;

  final GlobalKey<State<DebugPerfOverlay>> _debugPerfOverlayKey =
      GlobalKey<State<DebugPerfOverlay>>();

  late final CameraService _cameraService;

  @override
  void initState() {
    super.initState();
    _cameraService = ref.read(cameraServiceProvider);
    ref.read(autoCaptureCountProvider.notifier).state = 0;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initCamera();
    });
  }

  Future<void> _initCamera() async {
    setState(() {
      _state = _CameraInitState.loading;
      _errorMessage = null;
    });

    _mlKitSubscription?.cancel();
    _mlKitSubscription = null;

    try {
      final mlKitService = ref.read(mlKitServiceProvider);
      await mlKitService.setAccurateMode(
        ref.read(accurateLiveDetectionProvider),
      );

      final cameraService = ref.read(cameraServiceProvider);
      await cameraService.init();
      ref.read(isFrontCameraProvider.notifier).state =
          cameraService.controller?.description.lensDirection ==
          CameraLensDirection.front;
      resetLiveAnalyzers(ref);
      ref.read(onFrameCallbackProvider.notifier).state = _onFrame;
      await cameraService.startImageStream(_onFrame);

      _mlKitSubscription = mlKitService.analysisStream.listen((result) {
        _latestMask = result.segmentationMask;
      });

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

    if (kDebugMode) {
      (_debugPerfOverlayKey.currentState as dynamic)?.registerFrame();
    }

    final now = DateTime.now();
    if (now.difference(_lastProcessed) < _throttleInterval) return;
    _lastProcessed = now;

    final trackingEngine = ref.read(trackingEngineProvider);

    final previousScene = ref.read(sceneProfileProvider);
    final rawScene = _lightAnalyzer.analyzeLight(
      image,
      previousScene,
      segmentationMask: _latestMask,
      subject: ref.read(subjectProfileProvider),
    );
    final smoothedScene = trackingEngine.smoothScene(rawScene, previousScene);
    ref.read(sceneProfileProvider.notifier).state = smoothedScene;

    final mlKitService = ref.read(mlKitServiceProvider);
    final cameraService = ref.read(cameraServiceProvider);
    final controller = cameraService.controller;
    if (controller == null) return;

    if (kDebugMode &&
        now.difference(_lastDebugSnapshotLog) >= _debugSnapshotLogInterval) {
      _lastDebugSnapshotLog = now;
      final subject = ref.read(subjectProfileProvider);
      debugPrint(
        'mirror_check: lens=${controller.description.lensDirection.name} '
        'deviceOrientation=${controller.value.deviceOrientation.name} '
        'shoulderAngleDegrees=${subject.shoulderAngleDegrees?.toStringAsFixed(1)} '
        'shoulderBalanceRatio=${subject.shoulderBalanceRatio?.toStringAsFixed(3)} '
        'faceAngleZDegrees(roll)=${subject.faceAngleZDegrees?.toStringAsFixed(1)} '
        'faceAngleDegrees(yaw)=${subject.faceAngleDegrees?.toStringAsFixed(1)} '
        'bodyYawEstimate=${subject.bodyYawEstimate?.toStringAsFixed(1)}',
      );

      final target = ref.read(targetSubjectProfileProvider);
      final scene = ref.read(sceneProfileProvider);
      final targetScene = ref.read(targetSceneProfileProvider);
      final progress = ref.read(trackingProgressProvider);
      String diff(String label, double? current, double? targetValue) {
        if (current == null || targetValue == null) {
          return '$label=n/a(current=$current,target=$targetValue)';
        }
        return '$label=${(current - targetValue).abs().toStringAsFixed(2)}'
            '(cur=${current.toStringAsFixed(2)},tgt=${targetValue.toStringAsFixed(2)})';
      }

      debugPrint(
        'auto_capture_check: trackingProgress=${progress.toStringAsFixed(3)} '
        '${diff('bodyRatio', subject.bodyRatio, target.bodyRatio)} '
        '${diff('shoulderAngle', subject.shoulderAngleDegrees, target.shoulderAngleDegrees)} '
        '${diff('shoulderBalance', subject.shoulderBalanceRatio, target.shoulderBalanceRatio)} '
        '${diff('bodyYaw', subject.bodyYawEstimate, target.bodyYawEstimate)} '
        '${diff('faceAngle', subject.faceAngleDegrees, target.faceAngleDegrees)} '
        '${diff('brightness', scene.brightness, targetScene.brightness)}',
      );
    }

    mlKitService.processImage(
      image,
      controller.description,
      controller.value.deviceOrientation,
    );
  }

  Future<void> _performCapture() async {
    final cameraService = ref.read(cameraServiceProvider);
    final imagePath = await cameraService.capture();
    if (!mounted) return;

    if (imagePath != null) {
      ref.read(appTtsServiceProvider).speak('Photo captured.', force: true);
    }

    if (cameraService.lastGallerySaveSucceeded == false) {
      ref.read(gallerySaveWarningProvider.notifier).state =
          gallerySaveFailedMessage;
    }

    final referenceAsync = ref.read(referenceProfileProvider);
    final reference = referenceAsync.valueOrNull;
    if (reference == null) return;
    final tolerance = ref.read(toleranceSettingsProvider);

    final subject = ref.read(subjectProfileProvider);
    final scene = ref.read(sceneProfileProvider);

    final shot = buildShotFromCapture(
      imagePath: imagePath,
      subject: subject,
      scene: scene,
      reference: reference,
      tolerance: tolerance,
      shotType: ref.read(selectedShotTypeProvider),
    );

    ref.read(albumStateProvider.notifier).addShot(shot);

    if (!mounted) return;
    setState(() {
      _hasCaptured = true;
      _lastCapturedScore = shot.score;
      _showFlash = true;
    });

    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    setState(() => _showFlash = false);
  }

  void _onAdjustmentsTap() {
    final colors = Theme.of(context).extension<AppColors>()!;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (sheetContext) {
        return const AdjustmentsSheet();
      },
    );
  }

  void _onModeSelectorTap() {
    final colors = Theme.of(context).extension<AppColors>()!;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (sheetContext) {
        return const ShotTypePickerSheet();
      },
    );
  }

  void _onReferencePhotoTap() {
    final colors = Theme.of(context).extension<AppColors>()!;
    _showReferencePicker(colors);
  }

  Future<void> _showReferencePicker(AppColors colors) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (sheetContext) {
        return const ReferencePickerSheet();
      },
    );
  }

  Future<void> _flipCamera() async {
    final cameraService = ref.read(cameraServiceProvider);
    if (!cameraService.hasMultipleCameras) return;

    await cameraService.stopImageStream();
    await cameraService.switchLens();
    ref.read(isFrontCameraProvider.notifier).state =
        cameraService.controller?.description.lensDirection ==
        CameraLensDirection.front;
    resetLiveAnalyzers(ref);

    if (!mounted) return;
    setState(() {});

    if (!mounted) return;
    await cameraService.startImageStream(_onFrame);
  }

  Future<void> _onScaleStart(ScaleStartDetails details) async {
    _baseZoom = _currentZoom;
  }

  Future<void> _onScaleUpdate(ScaleUpdateDetails details) async {
    final cameraService = ref.read(cameraServiceProvider);
    final controller = cameraService.controller;
    if (controller == null) return;

    final zoom = (_baseZoom * details.scale).clamp(
      cameraService.minZoom,
      cameraService.maxZoom,
    );
    if (zoom == _currentZoom) return;
    _currentZoom = zoom;
    try {
      await controller.setZoomLevel(zoom);
    } on CameraException {
      // unsupported, ignore
    }
  }

  Future<void> _onTapUp(TapUpDetails details, Offset? normalized) async {
    if (normalized == null) return;

    await ref.read(cameraServiceProvider).focusAndMeterAt(normalized);

    if (!mounted) return;
    setState(() => _focusPoint = details.localPosition);

    _focusRingTimer?.cancel();
    _focusRingTimer = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      setState(() => _focusPoint = null);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        // Actually backgrounded — safe to fully tear down.
        if (_state != _CameraInitState.ready) return;
        _mlKitSubscription?.cancel();
        _mlKitSubscription = null;
        _cameraDisposedForBackground = true;
        if (mounted) {
          setState(() => _state = _CameraInitState.loading);
        }
        ref.read(cameraServiceProvider).pauseCameras();
        break;

      case AppLifecycleState.inactive:
        if (_state == _CameraInitState.ready) {
          ref.read(cameraServiceProvider).stopImageStream();
        }
        break;

      case AppLifecycleState.resumed:
        if (_cameraDisposedForBackground) {
          _cameraDisposedForBackground = false;
          _initCamera();
        } else if (_state == _CameraInitState.ready) {
          ref.read(cameraServiceProvider).startImageStream(_onFrame);
        }
        break;

      default:
        break;
    }
  }

  @override
  void dispose() {
    _focusRingTimer?.cancel();
    _mlKitSubscription?.cancel();
    _cameraService.stopImageStream();
    WidgetsBinding.instance.removeObserver(this);
    _cameraService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;

    ref.watch(sceneAnalysisListenerProvider);
    // Bug found and fixed this session: this used to unconditionally watch
    // voiceDirectorListenerProvider (v1) regardless of the "Coaching v2
    // (experimental)" toggle in Settings — coachingV2SettingsProvider was
    // never read anywhere in this file, making that switch a dead control.
    // Now exactly one of the two listeners is watched, never both.
    if (ref.watch(coachingV2SettingsProvider).enabled) {
      ref.watch(voiceDirectorListenerV2Provider);
    } else {
      ref.watch(voiceDirectorListenerProvider);
    }
    ref.watch(mlKitAvailabilityListenerProvider);

    ref.listen<Shot?>(capturedShotProvider, (previous, shot) {
      if (shot == null) return;
      ref.read(albumStateProvider.notifier).addShot(shot);
      if (!mounted) return;
      setState(() {
        _hasCaptured = true;
        _lastCapturedScore = shot.score;
        _showFlash = true;
      });
      Future.delayed(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        setState(() => _showFlash = false);
      });
    });

    ref.watch(autoCaptureProvider);

    ref.listen<String?>(gallerySaveWarningProvider, (previous, message) {
      if (message == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
        ref.read(gallerySaveWarningProvider.notifier).state = null;
      });
    });

    ref.listen<bool>(accurateLiveDetectionProvider, (previous, next) {
      if (previous == next) return;
      ref.read(mlKitServiceProvider).setAccurateMode(next);
    });

    ref.listen<String?>(autoCaptureSessionMessageProvider, (previous, message) {
      if (message == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
        ref.read(autoCaptureSessionMessageProvider.notifier).state = null;
      });
    });

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

  Widget _buildReadyBody(AppColors colors) {
    final cameraService = ref.read(cameraServiceProvider);
    final controller = cameraService.controller;
    if (controller == null || !controller.value.isInitialized) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(colors.accent),
        ),
      );
    }

    final selectedReferencePath = ref.watch(selectedReferenceImagePathProvider);
    final mlKitUnavailable = ref.watch(mlKitUnavailableProvider);

    final topInset = MediaQuery.of(context).padding.top;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    const navBarHeight = 44.0;
    final clusterTop = topInset + AppSpacing.xs;
    final secondRowTop = clusterTop + navBarHeight + AppSpacing.sm;
    final phraseChipTop = secondRowTop + AppSpacing.sm;

    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreviewLayer(
          controller: controller,
          focusPoint: _focusPoint,
          accentColor: colors.accent,
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onTapUp: _onTapUp,
        ),
        if (kDebugMode && ref.watch(debugPerfOverlayEnabledProvider))
          DebugPerfOverlay(key: _debugPerfOverlayKey),
        if (mlKitUnavailable)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                color: colors.warning.withOpacity(0.9),
                child: Text(
                  'Pose/face detection is unavailable on this device. '
                  'Voice coaching and auto-capture are off — you can still '
                  'capture manually.',
                  textAlign: TextAlign.center,
                  style: AppTypography.caption(
                    colors,
                  ).copyWith(color: colors.background),
                ),
              ),
            ),
          ),
        Positioned(
          top: clusterTop,
          left: AppSpacing.md,
          right: AppSpacing.md,
          child: CameraTopNavBar(
            colors: colors,
            onAdjustmentsTap: _onAdjustmentsTap,
            onModeSelectorTap: _onModeSelectorTap,
            onReferencePhotoTap: _onReferencePhotoTap,
            onFlipCameraTap: _flipCamera,
            onAlbumTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const AlbumScreen())),
            canFlipCamera: cameraService.hasMultipleCameras,
          ),
        ),
        if (selectedReferencePath == null)
          Positioned(
            top: secondRowTop,
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
                  'Tap the reference icon to choose a photo',
                  style: AppTypography.caption(
                    colors,
                  ).copyWith(color: colors.accent),
                ),
              ),
            ),
          ),
        Positioned(
          top: phraseChipTop,
          left: AppSpacing.md,
          right: AppSpacing.md,
          child: Consumer(
            builder: (context, ref, _) {
              final nextAction = ref.watch(nextActionProvider);
              if (nextAction == null) return const SizedBox.shrink();
              final displayedPhrase =
                  ref.watch(displayedCoachingPhraseProvider) ??
                  nextAction.phrase;
              return Center(
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
                    displayedPhrase,
                    style: AppTypography.body(colors).copyWith(
                      color: colors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (_hasCaptured && _lastCapturedScore != null)
          Positioned(
            top: secondRowTop,
            right: AppSpacing.md,
            child: ScoreBadge(score: _lastCapturedScore!.overall),
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
