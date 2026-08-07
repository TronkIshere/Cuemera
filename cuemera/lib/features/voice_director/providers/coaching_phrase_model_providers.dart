// features/voice_director/providers/coaching_phrase_model_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/coaching_phrase_model_service.dart';

const String _huggingFaceToken = String.fromEnvironment('HF_TOKEN');

final coachingPhraseModelServiceProvider = Provider<CoachingPhraseModelService>(
  (ref) {
    assert(
      _huggingFaceToken.isNotEmpty,
      'HF_TOKEN was not provided via --dart-define.',
    );
    return CoachingPhraseModelService(huggingFaceToken: _huggingFaceToken);
  },
);
