// integration_test/coaching_phrase_model_smoke_test.dart
//
//   flutter test integration_test/coaching_phrase_model_smoke_test.dart \
//     --dart-define=HF_TOKEN=<token> -d <device-id>
import 'package:cuemera/features/voice_director/models/coaching_decision.dart';
import 'package:cuemera/features/voice_director/services/coaching_phrase_model_service.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final sampleDecisions = <String, CoachingDecision>{
    'shoulder angle, decrease, mild': const CoachingDecision(
      attribute: CoachingAttribute.shoulderAngle,
      direction: CoachingDirection.decrease,
      tier: CoachingTier.poseAndFace,
      normalizedSeverity: 0.3,
      fallbackPhrase: 'Square your shoulders just a touch',
    ),
    'face roll, right, strong': const CoachingDecision(
      attribute: CoachingAttribute.faceRoll,
      direction: CoachingDirection.right,
      tier: CoachingTier.poseAndFace,
      normalizedSeverity: 0.9,
      fallbackPhrase:
          "Straighten your head — it's tilted well to the right compared to the reference",
    ),
    'expression, target smiling': const CoachingDecision(
      attribute: CoachingAttribute.expression,
      direction: CoachingDirection.none,
      tier: CoachingTier.poseAndFace,
      normalizedSeverity: 1.0,
      fallbackPhrase: "Try a more 'smiling' expression, like the reference",
      targetExpression: 'smiling',
    ),
    'background clutter, increase, moderate': const CoachingDecision(
      attribute: CoachingAttribute.backgroundClutter,
      direction: CoachingDirection.increase,
      tier: CoachingTier.composition,
      normalizedSeverity: 0.6,
      fallbackPhrase: 'Add some background interest, like your reference',
    ),
    'hue, none, strong': const CoachingDecision(
      attribute: CoachingAttribute.hue,
      direction: CoachingDirection.none,
      tier: CoachingTier.lighting,
      normalizedSeverity: 1.0,
      fallbackPhrase:
          "Your color tone is quite different from the reference — try to match it",
    ),
  };

  testWidgets('installs and generates for a spread of decisions', (
    tester,
  ) async {
    const token = String.fromEnvironment('HF_TOKEN');
    expect(
      token.isNotEmpty,
      isTrue,
      reason: 'Pass --dart-define=HF_TOKEN=<token> when running this test.',
    );

    final service = CoachingPhraseModelService(huggingFaceToken: token);

    final installStopwatch = Stopwatch()..start();
    try {
      await service.ensureInstalled(
        onProgress: (percent) => print('Download progress: $percent%'),
      );
    } on DownloadException catch (e) {
      fail('Model install failed: ${e.error.toUserMessage()}');
    }
    installStopwatch.stop();
    print('Install complete in ${installStopwatch.elapsedMilliseconds}ms');
    expect(service.isReady, isTrue);

    for (final entry in sampleDecisions.entries) {
      final stopwatch = Stopwatch()..start();
      final phrase = await service.generate(entry.value);
      stopwatch.stop();

      print(
        '[${entry.key}] '
        '(${stopwatch.elapsedMilliseconds}ms) -> ${phrase ?? "null"}',
      );

      expect(phrase, isNotNull);
      expect(phrase, isNotEmpty);
    }
  });
}
