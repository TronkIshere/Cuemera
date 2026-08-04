// features/editorial_score/providers/score_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../reference_photo/providers/reference_providers.dart';
import '../../scene_analysis/providers/scene_providers.dart';
import '../domain/score_calculator.dart';

final currentScoreProvider = Provider<EditorialScore?>((ref) {
  final subject = ref.watch(subjectProfileProvider);
  final scene = ref.watch(sceneProfileProvider);
  final referenceAsync = ref.watch(referenceProfileProvider);
  final tolerance = ref.watch(toleranceSettingsProvider);

  final reference = referenceAsync.valueOrNull;
  if (reference == null) return null;

  return calculateReferenceScore(subject, scene, reference, tolerance);
});
