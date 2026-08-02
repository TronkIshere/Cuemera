// features/scene_analysis/services/light_analyzer.dart
import 'package:camera/camera.dart';

import '../domain/models/scene_profile.dart';

class LightAnalyzer {
  SceneProfile analyzeLight(dynamic cameraFrame, SceneProfile previous) {
    final image = cameraFrame as CameraImage?;
    if (image == null) return previous;

    final brightness = _estimateBrightness(image);

    return previous.copyWith(brightness: brightness);
  }

  double _estimateBrightness(CameraImage image) {
    final plane = image.planes.first;
    final bytes = plane.bytes;
    if (bytes.isEmpty) return 0.5;

    final sampleStep = (bytes.length / 2000).clamp(1, bytes.length).toInt();
    int sum = 0;
    int count = 0;

    for (var i = 0; i < bytes.length; i += sampleStep) {
      sum += bytes[i];
      count++;
    }

    if (count == 0) return 0.5;
    return (sum / count) / 255.0;
  }
}
