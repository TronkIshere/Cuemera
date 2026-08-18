// core/services/camera_service.dart
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';

import 'error_reporting_service.dart';

class CameraService {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _lensIndex = 0;

  void Function(CameraImage image)? _onImage;

  CameraController? get controller => _controller;
  CameraDescription? get activeCameraDescription =>
      _controller != null && _cameras.isNotEmpty ? _cameras[_lensIndex] : null;
  bool get isInitialized => _controller?.value.isInitialized ?? false;
  bool get hasMultipleCameras => _cameras.length > 1;

  double _minZoom = 1.0;
  double _maxZoom = 1.0;

  double get minZoom => _minZoom;
  double get maxZoom => _maxZoom;

  Duration? lastCaptureControllerSetupLatency;
  Duration? lastCaptureShutterLatency;
  Duration? lastCaptureControllerTeardownLatency;
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
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
    await _controller!.initialize();
    _minZoom = await _controller!.getMinZoomLevel();
    _maxZoom = await _controller!.getMaxZoomLevel();
  }

  Future<String?> capture() async {
    if (!isInitialized || _controller!.value.isTakingPicture) {
      return null;
    }

    final wasStreaming = _controller!.value.isStreamingImages;
    if (wasStreaming) {
      await _controller!.stopImageStream();
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
