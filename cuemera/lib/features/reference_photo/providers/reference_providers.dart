// features/reference_photo/providers/reference_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/reference_profile.dart';
import '../domain/models/tolerance_settings.dart';
import '../services/reference_image_analyzer.dart';

final selectedReferenceImagePathProvider = StateProvider<String?>((ref) {
  return null;
});

final referenceImageAnalyzerProvider = Provider<ReferenceImageAnalyzer>((ref) {
  return ReferenceImageAnalyzer();
});

final referenceProfileProvider = FutureProvider<ReferenceProfile?>((ref) async {
  final path = ref.watch(selectedReferenceImagePathProvider);
  if (path == null) return null;

  final analyzer = ref.watch(referenceImageAnalyzerProvider);
  return analyzer.analyze(path);
});

final toleranceSettingsProvider = StateProvider<ToleranceSettings>((ref) {
  return ToleranceSettings.defaultBalanced;
});
