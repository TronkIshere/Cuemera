// features/reference_photo/providers/detection_thresholds_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/detection_thresholds.dart';

final detectionThresholdsProvider = StateProvider<DetectionThresholds>(
  (ref) => DetectionThresholds.defaultValues,
);
