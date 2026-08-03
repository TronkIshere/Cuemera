// features/camera_session/presentation/widgets/focus_ring.dart
import 'package:flutter/material.dart';

class FocusRing extends StatelessWidget {
  const FocusRing({super.key, required this.center, required this.color});

  final Offset center;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: center.dx - 20,
      top: center.dy - 20,
      child: AnimatedOpacity(
        opacity: 1.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 1.5),
          ),
        ),
      ),
    );
  }
}
