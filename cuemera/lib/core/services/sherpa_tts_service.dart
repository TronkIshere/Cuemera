// core/services/sherpa_tts_service.dart
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

enum TtsEmphasis { mild, moderate, strong }

class SherpaTtsService {
  SherpaTtsService({this.assetPrefix = 'assets/models/vits-en'});

  final String assetPrefix;

  sherpa_onnx.OfflineTts? _tts;
  final AudioPlayer _player = AudioPlayer();
  bool _ready = false;
  String? _lastPhrase;

  bool get isReady => _ready;

  Future<void> init() async {
    try {
      sherpa_onnx.initBindings();

      final modelDir = await _ensureModelExtracted();

      final vits = sherpa_onnx.OfflineTtsVitsModelConfig(
        model: '$modelDir/model.onnx',
        tokens: '$modelDir/tokens.txt',
        dataDir: '$modelDir/espeak-ng-data',
        lexicon: '',
        dictDir: '',
      );
      final config = sherpa_onnx.OfflineTtsConfig(
        model: sherpa_onnx.OfflineTtsModelConfig(
          vits: vits,
          numThreads: 2,
          debug: false,
          provider: 'cpu',
        ),
        // "maxNumSenetences" (sic) — this is the actual field name shipped
        // in the sherpa_onnx package (confirmed against multiple official
        // examples), not a typo on our end.
        maxNumSenetences: 1,
      );

      _tts = sherpa_onnx.OfflineTts(config);
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  Future<String> _ensureModelExtracted() async {
    final supportDir = await getApplicationSupportDirectory();
    final targetDir = Directory('${supportDir.path}/vits-en');
    final marker = File('${targetDir.path}/.extracted');
    if (await marker.exists()) return targetDir.path;

    final manifestJson = await rootBundle.loadString('AssetManifest.json');
    final manifest = json.decode(manifestJson) as Map<String, dynamic>;
    final assetPaths = manifest.keys.where((k) => k.startsWith(assetPrefix));

    for (final assetPath in assetPaths) {
      final data = await rootBundle.load(assetPath);
      final relative = assetPath.substring(assetPrefix.length + 1);
      final outFile = File('${targetDir.path}/$relative');
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(data.buffer.asUint8List());
    }

    await marker.create(recursive: true);
    await marker.writeAsString('done');
    return targetDir.path;
  }

  double _speedFor(TtsEmphasis emphasis) {
    switch (emphasis) {
      case TtsEmphasis.mild:
        return 1.0;
      case TtsEmphasis.moderate:
        return 0.95;
      case TtsEmphasis.strong:
        return 0.88;
    }
  }

  double _silenceScaleFor(TtsEmphasis emphasis) {
    switch (emphasis) {
      case TtsEmphasis.mild:
        return 0.2;
      case TtsEmphasis.moderate:
        return 0.3;
      case TtsEmphasis.strong:
        return 0.45;
    }
  }

  String _withEmphasisMarkup(String phrase, TtsEmphasis emphasis) {
    if (emphasis != TtsEmphasis.strong) return phrase;
    final trimmed = phrase.trim();
    if (trimmed.endsWith('!')) return trimmed;
    final withoutPeriod = trimmed.endsWith('.')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
    return '$withoutPeriod!';
  }

  Future<void> speak(
    String phrase, {
    TtsEmphasis emphasis = TtsEmphasis.mild,
  }) async {
    if (!_ready || _tts == null || phrase.isEmpty || phrase == _lastPhrase) {
      return;
    }
    _lastPhrase = phrase;

    final genConfig = sherpa_onnx.OfflineTtsGenerationConfig(
      sid: 0,
      speed: _speedFor(emphasis),
      silenceScale: _silenceScaleFor(emphasis),
    );
    final audio = _tts!.generateWithConfig(
      text: _withEmphasisMarkup(phrase, emphasis),
      config: genConfig,
    );
    if (audio.samples.isEmpty) return;

    final tempDir = await getTemporaryDirectory();
    final wavPath = '${tempDir.path}/coaching_phrase.wav';
    sherpa_onnx.writeWave(
      filename: wavPath,
      samples: audio.samples,
      sampleRate: audio.sampleRate,
    );

    await _player.stop();
    await _player.play(DeviceFileSource(wavPath));
  }

  Future<void> stop() async {
    _lastPhrase = null;
    await _player.stop();
  }

  Future<void> dispose() async {
    await _player.dispose();
    _tts?.free();
  }
}

final sherpaTtsServiceProvider = Provider<SherpaTtsService>((ref) {
  final service = SherpaTtsService();
  service.init();
  ref.onDispose(() => service.dispose());
  return service;
});
