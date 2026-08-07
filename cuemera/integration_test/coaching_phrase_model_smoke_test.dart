// integration_test/coaching_phrase_model_smoke_test.dart
//
//   flutter test integration_test/coaching_phrase_model_smoke_test.dart \
//     --dart-define=HF_TOKEN=<token> -d <device-id>
//
// Extends the original install/isReady smoke test with behavioral
// validation of generated phrases (attribute/direction/severity/
// naturalness/editorial-compliance) and per-case + aggregate latency.
// Validation is heuristic/keyword-based (word-boundary matching), not a
// semantic judge — it catches obviously wrong or malformed output, not
// subtle phrasing quality. Model install time is excluded from the
// latency stats; only generate() calls are measured.
import 'package:cuemera/features/voice_director/models/coaching_decision.dart';
import 'package:cuemera/features/voice_director/services/coaching_phrase_model_service.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Mirrors `voice_providers.dart`'s `_generationTimeout` — keep in sync.
const _realtimeLatencyThresholdMs = 3000;

enum _Family { pose, face, composition, lighting }

const _familyOf = <CoachingAttribute, _Family>{
  CoachingAttribute.shoulderAngle: _Family.pose,
  CoachingAttribute.bodyRatio: _Family.pose,
  CoachingAttribute.facePitch: _Family.face,
  CoachingAttribute.faceRoll: _Family.face,
  CoachingAttribute.mouthOpen: _Family.face,
  CoachingAttribute.eyeOpen: _Family.face,
  CoachingAttribute.expression: _Family.face,
  CoachingAttribute.negativeSpace: _Family.composition,
  CoachingAttribute.symmetry: _Family.composition,
  CoachingAttribute.backgroundClutter: _Family.composition,
  CoachingAttribute.brightness: _Family.lighting,
  CoachingAttribute.warmth: _Family.lighting,
  CoachingAttribute.hue: _Family.lighting,
};

const _familyKeywords = <_Family, List<String>>{
  _Family.pose: ['shoulder', 'shoulders', 'stance', 'posture', 'pose'],
  _Family.face: [
    'head',
    'tilt',
    'chin',
    'nod',
    'mouth',
    'lips',
    'eye',
    'eyes',
    'smile',
    'smiling',
    'expression',
  ],
  _Family.composition: [
    'background',
    'frame',
    'space',
    'center',
    'centre',
    'symmetry',
    'align',
    'balance',
    'clutter',
  ],
  _Family.lighting: [
    'light',
    'lighting',
    'bright',
    'dark',
    'shadow',
    'warm',
    'cool',
    'tone',
    'color',
    'colour',
    'hue',
  ],
};

const _attributeRequiredKeywords = <CoachingAttribute, List<String>>{
  CoachingAttribute.shoulderAngle: ['shoulder'],
  CoachingAttribute.facePitch: ['chin', 'head', 'tilt', 'nod'],
  CoachingAttribute.faceRoll: ['head', 'tilt', 'straighten', 'level'],
  CoachingAttribute.bodyRatio: [
    'pose',
    'stance',
    'posture',
    'position',
    'step',
  ],
  CoachingAttribute.mouthOpen: ['mouth', 'lips'],
  CoachingAttribute.eyeOpen: ['eye'],
  CoachingAttribute.expression: ['smil', 'expression', 'face'],
  CoachingAttribute.negativeSpace: [
    'space',
    'frame',
    'center',
    'centre',
    'position',
  ],
  CoachingAttribute.symmetry: [
    'center',
    'centre',
    'symmetr',
    'align',
    'balance',
  ],
  CoachingAttribute.backgroundClutter: ['background'],
  CoachingAttribute.brightness: ['light', 'bright', 'dark', 'shadow'],
  CoachingAttribute.warmth: ['warm', 'cool', 'tone'],
  CoachingAttribute.hue: ['color', 'colour', 'tone', 'hue'],
};

const _increaseWords = [
  'more',
  'increase',
  'raise',
  'higher',
  'add',
  'wider',
  'bigger',
  'up',
];
const _decreaseWords = [
  'less',
  'decrease',
  'lower',
  'reduce',
  'relax',
  'soften',
  'down',
  'smaller',
];
const _mildForbidden = [
  'drastically',
  'immediately',
  'urgently',
  'severely',
  'completely',
  'totally',
  'significantly',
];
const _strongForbidden = ['maybe', 'perhaps', 'slightly', 'barely'];
const _refusalMarkers = [
  'i cannot',
  "i can't",
  'i am unable',
  "i'm unable",
  'as an ai',
  'sorry',
  'i apologize',
];
const _actionVerbs = [
  'try',
  'move',
  'turn',
  'tilt',
  'relax',
  'lift',
  'lower',
  'look',
  'smile',
  'step',
  'adjust',
  'shift',
  'soften',
  'straighten',
  'open',
  'keep',
  'square',
  'raise',
];

