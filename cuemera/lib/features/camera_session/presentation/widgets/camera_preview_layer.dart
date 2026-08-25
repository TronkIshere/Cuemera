// features/camera_session/presentation/widgets/camera_preview_layer.dart
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation;

import 'focus_ring.dart';

class CameraPreviewLayer extends StatelessWidget {
  const CameraPreviewLayer({
    super.key,
    required this.controller,
    required this.focusPoint,
    required this.accentColor,
    required this.onScaleStart,
    required this.onScaleUpdate,
    required this.onTapUp,
  });

  final CameraController controller;
  final Offset? focusPoint;
  final Color accentColor;
  final Future<void> Function(ScaleStartDetails) onScaleStart;
  final Future<void> Function(ScaleUpdateDetails) onScaleUpdate;
  final Future<void> Function(TapUpDetails details, Offset? normalized) onTapUp;

  static Size? layoutPreviewSize(CameraController controller) {
    final raw = controller.value.previewSize;
    if (raw == null) return null;

    final longEdge = math.max(raw.width, raw.height);
    final shortEdge = math.min(raw.width, raw.height);

    final applied =
        controller.value.lockedCaptureOrientation ??
        controller.value.deviceOrientation;
    final isPortrait =
        applied == DeviceOrientation.portraitUp ||
        applied == DeviceOrientation.portraitDown;

    return isPortrait ? Size(shortEdge, longEdge) : Size(longEdge, shortEdge);
  }

  static Offset? normalizedPointFor({
    required Offset localPosition,
    required Size viewport,
    required Size preview,
  }) {
    if (viewport.isEmpty || preview.isEmpty) return null;

    final scale = math.max(
      viewport.width / preview.width,
      viewport.height / preview.height,
    );
    final shownWidth = preview.width * scale;
    final shownHeight = preview.height * scale;
    final croppedX = (shownWidth - viewport.width) / 2;
    final croppedY = (shownHeight - viewport.height) / 2;

    final x = (localPosition.dx + croppedX) / shownWidth;
    final y = (localPosition.dy + croppedY) / shownHeight;
    if (x < 0 || x > 1 || y < 0 || y > 1) return null;
    return Offset(x, y);
  }

  @override
  Widget build(BuildContext context) {
    final preview = layoutPreviewSize(controller);

    if (preview == null) {
      return const ColoredBox(color: Colors.black);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: onScaleStart,
          onScaleUpdate: onScaleUpdate,
          onTapUp: (details) => onTapUp(
            details,
            normalizedPointFor(
              localPosition: details.localPosition,
              viewport: viewport,
              preview: preview,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: preview.width,
                  height: preview.height,
                  child: CameraPreview(controller),
                ),
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
