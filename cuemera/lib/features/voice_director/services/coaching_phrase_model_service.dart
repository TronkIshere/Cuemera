// features/voice_director/services/coaching_phrase_model_service.dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_mediapipe/flutter_gemma_mediapipe.dart';

import '../../../core/services/error_reporting_service.dart';
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
  bool _installing = false;
  bool _generating = false;

  bool get isReady => _model != null;

  Future<void> _ensurePluginInitialized() async {
    if (_pluginInitialized) return;
    await FlutterGemma.initialize(
      inferenceEngines: const [MediaPipeEngine()],
      huggingFaceToken: huggingFaceToken.isEmpty ? null : huggingFaceToken,
    );
    _pluginInitialized = true;
  }

  Future<void> ensureInstalled({void Function(int percent)? onProgress}) async {
    if (isReady) return;
    if (_installing) return;
    _installing = true;
    try {
      await _ensurePluginInitialized();

      await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
          .fromNetwork(modelUrl, token: huggingFaceToken)
          .withProgress((progress) => onProgress?.call(progress))
          .install();

      _model = await FlutterGemma.getActiveModel(maxTokens: 512);
    } catch (e, st) {
      ErrorReportingService.instance.report(
        e,
        st,
        context: 'coaching_phrase_model_service: model initialization failure',
      );
      rethrow;
    } finally {
      _installing = false;
    }
  }

  Future<String?> generate(CoachingDecision decision) async {
    if (!isReady) return null;
    if (_generating) return null;
    _generating = true;

    try {
      final session = await _model!.createSession();
      await session.addQueryChunk(
        Message.text(text: _buildPrompt(decision), isUser: true),
      );
      final response = await session.getResponse();
      await session.close();

      final text = response.trim();
      return text.isEmpty ? null : text;
    } catch (e, st) {
      ErrorReportingService.instance.report(
        e,
        st,
        context: 'coaching_phrase_model_service: inference failure',
      );
      return null;
    } finally {
      _generating = false;
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
        'quotation marks, no mention that you are an AI, no apologies.',
      )
      ..writeln()
      ..writeln('Attribute to correct: ${decision.attribute.name}');

    if (decision.direction != CoachingDirection.none) {
      buffer.writeln(
        'Direction needed: ${decision.direction.name} — the instruction '
        'must clearly move this way, never the opposite.',
      );
    }
    if (decision.targetExpression != null) {
      buffer.writeln('Target expression: ${decision.targetExpression}');
    }

    buffer
      ..writeln(
        'Severity: ${decision.severityBand.name} — match the wording\'s '
        'intensity to this; don\'t over- or under-state it.',
      )
      ..writeln()
      ..writeln(
        'Base this only on the example below — same topic, same '
        'direction, similar intensity, new wording. Do not copy it '
        'verbatim, and do not bring in any other aspect of the photo '
        'that the example doesn\'t already mention:',
      )
      ..writeln('"${decision.fallbackPhrase}"');

    return buffer.toString();
  }
}
