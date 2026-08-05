// features/camera_session/presentation/widgets/camera_preview_layer.dart
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../reference_photo/domain/models/reference_profile.dart';
import '../../../reference_photo/providers/reference_providers.dart';
import 'focus_ring.dart';

class CameraPreviewLayer extends ConsumerWidget {
  const CameraPreviewLayer({
    super.key,
    required this.previewController,
    required this.focusPoint,
    required this.accentColor,
    required this.onScaleStart,
    required this.onScaleUpdate,
    required this.onTapUp,
    required this.hasCaptured,
  });

  final CameraController previewController;
  final Offset? focusPoint;
  final Color accentColor;
  final Future<void> Function(ScaleStartDetails) onScaleStart;
  final Future<void> Function(ScaleUpdateDetails) onScaleUpdate;
  final Future<void> Function(TapUpDetails, BoxConstraints) onTapUp;
  final bool hasCaptured;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reference = ref.watch(referenceProfileProvider).valueOrNull;

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: onScaleStart,
          onScaleUpdate: onScaleUpdate,
          onTapUp: (details) => onTapUp(details, constraints),
          child: Stack(
            fit: StackFit.expand,
            children: [
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: previewController.value.previewSize?.height ?? 1,
                  height: previewController.value.previewSize?.width ?? 1,
                  child: CameraPreview(previewController),
                ),
              ),
              if (reference != null &&
                  !hasCaptured &&
                  reference.imageWidth != null &&
                  reference.imageHeight != null)
                CustomPaint(
                  painter: _ReferenceContourPainter(reference: reference),
                ),
              if (focusPoint != null)
                FocusRing(center: focusPoint!, color: accentColor),
            ],
          ),
        );
      },
    );
  }
}

class _ReferenceContourPainter extends CustomPainter {
  _ReferenceContourPainter({required this.reference});

  final ReferenceProfile reference;

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / reference.imageWidth!;
    final scaleY = size.height / reference.imageHeight!;

    final paint = Paint()
      ..color = Colors.white.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    void drawContour(List<Offset>? points) {
      if (points == null || points.isEmpty) return;
      final path = Path();
      path.moveTo(points.first.dx * scaleX, points.first.dy * scaleY);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx * scaleX, point.dy * scaleY);
      }
      canvas.drawPath(path, paint);
    }

    drawContour(reference.faceOvalPoints);
    drawContour(reference.leftEyeContour);
    drawContour(reference.rightEyeContour);
    drawContour(reference.leftEyebrowTopContour);
    drawContour(reference.rightEyebrowTopContour);
    drawContour(reference.upperLipTopContour);
    drawContour(reference.upperLipBottomContour);
    drawContour(reference.lowerLipTopContour);
    drawContour(reference.lowerLipBottomContour);
    drawContour(reference.noseBridgeContour);
    drawContour(reference.noseBottomContour);
  }

  @override
  bool shouldRepaint(covariant _ReferenceContourPainter oldDelegate) {
    return oldDelegate.reference.imagePath != reference.imagePath;
  }
}
