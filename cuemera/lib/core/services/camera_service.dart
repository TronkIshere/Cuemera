// core/services/camera_service.dart
import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:ui' show Offset;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';

import 'error_reporting_service.dart';

enum CameraQuality {
  balanced(ResolutionPreset.high),
  sharp(ResolutionPreset.veryHigh);

  const CameraQuality(this.preset);

  final ResolutionPreset preset;
}

class CameraService {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _lensIndex = 0;

  CameraQuality _quality = CameraQuality.sharp;
  CameraQuality get quality => _quality;

  void Function(CameraImage image)? _onImage;

  CameraController? get controller => _controller;
  CameraDescription? get activeCameraDescription =>
      _controller != null && _cameras.isNotEmpty ? _cameras[_lensIndex] : null;
  bool get isInitialized => _controller?.value.isInitialized ?? false;
  bool get hasMultipleCameras => _cameras.length > 1;

  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _currentZoom = 1.0;

  double get minZoom => _minZoom;
  double get maxZoom => _maxZoom;
  double get currentZoom => _currentZoom;

  Duration? lastCaptureControllerSetupLatency;
  Duration? lastCaptureShutterLatency;
  Duration? lastCaptureControllerTeardownLatency;
  bool? lastGallerySaveSucceeded;

  Timer? _refocusTimer;

  static const Duration _refocusToContinuousDelay = Duration(seconds: 3);
  static const Duration _preCaptureSettleDelay = Duration(milliseconds: 150);

  Future<void> init() async {
    _cameras = await availableCameras();
    if (_cameras.isEmpty) return;
    await _createController(_cameras[_lensIndex]);
  }

  Future<void> setQuality(CameraQuality quality) async {
    if (quality == _quality) return;
    _quality = quality;
    if (_cameras.isEmpty) return;
    await _createController(_cameras[_lensIndex]);
  }

