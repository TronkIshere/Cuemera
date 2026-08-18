// core/services/ml_kit_service.dart
import 'dart:async';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';

import 'error_reporting_service.dart';

class MlKitAnalysisResult {
  const MlKitAnalysisResult({this.poses, this.faces, this.segmentationMask});

  final List<Pose>? poses;
  final List<Face>? faces;
  final SegmentationMask? segmentationMask;
}

const Map<DeviceOrientation, int> _androidRotationCompensation = {
  DeviceOrientation.portraitUp: 0,
  DeviceOrientation.landscapeLeft: 90,
  DeviceOrientation.portraitDown: 180,
  DeviceOrientation.landscapeRight: 270,
};

class MlKitService {
  PoseDetector _poseDetector = PoseDetector(
    options: PoseDetectorOptions(
      mode: PoseDetectionMode.stream,
      model: PoseDetectionModel.base,
    ),
  );
  FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      enableTracking: true,
      enableClassification: false,
    ),
  );
  final SelfieSegmenter _segmenter = SelfieSegmenter(
    mode: SegmenterMode.stream,
    enableRawSizeMask: true,
  );

  bool _accurateMode = false;
  bool get accurateMode => _accurateMode;

  static const bool debugLogFrameTiming = false;
  static const bool debugLogRotation = false;
  int? lastProcessImageMicros;

  final _resultController = StreamController<MlKitAnalysisResult>.broadcast();
  final _availabilityController = StreamController<bool>.broadcast();
  bool _busy = false;

  static const int _maxConsecutiveFailuresBeforeFlagging = 5;
  int _consecutiveFailures = 0;
  bool _flaggedUnavailable = false;

  Stream<MlKitAnalysisResult> get analysisStream => _resultController.stream;

  Stream<bool> get unavailableStream => _availabilityController.stream;

  Future<void> setAccurateMode(bool accurate) async {
    if (accurate == _accurateMode) return;

    while (_busy) {
      await Future.delayed(const Duration(milliseconds: 10));
    }

    final oldPoseDetector = _poseDetector;
    final oldFaceDetector = _faceDetector;

    _poseDetector = PoseDetector(
      options: PoseDetectorOptions(
        mode: PoseDetectionMode.stream,
        model: accurate ? PoseDetectionModel.accurate : PoseDetectionModel.base,
      ),
    );
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: accurate
            ? FaceDetectorMode.accurate
            : FaceDetectorMode.fast,
        enableTracking: true,
        enableClassification: false,
      ),
    );
    _accurateMode = accurate;

    await oldPoseDetector.close();
    await oldFaceDetector.close();

    debugPrint(
      'MlKitService: switched live detection to '
      '${accurate ? 'accurate' : 'fast'} model',
    );
  }

  @visibleForTesting
  InputImageRotation? rotationFor(
    CameraDescription description,
    DeviceOrientation deviceOrientation,
  ) {
    if (Platform.isIOS) {
      final result = InputImageRotationValue.fromRawValue(
        description.sensorOrientation,
      );
      if (debugLogRotation) {
        debugPrint(
          'MlKitService.rotationFor(): platform=iOS '
          'lens=${description.lensDirection.name} '
          'sensorOrientation=${description.sensorOrientation} -> '
          'result=${result?.rawValue}',
        );
      }
      return result;
    }

    final deviceRotation = _androidRotationCompensation[deviceOrientation];
    if (deviceRotation == null) {
      if (debugLogRotation) {
        debugPrint(
          'MlKitService.rotationFor(): platform=Android '
          'deviceOrientation=${deviceOrientation.name} has no compensation '
          'entry -> result=null',
        );
      }
      return null;
    }

    final int rotationCompensation;
    if (description.lensDirection == CameraLensDirection.front) {
      rotationCompensation =
          (description.sensorOrientation + deviceRotation) % 360;
    } else {
      rotationCompensation =
          (description.sensorOrientation - deviceRotation + 360) % 360;
    }
    final result = InputImageRotationValue.fromRawValue(rotationCompensation);
    if (debugLogRotation) {
      debugPrint(
        'MlKitService.rotationFor(): platform=Android '
        'lens=${description.lensDirection.name} '
        'sensorOrientation=${description.sensorOrientation} '
        'deviceOrientation=${deviceOrientation.name} '
        'deviceRotationCompensation=$deviceRotation '
        'rotationCompensation=$rotationCompensation -> '
        'result=${result?.rawValue}',
      );
    }
    return result;
  }

  Future<void> processImage(
    CameraImage image,
    CameraDescription description,
    DeviceOrientation deviceOrientation,
  ) async {
    if (_busy) return;
    _busy = true;

    try {
      final rotation = rotationFor(description, deviceOrientation);
      if (rotation == null) return;

      final inputImage = _toInputImage(image, rotation);
      if (inputImage == null) return;

      final stopwatch = debugLogFrameTiming ? (Stopwatch()..start()) : null;

      final posesFuture = _poseDetector.processImage(inputImage);
      final facesFuture = _faceDetector.processImage(inputImage);
      final maskFuture = _segmenter.processImage(inputImage);

      final poses = await posesFuture;
      final faces = await facesFuture;
      final mask = await maskFuture;

      if (stopwatch != null) {
        stopwatch.stop();
        lastProcessImageMicros = stopwatch.elapsedMicroseconds;
        debugPrint(
          '[MlKitService] processImage: pose+face+mask concurrent wait took '
          '${stopwatch.elapsedMicroseconds}us (accurateMode=$_accurateMode)',
        );
      }

      _resultController.add(
        MlKitAnalysisResult(poses: poses, faces: faces, segmentationMask: mask),
      );

      if (_consecutiveFailures > 0 || _flaggedUnavailable) {
        _consecutiveFailures = 0;
        if (_flaggedUnavailable) {
          _flaggedUnavailable = false;
          _availabilityController.add(false);
        }
      }
    } catch (e, st) {
      ErrorReportingService.instance.report(
        e,
        st,
        context: 'MlKitService: processImage',
      );

      _consecutiveFailures++;
      if (!_flaggedUnavailable &&
          _consecutiveFailures >= _maxConsecutiveFailuresBeforeFlagging) {
        _flaggedUnavailable = true;
        _availabilityController.add(true);
      }
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
      format: Platform.isAndroid
          ? InputImageFormat.nv21
          : InputImageFormat.bgra8888,
      bytesPerRow: image.planes.first.bytesPerRow,
    );
    return InputImage.fromBytes(bytes: bytes, metadata: metadata);
  }

  Future<void> dispose() async {
    await _poseDetector.close();
    await _faceDetector.close();
    await _segmenter.close();
    await _resultController.close();
    await _availabilityController.close();
  }
}

final mlKitServiceProvider = Provider<MlKitService>((ref) {
  final service = MlKitService();
  ref.onDispose(() => service.dispose());
  return service;
});
