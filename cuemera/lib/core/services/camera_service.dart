// core/services/camera_service.dart
import 'package:camera/camera.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CameraService {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _lensIndex = 0;

  CameraController? get controller => _controller;
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  Future<void> init() async {
    _cameras = await availableCameras();
    if (_cameras.isEmpty) return;
    await _createController(_cameras[_lensIndex]);
  }

  Future<void> _createController(CameraDescription description) async {
    await _controller?.dispose();
    _controller = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );
    await _controller!.initialize();
  }

  Future<String?> capture() async {
    if (!isInitialized || _controller!.value.isTakingPicture) return null;
    if (_controller!.value.isStreamingImages) {
      await _controller!.stopImageStream();
    }
    final file = await _controller!.takePicture();
    return file.path;
  }

  Future<void> switchLens() async {
    if (_cameras.length < 2) return;
    _lensIndex = (_lensIndex + 1) % _cameras.length;
    await _createController(_cameras[_lensIndex]);
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
  }
}

final cameraServiceProvider = Provider<CameraService>((ref) {
  final service = CameraService();
  ref.onDispose(() => service.dispose());
  return service;
});