  Future<void> _createController(CameraDescription description) async {
    _refocusTimer?.cancel();
    await _controller?.dispose();
    _controller = CameraController(
      description,
      _quality.preset,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
    await _controller!.initialize();

    _minZoom = await _controller!.getMinZoomLevel();
    _maxZoom = await _controller!.getMaxZoomLevel();
    _currentZoom = _minZoom;

    await _applyContinuousFocusAndExposure();

    _logNegotiatedConfig(description);
  }

  Future<void> _applyContinuousFocusAndExposure() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await controller.setFocusMode(FocusMode.auto);
    } on CameraException catch (e) {
      debugPrint(
        '[CameraService] setFocusMode(auto) failed: ${e.code} ${e.description}',
      );
    }
    try {
      await controller.setExposureMode(ExposureMode.auto);
    } on CameraException catch (e) {
      debugPrint(
        '[CameraService] setExposureMode(auto) failed: '
        '${e.code} ${e.description}',
      );
    }
  }

  void _logNegotiatedConfig(CameraDescription description) {
    if (!kDebugMode) return;
    final value = _controller?.value;
    if (value == null) return;
    final size = value.previewSize;
    debugPrint(
      'camera_config: lens=${description.lensDirection.name} '
      'sensorOrientation=${description.sensorOrientation} '
      'requestedPreset=${_quality.preset.name} '
      'previewSize=${size?.width.toInt()}x${size?.height.toInt()} '
      'aspectRatio=${value.aspectRatio.toStringAsFixed(3)} '
      'focusPointSupported=${value.focusPointSupported} '
      'exposurePointSupported=${value.exposurePointSupported} '
      'zoomRange=[${_minZoom.toStringAsFixed(2)}..'
      '${_maxZoom.toStringAsFixed(2)}]',
    );
  }

  Future<void> setZoom(double zoom) async {
    final controller = _controller;
    if (controller == null || !isInitialized) return;
    final clamped = zoom.clamp(_minZoom, _maxZoom);
    if ((clamped - _currentZoom).abs() < 0.01) return;
    _currentZoom = clamped;
    try {
      await controller.setZoomLevel(clamped);
    } on CameraException catch (e) {
      debugPrint(
        '[CameraService] setZoomLevel($clamped) failed: '
        '${e.code} ${e.description}',
      );
    }
  }

  Future<void> focusAndMeterAt(Offset normalized) async {
    final controller = _controller;
    if (controller == null || !isInitialized) return;

    _refocusTimer?.cancel();

    if (controller.value.focusPointSupported) {
      try {
        await controller.setFocusPoint(normalized);
        await controller.setFocusMode(FocusMode.locked);
      } on CameraException catch (e) {
        debugPrint(
          '[CameraService] setFocusPoint failed: ${e.code} ${e.description}',
        );
      }
    } else {
      debugPrint(
        '[CameraService] focusPointSupported=false — tap-to-focus is a no-op '
        'on this device',
      );
    }

    if (controller.value.exposurePointSupported) {
      try {
        await controller.setExposurePoint(normalized);
      } on CameraException catch (e) {
        debugPrint(
          '[CameraService] setExposurePoint failed: '
          '${e.code} ${e.description}',
        );
      }
    }

    _refocusTimer = Timer(_refocusToContinuousDelay, () async {
      final live = _controller;
      if (live == null || !live.value.isInitialized) return;
      try {
        await live.setFocusPoint(null);
      } on CameraException {
        return;
      }
      await _applyContinuousFocusAndExposure();
    });
  }

  Future<String?> capture() async {
    if (!isInitialized || _controller!.value.isTakingPicture) {
      return null;
    }

    final wasStreaming = _controller!.value.isStreamingImages;
    if (wasStreaming) {
      await _controller!.stopImageStream();
      await Future<void>.delayed(_preCaptureSettleDelay);
    }

    lastCaptureControllerSetupLatency = Duration.zero;
    lastCaptureControllerTeardownLatency = Duration.zero;

    String? path;
    try {
      final shutterStopwatch = Stopwatch()..start();
      final file = await _controller!.takePicture();
      shutterStopwatch.stop();
      lastCaptureShutterLatency = shutterStopwatch.elapsed;

      path = file.path;
    } finally {
      debugPrint(
        '[CameraService] capture() latency — '
        'shutter: ${lastCaptureShutterLatency?.inMilliseconds}ms '
        '(single shared controller — no separate setup/teardown)',
      );
      if (wasStreaming && _onImage != null && isInitialized) {
        await _controller!.startImageStream(_onImage!);
      }
    }

    if (kDebugMode && path != null) {
      try {
        final bytes = await File(path).length();
        debugPrint(
          'camera_config: still written ${(bytes / 1024).round()}KB at preset '
          '${_quality.preset.name}',
        );
      } catch (_) {
        // Diagnostics only.
      }
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

  Future<void> pauseCameras() async {
    _refocusTimer?.cancel();
    await stopImageStream();
    await _controller?.dispose();
    _controller = null;
  }

  Future<void> resumeCameras() async {
    if (_cameras.isEmpty) return;
    await _createController(_cameras[_lensIndex]);
  }

  Future<void> switchLens() async {
    if (_cameras.length < 2) return;
    _lensIndex = (_lensIndex + 1) % _cameras.length;
    await _createController(_cameras[_lensIndex]);
  }

  Future<void> startImageStream(
    void Function(CameraImage image) onImage,
  ) async {
    _onImage = onImage;
    if (!isInitialized || _controller!.value.isStreamingImages) return;
    await _controller!.startImageStream(onImage);
  }

  Future<void> stopImageStream() async {
    if (isInitialized && _controller!.value.isStreamingImages) {
      await _controller!.stopImageStream();
    }
  }

  Future<void> dispose() async {
    _refocusTimer?.cancel();
    await stopImageStream();
    await _controller?.dispose();
    _controller = null;
  }
}

final cameraServiceProvider = Provider<CameraService>((ref) {
  final service = CameraService();
  ref.onDispose(() => service.dispose());
  return service;
});