bool _containsWord(String haystackLower, String needleLower) {
  if (needleLower.contains(' ')) return haystackLower.contains(needleLower);
  return RegExp(
    r'\b' + RegExp.escape(needleLower) + r'\b',
  ).hasMatch(haystackLower);
}

class PhraseCheckResult {
  PhraseCheckResult({required this.label, required this.passed, this.reason});
  final String label;
  final bool passed;
  final String? reason;
}

PhraseCheckResult _checkAttribute(
  String phraseLower,
  CoachingAttribute attribute,
) {
  final required = _attributeRequiredKeywords[attribute]!;
  if (!required.any(phraseLower.contains)) {
    return PhraseCheckResult(
      label: 'attribute',
      passed: false,
      reason:
          'missing expected ${attribute.name} wording (looked for: ${required.join(", ")})',
    );
  }
  final ownFamily = _familyOf[attribute];
  for (final entry in _familyKeywords.entries) {
    if (entry.key == ownFamily) continue;
    for (final word in entry.value) {
      if (_containsWord(phraseLower, word)) {
        return PhraseCheckResult(
          label: 'attribute',
          passed: false,
          reason:
              'mentions unrelated ${entry.key.name} term "$word" for a ${attribute.name} decision',
        );
      }
    }
  }
  return PhraseCheckResult(label: 'attribute', passed: true);
}

PhraseCheckResult _checkDirection(
  String phraseLower,
  CoachingDirection direction,
) {
  switch (direction) {
    case CoachingDirection.none:
      return PhraseCheckResult(
        label: 'direction',
        passed: true,
        reason: 'no direction required',
      );
    case CoachingDirection.left:
    case CoachingDirection.right:
      final own = direction.name;
      final opposite = direction == CoachingDirection.left ? 'right' : 'left';
      if (_containsWord(phraseLower, opposite)) {
        return PhraseCheckResult(
          label: 'direction',
          passed: false,
          reason: 'contradicts $own with "$opposite"',
        );
      }
      if (!_containsWord(phraseLower, own)) {
        return PhraseCheckResult(
          label: 'direction',
          passed: false,
          reason: 'does not mention "$own"',
        );
      }
      return PhraseCheckResult(label: 'direction', passed: true);
    case CoachingDirection.increase:
    case CoachingDirection.decrease:
      final contradicting = direction == CoachingDirection.increase
          ? _decreaseWords
          : _increaseWords;
      for (final word in contradicting) {
        if (_containsWord(phraseLower, word)) {
          return PhraseCheckResult(
            label: 'direction',
            passed: false,
            reason: 'contradicts ${direction.name} with "$word"',
          );
        }
      }
      return PhraseCheckResult(label: 'direction', passed: true);
  }
}

PhraseCheckResult _checkSeverity(
  String phraseLower,
  CoachingSeverityBand band,
) {
  final forbidden = switch (band) {
    CoachingSeverityBand.mild => _mildForbidden,
    CoachingSeverityBand.moderate => const <String>[],
    CoachingSeverityBand.strong => _strongForbidden,
  };
  for (final word in forbidden) {
    if (_containsWord(phraseLower, word)) {
      return PhraseCheckResult(
        label: 'severity',
        passed: false,
        reason: '"$word" is disproportionate for a ${band.name} issue',
      );
    }
  }
  return PhraseCheckResult(label: 'severity', passed: true);
}

PhraseCheckResult _checkNaturalness(String phrase) {
  final trimmed = phrase.trim();
  if (trimmed.isEmpty) {
    return PhraseCheckResult(
      label: 'naturalness',
      passed: false,
      reason: 'empty phrase',
    );
  }
  if (trimmed.contains('\n')) {
    return PhraseCheckResult(
      label: 'naturalness',
      passed: false,
      reason: 'multi-line output',
    );
  }
  if (trimmed.contains('"') || trimmed.contains("'")) {
    return PhraseCheckResult(
      label: 'naturalness',
      passed: false,
      reason: 'contains quotation marks',
    );
  }
  if (RegExp(r'[0-9]').hasMatch(trimmed)) {
    return PhraseCheckResult(
      label: 'naturalness',
      passed: false,
      reason: 'contains a digit',
    );
  }
  final wordCount = trimmed.split(RegExp(r'\s+')).length;
  if (wordCount < 2) {
    return PhraseCheckResult(
      label: 'naturalness',
      passed: false,
      reason: 'too short ($wordCount word)',
    );
  }
  if (wordCount > 20) {
    return PhraseCheckResult(
      label: 'naturalness',
      passed: false,
      reason: 'too verbose ($wordCount words)',
    );
  }
  if (RegExp(
    r'\b(\w+)\b(\s+\1\b){2,}',
    caseSensitive: false,
  ).hasMatch(trimmed)) {
    return PhraseCheckResult(
      label: 'naturalness',
      passed: false,
      reason: 'repeats a word 3+ times in a row',
    );
  }
  return PhraseCheckResult(label: 'naturalness', passed: true);
}

