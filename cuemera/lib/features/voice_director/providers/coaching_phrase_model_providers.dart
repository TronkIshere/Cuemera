// features/voice_director/providers/coaching_phrase_model_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/coaching_phrase_model_service.dart';

const String _huggingFaceToken = String.fromEnvironment('HF_TOKEN');

final coachingPhraseModelServiceProvider =
    Provider<CoachingPhraseModelService?>((ref) {
      if (_huggingFaceToken.isEmpty) return null;
      return CoachingPhraseModelService(huggingFaceToken: _huggingFaceToken);
    });

/// True once generation has failed repeatedly in a row (see
/// `voice_providers.dart`'s `_maxConsecutiveFailuresBeforeUnavailable`) —
/// coaching falls back to the phrase bank until this is reset. Lives here
/// rather than in `voice_providers.dart` so `ai_coaching_providers.dart`
/// (in `features/settings/`) can reset it on a manual retry without a
/// circular import between the two provider files.
final coachingAiUnavailableProvider = StateProvider<bool>((ref) => false);

int? lastPhraseGenerationLatencyMs;
bool? lastPhraseGenerationSucceeded;
