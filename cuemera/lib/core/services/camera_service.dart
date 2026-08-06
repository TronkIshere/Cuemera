// core/services/camera_service.dart
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';

import 'error_reporting_service.dart';

class CameraService {
  CameraController? _controller;
  CameraController? _previewController;
  List<CameraDescription> _cameras = [];
  int _lensIndex = 0;

  CameraController? get controller => _controller;
  CameraController? get previewController => _previewController;
  CameraDescription? get activeCameraDescription =>
      _controller != null && _cameras.isNotEmpty ? _cameras[_lensIndex] : null;
  bool get isInitialized => _controller?.value.isInitialized ?? false;
  bool get isPreviewInitialized =>
      _previewController?.value.isInitialized ?? false;
  bool get hasMultipleCameras => _cameras.length > 1;

  double _minZoom = 1.0;
  double _maxZoom = 1.0;

  double get minZoom => _minZoom;
  double get maxZoom => _maxZoom;

  /// Wall-clock time the most recent [capture] spent creating+initializing
  /// the temporary max-resolution `CameraController`, from the moment the
  /// live stream was stopped to the moment `initialize()` returned.
  Duration? lastCaptureControllerSetupLatency;

  /// Wall-clock time the most recent [capture] spent inside
  /// `takePicture()` itself, once the temporary controller was ready.
  Duration? lastCaptureShutterLatency;

  /// Wall-clock time the most recent [capture] spent disposing the
  /// temporary controller.
  Duration? lastCaptureControllerTeardownLatency;

  /// Whether the most recent [capture] successfully saved to the device
  /// gallery. `null` means no capture has completed yet; `false` covers
  /// both a denied gallery permission and a thrown `Gal` exception.
  bool? lastGallerySaveSucceeded;

  Future<void> init() async {
    _cameras = await availableCameras();
    if (_cameras.isEmpty) return;
    await _createController(_cameras[_lensIndex]);
  }

  Future<void> _createController(CameraDescription description) async {
    await _controller?.dispose();
    _controller = CameraController(
      description,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );
    await _controller!.initialize();
  }

  Future<void> initPreviewController() async {
    if (_cameras.isEmpty) return;
    await _previewController?.dispose();
    _previewController = CameraController(
      _cameras[_lensIndex],
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );
    await _previewController!.initialize();
    _minZoom = await _previewController!.getMinZoomLevel();
    _maxZoom = await _previewController!.getMaxZoomLevel();
  }

  Future<String?> capture() async {
    if (!isInitialized || _controller!.value.isTakingPicture) return null;

    if (_controller!.value.isStreamingImages) {
      await _controller!.stopImageStream();
    }

    final description = _cameras[_lensIndex];
    final captureController = CameraController(
      description,
      ResolutionPreset.max,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );

    String? path;
    final setupStopwatch = Stopwatch()..start();
    try {
      await captureController.initialize();
      setupStopwatch.stop();
      lastCaptureControllerSetupLatency = setupStopwatch.elapsed;

      final shutterStopwatch = Stopwatch()..start();
      final file = await captureController.takePicture();
      shutterStopwatch.stop();
      lastCaptureShutterLatency = shutterStopwatch.elapsed;

      path = file.path;
    } finally {
      final teardownStopwatch = Stopwatch()..start();
      await captureController.dispose();
      teardownStopwatch.stop();
      lastCaptureControllerTeardownLatency = teardownStopwatch.elapsed;

      debugPrint(
        '[CameraService] capture() latency — '
        'setup: ${lastCaptureControllerSetupLatency?.inMilliseconds}ms, '
        'shutter: ${lastCaptureShutterLatency?.inMilliseconds}ms, '
        'teardown: ${lastCaptureControllerTeardownLatency?.inMilliseconds}ms',
      );
    }

    if (path != null) {
      try {
        final hasAccess = await Gal.requestAccess();
        if (hasAccess) {
          await Gal.putImage(path);
          lastGallerySaveSucceeded = true;
        } else {
          lastGallerySaveSucceeded = false;
        }
      } catch (e, st) {
        lastGallerySaveSucceeded = false;
        ErrorReportingService.instance.report(
          e,
          st,
          context: 'CameraService: gallery save',
        );
      }
    }

    return path;
  }

  Future<void> switchLens() async {
    if (_cameras.length < 2) return;
    _lensIndex = (_lensIndex + 1) % _cameras.length;
    await _createController(_cameras[_lensIndex]);
    await initPreviewController();
  }

  Future<void> startImageStream(
    void Function(CameraImage image) onImage,
  ) async {
    if (!isInitialized || _controller!.value.isStreamingImages) return;
    await _controller!.startImageStream(onImage);
  }

  Future<void> stopImageStream() async {
    if (isInitialized && _controller!.value.isStreamingImages) {
      await _controller!.stopImageStream();
    }
  }

  Future<void> dispose() async {
    await stopImageStream();
    await _controller?.dispose();
    _controller = null;
    await _previewController?.dispose();
    _previewController = null;
  }
}

final cameraServiceProvider = Provider<CameraService>((ref) {
  final service = CameraService();
  ref.onDispose(() => service.dispose());
  return service;
});
