// core/services/ml_kit_service.dart
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';

class MlKitAnalysisResult {
  const MlKitAnalysisResult({this.poses, this.faces, this.segmentationMask});

  final List<Pose>? poses;
  final List<Face>? faces;
  final SegmentationMask? segmentationMask;
}

class MlKitService {
  final PoseDetector _poseDetector = PoseDetector(
    options: PoseDetectorOptions(mode: PoseDetectionMode.stream),
  );
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      enableTracking: true,
    ),
  );
  final SelfieSegmenter _segmenter = SelfieSegmenter(
    mode: SegmenterMode.stream,
    enableRawSizeMask: true,
  );

  final _resultController = StreamController<MlKitAnalysisResult>.broadcast();
  bool _busy = false;

  Stream<MlKitAnalysisResult> get analysisStream => _resultController.stream;

  Future<void> processImage(
    CameraImage image,
    CameraDescription description,
    InputImageRotation rotation,
  ) async {
    if (_busy) return;
    _busy = true;

    try {
      final inputImage = _toInputImage(image, rotation);
      if (inputImage == null) return;

      final poses = await _poseDetector.processImage(inputImage);
      final faces = await _faceDetector.processImage(inputImage);
      final mask = await _segmenter.processImage(inputImage);

      _resultController.add(
        MlKitAnalysisResult(poses: poses, faces: faces, segmentationMask: mask),
      );
    } finally {
      _busy = false;
    }
  }

  InputImage? _toInputImage(CameraImage image, InputImageRotation rotation) {
    final writeBuffer = WriteBuffer();
    for (final plane in image.planes) {
      writeBuffer.putUint8List(plane.bytes);
    }
    final bytes = writeBuffer.done().buffer.asUint8List();
    final metadata = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: InputImageFormat.nv21,
      bytesPerRow: image.planes.first.bytesPerRow,
    );
    return InputImage.fromBytes(bytes: bytes, metadata: metadata);
  }

  Future<void> dispose() async {
    await _poseDetector.close();
    await _faceDetector.close();
    await _segmenter.close();
    await _resultController.close();
  }
}

final mlKitServiceProvider = Provider<MlKitService>((ref) {
  final service = MlKitService();
  ref.onDispose(() => service.dispose());
  return service;
});
