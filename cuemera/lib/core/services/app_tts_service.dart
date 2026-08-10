// core/services/app_tts_service.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sherpa_tts_service.dart';
import 'tts_service.dart';

class AppTtsService {
  AppTtsService({required this.sherpa, required this.fallback});

  final SherpaTtsService sherpa;
  final TtsService fallback;

  Future<void> speak(
    String phrase, {
    TtsEmphasis emphasis = TtsEmphasis.mild,
    bool force = false,
  }) async {
    if (sherpa.isReady) {
      try {
        await sherpa.speak(phrase, emphasis: emphasis, force: force);
        return;
      } catch (_) {
        // Falls through to flutter_tts below.
      }
    }
    await fallback.speak(phrase, force: force);
  }

  Future<void> stop() async {
    await sherpa.stop();
    await fallback.stop();
  }
}

final appTtsServiceProvider = Provider<AppTtsService>((ref) {
  final sherpa = ref.watch(sherpaTtsServiceProvider);
  final fallback = ref.watch(ttsServiceProvider);
  return AppTtsService(sherpa: sherpa, fallback: fallback);
});
