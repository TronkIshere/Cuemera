// features/voice_director/providers/coaching_phrase_model_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/coaching_phrase_model_service.dart';

/// Token-sourcing: build-time `--dart-define=HF_TOKEN=...` per build
/// flavor — the simplest option, chosen as a default here rather than
/// blocking on a release-config decision. Swappable for a
/// backend-fetched short-lived token or a self-hosted model mirror
/// (removes the token requirement entirely) without changing anything
/// below this constant — see PHASE1_MODEL_INTEGRATION_PLAN.md.
const String _huggingFaceToken = String.fromEnvironment('HF_TOKEN');

/// Exposed for Phase 1 testing/iteration only. Phase 2 wires a provider
/// like this into `voiceDirectorListenerProvider` with the
/// fallback-on-failure behavior the plan describes; nothing here is on
/// the live coaching path yet.
final coachingPhraseModelServiceProvider = Provider<CoachingPhraseModelService>(
  (ref) {
    assert(
      _huggingFaceToken.isNotEmpty,
      'HF_TOKEN was not provided via --dart-define. Gemma 3 270M is a gated '
      'model on Hugging Face and will fail to download without it.',
    );
    return CoachingPhraseModelService(huggingFaceToken: _huggingFaceToken);
  },
);
