// features/voice_director/providers/coaching_phrase_model_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/error_reporting_service.dart';
import '../services/coaching_phrase_model_service.dart';
import '../services/model_lifecycle.dart';

const String _huggingFaceToken = String.fromEnvironment('HF_TOKEN');

final coachingPhraseModelServiceProvider =
    Provider<CoachingPhraseModelService?>((ref) {
      if (_huggingFaceToken.isEmpty) return null;
      return CoachingPhraseModelService(huggingFaceToken: _huggingFaceToken);
    });

final modelLifecycleManagerProvider = Provider<ModelLifecycleManager>((ref) {
  return ModelLifecycleManager(
    onError: (error, stackTrace, context) => ErrorReportingService.instance
        .report(error, stackTrace, context: context),
  );
});

final coachingAiUnavailableProvider = StateProvider<bool>((ref) => false);

int? lastPhraseGenerationLatencyMs;
bool? lastPhraseGenerationSucceeded;
