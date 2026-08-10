// core/services/sherpa_tts_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show debugPrint;
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
      debugPrint(
        'SherpaTtsService: init OK, isReady=true (modelDir=$modelDir)',
      );
    } catch (e, st) {
      debugPrint('SherpaTtsService.init() FAILED: $e');
      debugPrint('$st');
      _ready = false;
    }
  }

  /// Extracts the bundled VITS assets to a writable directory.
  ///
  /// Verifies the three files/dirs sherpa_onnx actually needs are present
  /// on disk before trusting a leftover ".extracted" marker from a prior
  /// (possibly incomplete) run — a stale marker used to cause every
  /// subsequent launch to silently skip re-extraction even after fixing
  /// pubspec.yaml's asset list, since the check used to be marker-only.
  Future<String> _ensureModelExtracted() async {
    final supportDir = await getApplicationSupportDirectory();
    final targetDir = Directory('${supportDir.path}/vits-en');
    final marker = File('${targetDir.path}/.extracted');

    if (await marker.exists() && await _looksComplete(targetDir)) {
      debugPrint(
        'SherpaTtsService: using previously extracted model at ${targetDir.path}',
      );
      return targetDir.path;
    }

    debugPrint(
      'SherpaTtsService: (re)extracting model assets to ${targetDir.path}',
    );

    final manifestJson = await rootBundle.loadString('AssetManifest.json');
    final manifest = json.decode(manifestJson) as Map<String, dynamic>;
    final assetPaths = manifest.keys
        .where((k) => k.startsWith(assetPrefix))
        .toList();

    debugPrint(
      'SherpaTtsService: found ${assetPaths.length} bundled asset(s) under '
      '"$assetPrefix" in AssetManifest.json',
    );
    if (assetPaths.isEmpty) {
      throw StateError(
        'No assets found under "$assetPrefix" — check that pubspec.yaml '
        'actually declares this path under flutter: > assets:',
      );
    }

    for (final assetPath in assetPaths) {
      final data = await rootBundle.load(assetPath);
      final relative = assetPath.substring(assetPrefix.length + 1);
      final outFile = File('${targetDir.path}/$relative');
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(data.buffer.asUint8List());
    }

    if (!await _looksComplete(targetDir)) {
      throw StateError(
        'Extraction finished but required files are still missing under '
        '${targetDir.path} — most likely "espeak-ng-data/" (or a nested '
        'subdirectory of it) is missing from pubspec.yaml\'s assets: list. '
        'Flutter does not bundle nested directories recursively; each '
        'subdirectory needs its own explicit line.',
      );
    }

    await marker.create(recursive: true);
    await marker.writeAsString('done');
    return targetDir.path;
  }

  /// True only if the files sherpa_onnx actually needs are present.
  /// Extend this list if your model uses a lexicon/dict dir too.
  Future<bool> _looksComplete(Directory targetDir) async {
    final requiredPaths = [
      '${targetDir.path}/model.onnx',
      '${targetDir.path}/tokens.txt',
      '${targetDir.path}/espeak-ng-data',
    ];
    for (final p in requiredPaths) {
      final isDir = p.endsWith('espeak-ng-data');
      final exists = isDir
          ? await Directory(p).exists()
          : await File(p).exists();
      if (!exists) {
        debugPrint('SherpaTtsService: missing required path: $p');
        return false;
      }
      if (isDir) {
        final hasFiles = await Directory(p).list().isEmpty.then((e) => !e);
        if (!hasFiles) {
          debugPrint('SherpaTtsService: $p exists but is empty');
          return false;
        }
      }
    }
    return true;
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

  /// [force] bypasses the same-phrase dedupe — see TtsService.speak() for
  /// why this matters for one-off confirmations vs. per-frame coaching.
  Future<void> speak(
    String phrase, {
    TtsEmphasis emphasis = TtsEmphasis.mild,
    bool force = false,
  }) async {
    if (!_ready || _tts == null || phrase.isEmpty) return;
    if (!force && phrase == _lastPhrase) return;
    _lastPhrase = phrase;

    try {
      final genConfig = sherpa_onnx.OfflineTtsGenerationConfig(
        sid: 0,
        speed: _speedFor(emphasis),
        silenceScale: _silenceScaleFor(emphasis),
      );
      final audio = _tts!.generateWithConfig(
        text: _withEmphasisMarkup(phrase, emphasis),
        config: genConfig,
      );
      if (audio.samples.isEmpty) {
        debugPrint(
          'SherpaTtsService.speak(): generated 0 samples for "$phrase"',
        );
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final wavPath = '${tempDir.path}/coaching_phrase.wav';
      sherpa_onnx.writeWave(
        filename: wavPath,
        samples: audio.samples,
        sampleRate: audio.sampleRate,
      );

      final wavFile = File(wavPath);
      final size = await wavFile.exists() ? await wavFile.length() : 0;
      debugPrint('SherpaTtsService.speak(): wrote $size bytes to $wavPath');

      await _player.stop();
      final completer = Completer<void>();
      void finish() {
        if (!completer.isCompleted) completer.complete();
      }

      late final StreamSubscription<void> completeSub;
      late final StreamSubscription<PlayerState> stateSub;
      completeSub = _player.onPlayerComplete.listen((_) => finish());
      stateSub = _player.onPlayerStateChanged.listen((state) {
        if (state == PlayerState.stopped || state == PlayerState.disposed) {
          finish();
        }
      });
      await _player.play(DeviceFileSource(wavPath));
      await completer.future;
      await completeSub.cancel();
      await stateSub.cancel();
    } catch (e, st) {
      debugPrint('SherpaTtsService.speak() FAILED: $e');
      debugPrint('$st');
      rethrow; // let AppTtsService catch this and fall back to flutter_tts
    }
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
