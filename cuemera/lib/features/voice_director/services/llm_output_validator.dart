// features/voice_director/services/llm_output_validator.dart

import 'package:cuemera/features/voice_director/domain/action_plan.dart'
    show DirectionWordChecker;
import 'package:cuemera/features/voice_director/services/llm_contract.dart';

enum LlmValidationFailure {
  none,
  emptyOrWhitespace,
  tooManyWords,
  containsDigitsOrTechnicalTerms,
  containsForbiddenTopic,
  missingRequiredTopic,
  opposingDirectionWord,
  bothDirectionWordsPresent,
  mentionsBeingAnAi,
}

class LlmValidationResult {
  const LlmValidationResult({
    required this.passed,
    required this.failure,
    this.offendingSnippet,
  });

  final bool passed;
  final LlmValidationFailure failure;

  final String? offendingSnippet;

  String debugLine() =>
      'AI: validation=${passed ? 'PASS' : 'FAIL'} '
      'reason=${failure.name}${offendingSnippet != null ? ' snippet="$offendingSnippet"' : ''}';
}

class LlmOutputValidator {
  const LlmOutputValidator({this.maxWords = 16});
  final int maxWords;

  LlmValidationResult validate(String generated, LlmCoachingContract contract) {
    final text = generated.trim();
    if (text.isEmpty) {
      return const LlmValidationResult(
        passed: false,
        failure: LlmValidationFailure.emptyOrWhitespace,
      );
    }

    final words = text.split(RegExp(r'\s+'));
    if (words.length > maxWords) {
      return LlmValidationResult(
        passed: false,
        failure: LlmValidationFailure.tooManyWords,
        offendingSnippet: '${words.length} words',
      );
    }

    if (RegExp(r'\d').hasMatch(text)) {
      return const LlmValidationResult(
        passed: false,
        failure: LlmValidationFailure.containsDigitsOrTechnicalTerms,
      );
    }

    final lower = text.toLowerCase();

    for (final forbidden in contract.forbiddenTopics) {
      if (_containsWord(lower, forbidden)) {
        return LlmValidationResult(
          passed: false,
          failure: LlmValidationFailure.containsForbiddenTopic,
          offendingSnippet: forbidden,
        );
      }
    }

    if (contract.allowedTopics.isNotEmpty &&
        !contract.allowedTopics.any((topic) => _containsWord(lower, topic))) {
      return const LlmValidationResult(
        passed: false,
        failure: LlmValidationFailure.missingRequiredTopic,
      );
    }

    if (!DirectionWordChecker.isConsistent(text, contract.direction)) {
      final failure = lower.contains('left') && lower.contains('right')
          ? LlmValidationFailure.bothDirectionWordsPresent
          : LlmValidationFailure.opposingDirectionWord;
      return LlmValidationResult(
        passed: false,
        failure: failure,
        offendingSnippet: text,
      );
    }

    if (lower.contains(' ai ') ||
        lower.startsWith('as an ai') ||
        lower.contains('language model')) {
      return const LlmValidationResult(
        passed: false,
        failure: LlmValidationFailure.mentionsBeingAnAi,
      );
    }

    return const LlmValidationResult(
      passed: true,
      failure: LlmValidationFailure.none,
    );
  }

  bool _containsWord(String lowerText, String phrase) =>
      lowerText.contains(phrase.toLowerCase());
}
