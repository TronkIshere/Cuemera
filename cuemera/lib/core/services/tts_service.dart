// core/services/tts_service.dart
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  final FlutterTts _tts = FlutterTts();
  String? _lastPhrase;
  bool _ready = false;

  Future<void> init() async {
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.55);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);
      await _tts.awaitSpeakCompletion(true);
      _ready = true;
      debugPrint('TtsService: init OK, isReady=true');
    } catch (e, st) {
      debugPrint('TtsService.init() FAILED: $e');
      debugPrint('$st');
      _ready = false;
    }
  }

  Future<void> speak(String phrase, {bool force = false}) async {
    if (!_ready || phrase.isEmpty) return;
    if (!force && phrase == _lastPhrase) return;
    _lastPhrase = phrase;
    debugPrint('TtsService.speak(): "$phrase"');
    await _tts.stop();
    final result = await _tts.speak(phrase);
    debugPrint('TtsService.speak(): result=$result');
  }

  Future<void> stop() async {
    _lastPhrase = null;
    await _tts.stop();
  }

  Future<void> dispose() async {
    await _tts.stop();
  }
}

final ttsServiceProvider = Provider<TtsService>((ref) {
  final service = TtsService();
  service.init();
  ref.onDispose(() => service.dispose());
  return service;
});
