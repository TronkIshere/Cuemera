// core/services/app_tts_service.dart
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sherpa_tts_service.dart';
import 'tts_service.dart';

class AppTtsService {
  AppTtsService({required this.sherpa, required this.fallback});

  final SherpaTtsService sherpa;
  final TtsService fallback;

  Future<void> _queue = Future.value();
  bool _speaking = false;

  bool get isSpeaking => _speaking;

  Future<void> speak(
    String phrase, {
    TtsEmphasis emphasis = TtsEmphasis.mild,
    bool force = false,
  }) {
    final previous = _queue;
    final next = previous.then((_) async {
      _speaking = true;
      try {
        await _speakNow(phrase, emphasis: emphasis, force: force);
      } finally {
        _speaking = false;
      }
    });
    _queue = next;
    return next;
  }

  Future<void> _speakNow(
    String phrase, {
    required TtsEmphasis emphasis,
    required bool force,
  }) async {
    debugPrint(
      'AppTtsService: speaking "$phrase" (sherpa.isReady=${sherpa.isReady})',
    );
    if (sherpa.isReady) {
      try {
        await sherpa.speak(phrase, emphasis: emphasis, force: force);
        return;
      } catch (e, st) {
        debugPrint(
          'AppTtsService: sherpa.speak() failed, falling back to flutter_tts: $e',
        );
        debugPrint('$st');
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
