// features/voice_director/providers/coaching_phrase_model_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/coaching_phrase_model_service.dart';

const String _huggingFaceToken = String.fromEnvironment('HF_TOKEN');

final coachingPhraseModelServiceProvider =
    Provider<CoachingPhraseModelService?>((ref) {
      if (_huggingFaceToken.isEmpty) return null;
      return CoachingPhraseModelService(huggingFaceToken: _huggingFaceToken);
    });
