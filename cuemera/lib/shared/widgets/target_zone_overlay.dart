// shared/widgets/target_zone_overlay.dart
import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

class TargetZoneOverlay extends StatelessWidget {
  const TargetZoneOverlay({super.key, required this.aligned, this.zoneRect});

  final bool aligned;
  final Rect? zoneRect;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;

    return CustomPaint(
      painter: _TargetZonePainter(
        color: aligned ? colors.success : colors.targetZone,
        zoneRect: zoneRect,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _TargetZonePainter extends CustomPainter {
  _TargetZonePainter({required this.color, this.zoneRect});

  final Color color;
  final Rect? zoneRect;

  @override
  void paint(Canvas canvas, Size size) {
    final rect =
        zoneRect ??
        Rect.fromCenter(
          center: Offset(size.width / 2, size.height / 2),
          width: size.width * 0.6,
          height: size.height * 0.45,
        );

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(24));
    canvas.drawRRect(rrect, paint);

    const cornerLength = 24.0;
    final cornerPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    void drawCorner(Offset origin, Offset dx, Offset dy) {
      canvas.drawLine(origin, origin + dx, cornerPaint);
      canvas.drawLine(origin, origin + dy, cornerPaint);
    }

    drawCorner(
      rect.topLeft,
      const Offset(cornerLength, 0),
      const Offset(0, cornerLength),
    );
    drawCorner(
      rect.topRight,
      const Offset(-cornerLength, 0),
      const Offset(0, cornerLength),
    );
    drawCorner(
      rect.bottomLeft,
      const Offset(cornerLength, 0),
      const Offset(0, -cornerLength),
    );
    drawCorner(
      rect.bottomRight,
      const Offset(-cornerLength, 0),
      const Offset(0, -cornerLength),
    );
  }

  @override
  bool shouldRepaint(covariant _TargetZonePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.zoneRect != zoneRect;
  }
}
