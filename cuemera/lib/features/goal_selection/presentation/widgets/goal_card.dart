// features/goal_selection/presentation/widgets/goal_card.dart
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';

class EditorialMenuCard extends StatefulWidget {
  const EditorialMenuCard({
    super.key,
    required this.height,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.onTap,
    this.isPrimary = false,
  });

  final double height;
  final IconData icon;
  final String title;
  final String subtitle;
  final AppColors colors;
  final VoidCallback onTap;
  final bool isPrimary;

  @override
  State<EditorialMenuCard> createState() => _EditorialMenuCardState();
}

class _EditorialMenuCardState extends State<EditorialMenuCard> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;

    final baseHaloOpacity = widget.isPrimary ? 0.08 : 0.05;
    final haloOpacity = _pressed ? baseHaloOpacity + 0.07 : baseHaloOpacity;

    final baseBorderTopOpacity = widget.isPrimary ? 0.1 : 0.08;
    final baseBorderBottomOpacity = widget.isPrimary ? 0.08 : 0.06;
    final borderBoost = _pressed ? 0.12 : 0.0;

    final surfaceLighter = Color.lerp(colors.surface, Colors.white, 0.03)!;
    final badgeLighterBase = widget.isPrimary ? 0.07 : 0.04;
    final badgeLighter = Color.lerp(
      colors.surface,
      Colors.white,
      _pressed ? badgeLighterBase + 0.05 : badgeLighterBase,
    )!;

    const badgeSize = 40.0;
    const iconSize = 22.0;
    const titleSize = 25.0;
    const subtitleSize = 14.0;
    const innerPadding = 20.0;

    return RepaintBoundary(
      child: GestureDetector(
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) {
          _setPressed(false);
          widget.onTap();
        },
        onTapCancel: () => _setPressed(false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          transform: Matrix4.identity()
            ..translate(0.0, _pressed ? 2.0 : 0.0)
            ..scale(_pressed ? 0.985 : 1.0),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Color.lerp(
                  const Color(0x66000000),
                  colors.accent.withOpacity(0.35),
                  haloOpacity * 4,
                )!,
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
              child: Container(
                height: widget.height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withOpacity(
                        baseBorderTopOpacity + borderBoost,
                      ),
                      colors.accent.withOpacity(
                        baseBorderBottomOpacity + borderBoost,
                      ),
                    ],
                  ),
                ),
                padding: const EdgeInsets.all(1),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(27),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [surfaceLighter, colors.surface],
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(27),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.white.withOpacity(0.02),
                                Colors.black.withOpacity(0.03),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        left: 0,
                        child: Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                Colors.white.withOpacity(0.04),
                                Colors.white.withOpacity(0),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.all(innerPadding),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              flex: 6,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.topLeft,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: badgeSize,
                                      height: badgeSize,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            badgeLighter,
                                            colors.surface,
                                          ],
                                        ),
                                        border: Border.all(
                                          color: colors.accent.withOpacity(0.1),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: colors.accent.withOpacity(
                                              0.06,
                                            ),
                                            blurRadius: 12,
                                            spreadRadius: 1,
                                          ),
                                        ],
                                      ),
                                      child: Icon(
                                        widget.icon,
                                        size: iconSize,
                                        color: colors.accent,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      widget.title,
                                      style: TextStyle(
                                        fontSize: titleSize,
                                        fontWeight: FontWeight.w600,
                                        color: colors.text,
                                        height: 1.0,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      widget.subtitle,
                                      style: TextStyle(
                                        fontSize: subtitleSize,
                                        color: colors.textMuted,
                                        height: 1.0,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      width: 48,
                                      height: 1,
                                      color: colors.accent.withOpacity(0.35),
                                    ),
                                    const SizedBox(height: 9),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          AppStrings.homeTapToBegin,
                                          style: TextStyle(
                                            fontSize: 11,
                                            height: 1.0,
                                            color: colors.accent.withOpacity(
                                              0.35,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 180,
                                          ),
                                          curve: Curves.easeOutCubic,
                                          transform: Matrix4.translationValues(
                                            _pressed ? 2.0 : 0.0,
                                            0.0,
                                            0.0,
                                          ),
                                          child: Icon(
                                            Icons.arrow_forward,
                                            size: 14,
                                            color: colors.accent.withOpacity(
                                              0.4,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 4,
                              child: ClipRect(
                                child: Stack(
                                  clipBehavior: Clip.hardEdge,
                                  children: [
                                    Positioned.fill(
                                      child: CustomPaint(
                                        painter: _AtmospherePainter(
                                          color: colors.accent,
                                        ),
                                      ),
                                    ),
                                    Center(
                                      child: Icon(
                                        widget.icon,
                                        size: widget.isPrimary ? 80 : 64,
                                        color: colors.accent.withOpacity(0.3),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AtmospherePainter extends CustomPainter {
  _AtmospherePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final glowCenter = Offset(size.width * 0.55, size.height * 0.4);
    final glowPaint = Paint()
      ..shader =
          RadialGradient(
            colors: [color.withOpacity(0.05), color.withOpacity(0)],
          ).createShader(
            Rect.fromCircle(center: glowCenter, radius: size.width * 0.7),
          );
    canvas.drawCircle(glowCenter, size.width * 0.7, glowPaint);

    final framePaint = Paint()
      ..color = color.withOpacity(0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final frameRect = Rect.fromLTWH(
      size.width * 0.18,
      size.height * 0.15,
      size.width * 0.6,
      size.height * 0.6,
    );
    canvas.drawRect(frameRect, framePaint);

    final squarePaint = Paint()
      ..color = color.withOpacity(0.03)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final squareSize = size.width * 0.22;
    final squareRect = Rect.fromLTWH(
      size.width * 0.05,
      size.height * 0.62,
      squareSize,
      squareSize,
    );
    canvas.drawRect(squareRect, squarePaint);
  }

  @override
  bool shouldRepaint(covariant _AtmospherePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