PhraseCheckResult _checkEditorial(String phraseLower) {
  for (final marker in _refusalMarkers) {
    if (phraseLower.contains(marker)) {
      return PhraseCheckResult(
        label: 'editorial',
        passed: false,
        reason: 'refusal/meta phrase: "$marker"',
      );
    }
  }
  if (!_actionVerbs.any((v) => _containsWord(phraseLower, v))) {
    return PhraseCheckResult(
      label: 'editorial',
      passed: false,
      reason: 'no actionable coaching verb found',
    );
  }
  return PhraseCheckResult(label: 'editorial', passed: true);
}

PhraseCheckResult _checkLatency(int latencyMs) {
  if (latencyMs > _realtimeLatencyThresholdMs) {
    return PhraseCheckResult(
      label: 'latency',
      passed: false,
      reason:
          '${latencyMs}ms exceeds ${_realtimeLatencyThresholdMs}ms realtime threshold',
    );
  }
  return PhraseCheckResult(label: 'latency', passed: true);
}

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

  testWidgets('installs and validates coaching phrase generation', (
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

    final latenciesMs = <int>[];
    var passedCount = 0;
    var failedCount = 0;
    final failureSummaries = <String>[];

    for (final entry in sampleDecisions.entries) {
      final label = entry.key;
      final decision = entry.value;

      final stopwatch = Stopwatch()..start();
      final phrase = await service.generate(decision);
      stopwatch.stop();
      final latencyMs = stopwatch.elapsedMilliseconds;
      latenciesMs.add(latencyMs);

      print('--- [$label] ---');
      print(
        'decision: attribute=${decision.attribute.name}, '
        'direction=${decision.direction.name}, '
        'severity=${decision.severityBand.name}, '
        'targetExpression=${decision.targetExpression}',
      );
      print('phrase: ${phrase ?? "null"}');
      print('latency: ${latencyMs}ms');

      if (phrase == null || phrase.trim().isEmpty) {
        failedCount++;
        failureSummaries.add('[$label] generate() returned null/empty');
        print('validation: FAIL (no phrase generated)');
        continue;
      }

      final phraseLower = phrase.toLowerCase();
      final checks = <PhraseCheckResult>[
        _checkAttribute(phraseLower, decision.attribute),
        _checkDirection(phraseLower, decision.direction),
        _checkSeverity(phraseLower, decision.severityBand),
        _checkNaturalness(phrase),
        _checkEditorial(phraseLower),
        _checkLatency(latencyMs),
      ];

      for (final check in checks) {
        final status = check.passed ? 'PASS' : 'FAIL';
        final reasonText = check.reason != null ? ' — ${check.reason}' : '';
        print('validation [${check.label}]: $status$reasonText');
      }

      if (checks.every((c) => c.passed)) {
        passedCount++;
      } else {
        failedCount++;
        final failed = checks.where((c) => !c.passed);
        failureSummaries.add(
          '[$label] ${failed.map((c) => '${c.label}: ${c.reason}').join('; ')}',
        );
      }
    }

    final minLatency = latenciesMs.reduce((a, b) => a < b ? a : b);
    final maxLatency = latenciesMs.reduce((a, b) => a > b ? a : b);
    final avgLatency = latenciesMs.reduce((a, b) => a + b) / latenciesMs.length;

    print('=== Summary ===');
    print('passed: $passedCount, failed: $failedCount');
    print(
      'latency (ms) — min: $minLatency, max: $maxLatency, '
      'avg: ${avgLatency.toStringAsFixed(1)}',
    );
    if (failureSummaries.isNotEmpty) {
      print('failures:');
      for (final f in failureSummaries) {
        print('  - $f');
      }
    }

    expect(
      failedCount,
      0,
      reason:
          'One or more coaching-phrase validations failed:\n${failureSummaries.join('\n')}',
    );
  });
}
