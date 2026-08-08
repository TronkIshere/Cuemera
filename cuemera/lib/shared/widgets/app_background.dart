// shared/widgets/app_background.dart
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final brightness = Theme.of(context).brightness;

    if (brightness != Brightness.dark) {
      return Container(color: colors.background, child: child);
    }

    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                return CustomPaint(
                  size: size,
                  painter: _BackgroundPainter(
                    size: size,
                    background: colors.background,
                    surface: colors.surface,
                    accent: colors.accent,
                    brightness: brightness,
                  ),
                );
              },
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  _BackgroundPainter({
    required this.size,
    required this.background,
    required this.surface,
    required this.accent,
    required this.brightness,
  });

  final Size size;
  final Color background;
  final Color surface;
  final Color accent;
  final Brightness brightness;

  @override
  void paint(Canvas canvas, Size size) {
    final isLandscape = size.width > size.height;

    _paintBaseGradient(canvas, size);
    _paintSecondaryGlow(canvas, size);
    _paintCounterGlow(canvas, size);

    if (isLandscape) {
      _paintLandscapeElements(canvas, size);
    } else {
      _paintPortraitElements(canvas, size);
    }
  }

  void _paintBaseGradient(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final origin = Offset(size.width * 0.08, size.height * 0.12);
    final focal = Offset(size.width * 0.72, size.height * 0.88);
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        origin,
        focal,
        const [
          Color(0xFF232329),
          Color(0xFF1C1C22),
          Color(0xFF18181E),
          Color(0xFF14141A),
        ],
        const [0.0, 0.3, 0.65, 1.0],
      );
    canvas.drawRect(rect, paint);
  }

  void _paintSecondaryGlow(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.12, size.height * 0.16);
    final radius = size.width * 0.75;
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [accent.withOpacity(0.05), accent.withOpacity(0)],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 80);
    canvas.drawCircle(center, radius, paint);
  }

  void _paintCounterGlow(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.9, size.height * 0.74);
    final radius = size.width * 0.35;
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [surface.withOpacity(0.025), surface.withOpacity(0)],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60);
    canvas.drawCircle(center, radius, paint);
  }

  void _paintPortraitElements(Canvas canvas, Size size) {
    _drawSoftboxEcho(
      canvas,
      size,
      Offset(size.width * 0.1, size.height * 0.15),
      size.width * 0.61,
    );

    _drawStrokedRect(
      canvas,
      Offset(size.width * 0.74, size.height * 0.36),
      Size(size.width * 0.36, size.height * 0.52),
      -4,
      accent.withOpacity(0.06),
    );

    _drawStrokedRect(
      canvas,
      Offset(size.width * 0.16, size.height * 0.7),
      Size(size.width * 0.18, size.height * 0.22),
      3,
      accent.withOpacity(0.07),
    );

    _drawFilledRect(
      canvas,
      Offset(size.width * 0.7, size.height * 0.1),
      Size(size.width * 0.48, size.height * 0.08),
      -8,
      surface.withOpacity(0.035),
    );

    _drawFilledRect(
      canvas,
      Offset(size.width * 0.46, size.height * 0.9),
      Size(size.width * 0.12, size.width * 0.12),
      2,
      accent.withOpacity(0.025),
    );

    _drawCornerBracket(
      canvas,
      Offset(size.width * 0.84, size.height * 0.18),
      size.width * 0.12,
      accent.withOpacity(0.05),
    );
  }

  void _paintLandscapeElements(Canvas canvas, Size size) {
    _drawSoftboxEcho(
      canvas,
      size,
      Offset(size.width * 0.05, size.height * 0.18),
      size.width * 0.42,
    );

    _drawStrokedRect(
      canvas,
      Offset(size.width * 0.74, size.height * 0.36),
      Size(size.width * 0.42, size.height * 0.34),
      -4,
      accent.withOpacity(0.06),
    );

    _drawStrokedRect(
      canvas,
      Offset(size.width * 0.16, size.height * 0.72),
      Size(size.width * 0.16, size.height * 0.16),
      3,
      accent.withOpacity(0.07),
    );

    _drawFilledRect(
      canvas,
      Offset(size.width * 0.7, size.height * 0.1),
      Size(size.width * 0.48, size.height * 0.055),
      -8,
      surface.withOpacity(0.035),
    );

    _drawFilledRect(
      canvas,
      Offset(size.width * 0.6, size.height * 0.9),
      Size(size.width * 0.08, size.width * 0.08),
      2,
      accent.withOpacity(0.025),
    );

    _drawCornerBracket(
      canvas,
      Offset(size.width * 0.84, size.height * 0.18),
      size.width * 0.08,
      accent.withOpacity(0.05),
    );
  }

  void _drawSoftboxEcho(
    Canvas canvas,
    Size size,
    Offset center,
    double diameter,
  ) {
    final radius = diameter / 2;
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [accent.withOpacity(0.03), accent.withOpacity(0)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
  }

  void _drawFilledRect(
    Canvas canvas,
    Offset center,
    Size rectSize,
    double rotationDegrees,
    Color color,
  ) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotationDegrees * 3.1415926535 / 180);
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset.zero,
        width: rectSize.width,
        height: rectSize.height,
      ),
      paint,
    );
    canvas.restore();
  }

  void _drawStrokedRect(
    Canvas canvas,
    Offset center,
    Size rectSize,
    double rotationDegrees,
    Color color,
  ) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotationDegrees * 3.1415926535 / 180);
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset.zero,
        width: rectSize.width,
        height: rectSize.height,
      ),
      paint,
    );
    canvas.restore();
  }

  void _drawCornerBracket(
    Canvas canvas,
    Offset origin,
    double armLength,
    Color color,
  ) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawLine(origin, Offset(origin.dx + armLength, origin.dy), paint);
    canvas.drawLine(origin, Offset(origin.dx, origin.dy + armLength), paint);
  }

  @override
  bool shouldRepaint(covariant _BackgroundPainter oldDelegate) {
    return oldDelegate.brightness != brightness || oldDelegate.size != size;
  }
}
