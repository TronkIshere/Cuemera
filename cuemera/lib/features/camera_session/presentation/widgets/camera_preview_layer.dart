// features/camera_session/presentation/widgets/camera_preview_layer.dart
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

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
    required this.hasCaptured,
  });

  final CameraController controller;
  final Offset? focusPoint;
  final Color accentColor;
  final Future<void> Function(ScaleStartDetails) onScaleStart;
  final Future<void> Function(ScaleUpdateDetails) onScaleUpdate;
  final Future<void> Function(TapUpDetails, BoxConstraints) onTapUp;
  final bool hasCaptured;

  @override
  Widget build(BuildContext context) {
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
                  width: controller.value.previewSize?.height ?? 1,
                  height: controller.value.previewSize?.width ?? 1,
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
