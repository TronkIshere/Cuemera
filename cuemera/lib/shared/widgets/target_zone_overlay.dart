// shared/widgets/target_zone_overlay.dart
import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

class TargetZoneOverlay extends StatefulWidget {
  const TargetZoneOverlay({
    super.key,
    required this.aligned,
    required this.trackingProgress,
    this.zoneRect,
  });

  final bool aligned;
  final double trackingProgress;
  final Rect? zoneRect;

  @override
  State<TargetZoneOverlay> createState() => _TargetZoneOverlayState();
}

class _TargetZoneOverlayState extends State<TargetZoneOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  static const double _readyThreshold = 0.95;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant TargetZoneOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPulse();
  }

  void _syncPulse() {
    if (widget.trackingProgress >= _readyThreshold) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final baseColor = widget.aligned ? colors.success : colors.targetZone;

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(scale: _pulseAnimation.value, child: child);
      },
      child: CustomPaint(
        painter: _TargetZonePainter(
          color: baseColor,
          progress: widget.trackingProgress,
          zoneRect: widget.zoneRect,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _TargetZonePainter extends CustomPainter {
  _TargetZonePainter({
    required this.color,
    required this.progress,
    this.zoneRect,
  });

  final Color color;
  final double progress;
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

    final clampedProgress = progress.clamp(0.0, 1.0);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(24));

    if (clampedProgress > 0.15) {
      final fillPaint = Paint()
        ..color = color.withOpacity(clampedProgress * 0.25)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(rrect, fillPaint);
    }

    final strokeWidth = 2.0 + clampedProgress * 4.0;
    final strokeOpacity = 0.35 + clampedProgress * 0.65;

    final paint = Paint()
      ..color = color.withOpacity(strokeOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawRRect(rrect, paint);

    const cornerLength = 24.0;
    final cornerPaint = Paint()
      ..color = color.withOpacity(strokeOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 1
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
    return oldDelegate.color != color ||
        oldDelegate.progress != progress ||
        oldDelegate.zoneRect != zoneRect;
  }
}
