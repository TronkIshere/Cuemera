// features/camera_session/presentation/widgets/debug_perf_overlay.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../capture/providers/capture_providers.dart';
import '../../../reference_photo/providers/reference_providers.dart';
import '../../../scene_analysis/providers/scene_providers.dart';

class DebugPerfOverlay extends ConsumerStatefulWidget {
  const DebugPerfOverlay({super.key});

  @override
  ConsumerState<DebugPerfOverlay> createState() => _DebugPerfOverlayState();
}

class _DebugPerfOverlayState extends ConsumerState<DebugPerfOverlay> {
  int _frameCount = 0;
  double _fps = 0;
  DateTime _windowStart = DateTime.now();

  void registerFrame() {
    _frameCount++;
    final now = DateTime.now();
    final elapsed = now.difference(_windowStart).inMilliseconds;
    if (elapsed >= 1000) {
      setState(() {
        _fps = _frameCount * 1000 / elapsed;
        _frameCount = 0;
        _windowStart = now;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final subject = ref.watch(subjectProfileProvider);
    final scene = ref.watch(sceneProfileProvider);
    final trackingProgress = ref.watch(trackingProgressProvider);
    final autoCaptureService = ref.watch(autoCaptureServiceProvider);
    final referenceAsync = ref.watch(referenceProfileProvider);
    final tolerance = ref.watch(toleranceSettingsProvider);
    final breakdown = referenceAsync.maybeWhen(
      data: (reference) => reference == null
          ? <String, bool>{}
          : autoCaptureService.debugConditionBreakdown(
              subject,
              scene,
              reference,
              tolerance,
              trackingProgress,
            ),
      orElse: () => <String, bool>{},
    );

    return Positioned(
      top: 200,
      left: 8,
      child: Container(
        padding: const EdgeInsets.all(8),
        color: Colors.black.withOpacity(0.65),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'FPS: ${_fps.toStringAsFixed(1)}',
              style: const TextStyle(color: Colors.greenAccent, fontSize: 12),
            ),
            Text(
              'trackingProgress: ${trackingProgress.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            ...breakdown.entries.map(
              (e) => Text(
                '${e.key}: ${e.value ? "OK" : "FAIL"}',
                style: TextStyle(
                  color: e.value ? Colors.greenAccent : Colors.redAccent,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
