// features/voice_director/services/coaching_phrase_model_service.dart
import 'package:cuemera/features/voice_director/models/coaching_decision.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_mediapipe/flutter_gemma_mediapipe.dart';

/// Wraps Gemma 3 270M (via flutter_gemma) to generate natural-language
/// coaching phrases from a [CoachingDecision]. Isolated from the live
/// coaching path on purpose — Phase 1 only. Wiring this into
/// `voiceDirectorListenerProvider` (with the fallback-on-failure behavior
/// the plan describes) is Phase 2.
///
/// Model: litert-community/gemma-3-270m-it, the `gemma3-270m-it-q8.task`
/// mobile build (int8, ~304MB) — NOT one of the `-web` variants in that
/// same repo, which are for the web/WASM target only. Gated on Hugging
/// Face: a token is required to download it (see [huggingFaceToken]).
///
/// flutter_gemma 1.0+ split into a small core plus opt-in engine packages
/// — core registers no engine by itself, so this class registers
/// `MediaPipeEngine` (the `.task` engine, from `flutter_gemma_mediapipe`)
/// itself on first use via [_ensurePluginInitialized], rather than
/// requiring every call site to remember a separate `main()`-level setup
/// step. Calling `FlutterGemma.initialize(...)` more than once across the
/// app would be a bug, so this guards on a static flag.
class CoachingPhraseModelService {
  CoachingPhraseModelService({
    required this.huggingFaceToken,
    this.modelUrl = _defaultModelUrl,
  });

  static const String _defaultModelUrl =
      'https://huggingface.co/litert-community/gemma-3-270m-it/resolve/main/gemma3-270m-it-q8.task';

  static bool _pluginInitialized = false;

  final String modelUrl;
  final String huggingFaceToken;

  InferenceModel? _model;

  bool get isReady => _model != null;

  void _ensurePluginInitialized() {
    if (_pluginInitialized) return;
    FlutterGemma.initialize(
      inferenceEngines: const [MediaPipeEngine()],
      huggingFaceToken: huggingFaceToken.isEmpty ? null : huggingFaceToken,
    );
    _pluginInitialized = true;
  }

  /// Downloads (first call only — flutter_gemma caches after install) and
  /// activates the model. Safe to call more than once; a second call
  /// while already installed is a no-op.
  ///
  /// Throws [DownloadException] on failure (gated-model 401/403, bad URL,
  /// network error, etc.) — unlike [generate], this is a distinct
  /// user-initiated action (e.g. tapping "enable AI coaching"), so the
  /// caller should surface `e.error.toUserMessage()` rather than have the
  /// failure silently swallowed here.
  Future<void> ensureInstalled({void Function(int percent)? onProgress}) async {
    if (isReady) return;
    _ensurePluginInitialized();

    await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
        .fromNetwork(modelUrl, token: huggingFaceToken)
        .withProgress((progress) => onProgress?.call(progress))
        .install();

    _model = await FlutterGemma.getActiveModel(maxTokens: 128);
  }

  /// Generates a short spoken-coaching phrase for [decision]. Returns
  /// `null` — never throws — if the model isn't installed yet or
  /// generation fails for any reason, so callers have an unambiguous
  /// signal to fall back to `decision.fallbackPhrase` (Phase 2's job, not
  /// this method's).
  Future<String?> generate(CoachingDecision decision) async {
    if (!isReady) return null;

    try {
      final session = await _model!.createSession();
      await session.addQueryChunk(
        Message.text(text: _buildPrompt(decision), isUser: true),
      );
      final response = await session.getResponse();
      await session.close();

      final text = response.trim();
      return text.isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  String _buildPrompt(CoachingDecision decision) {
    final buffer = StringBuffer()
      ..writeln(
        'You are a photography coach speaking one short line out loud to '
        'someone posing for a photo, live, in the moment.',
      )
      ..writeln(
        'Reply with ONLY the spoken line — under 12 words, natural and '
        'encouraging, no numbers or technical terms, no preamble, no '
        'quotation marks.',
      )
      ..writeln()
      ..writeln('Attribute to correct: ${decision.attribute.name}');

    if (decision.direction != CoachingDirection.none) {
      buffer.writeln('Direction needed: ${decision.direction.name}');
    }
    if (decision.targetExpression != null) {
      buffer.writeln('Target expression: ${decision.targetExpression}');
    }

    buffer
      ..writeln('Severity: ${decision.severityBand.name}')
      ..writeln()
      ..writeln(
        'For tone and style only (do not copy this verbatim): '
        '"${decision.fallbackPhrase}"',
      );

    return buffer.toString();
  }
}
