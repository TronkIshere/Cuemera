// features/voice_director/services/coaching_phrase_model_service.dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_mediapipe/flutter_gemma_mediapipe.dart';

import '../models/coaching_decision.dart';

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

  Future<void> ensureInstalled({void Function(int percent)? onProgress}) async {
    if (isReady) return;
    _ensurePluginInitialized();

    await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
        .fromNetwork(modelUrl, token: huggingFaceToken)
        .withProgress((progress) => onProgress?.call(progress))
        .install();

    _model = await FlutterGemma.getActiveModel(maxTokens: 128);
  }

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
