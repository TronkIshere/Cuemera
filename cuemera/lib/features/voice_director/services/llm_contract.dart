// features/voice_director/services/llm_contract.dart

import 'package:cuemera/features/voice_director/models/coaching_decision.dart';

const Map<CoachingAttribute, List<String>> kAttributeTopicKeywords = {
  CoachingAttribute.shoulderAngle: ['shoulder', 'shoulders'],
  CoachingAttribute.shoulderBalance: ['shoulder', 'shoulders', 'level'],
  CoachingAttribute.shoulderSpan: ['shoulder', 'shoulders', 'relax', 'open'],
  CoachingAttribute.facePitch: ['chin', 'head'],
  CoachingAttribute.faceRoll: ['head', 'tilt'],
  CoachingAttribute.faceYaw: ['face', 'turn', 'head'],
  CoachingAttribute.bodyYaw: ['turn', 'body'],
  CoachingAttribute.bodyRatio: ['frame', 'framing'],
  CoachingAttribute.mouthOpen: ['mouth'],
  CoachingAttribute.eyeOpen: ['eyes'],
  CoachingAttribute.expression: ['smile', 'expression'],
  CoachingAttribute.negativeSpace: ['space', 'frame'],
  CoachingAttribute.symmetry: ['center', 'centered'],
  CoachingAttribute.backgroundClutter: ['background'],
  CoachingAttribute.brightness: ['light', 'bright', 'dim'],
  CoachingAttribute.warmth: ['warm', 'cool', 'tone'],
  CoachingAttribute.hue: ['color', 'tone'],
};

/// Human-readable label used in the prompt in place of the raw enum name.
const Map<CoachingAttribute, String> kAttributeHumanName = {
  CoachingAttribute.shoulderAngle: 'shoulder tilt',
  CoachingAttribute.shoulderBalance: 'shoulder level',
  CoachingAttribute.shoulderSpan: 'shoulder width',
  CoachingAttribute.facePitch: 'chin/head tilt up-down',
  CoachingAttribute.faceRoll: 'head tilt sideways',
  CoachingAttribute.faceYaw: 'which way the face is turned',
  CoachingAttribute.bodyYaw: 'which way the body is turned',
  CoachingAttribute.bodyRatio: 'framing',
  CoachingAttribute.mouthOpen: 'how open the mouth is',
  CoachingAttribute.eyeOpen: 'how open the eyes are',
  CoachingAttribute.expression: 'facial expression',
  CoachingAttribute.negativeSpace: 'how much empty space is in frame',
  CoachingAttribute.symmetry: 'how centered the subject is',
  CoachingAttribute.backgroundClutter: 'background busyness',
  CoachingAttribute.brightness: 'brightness',
  CoachingAttribute.warmth: 'color warmth',
  CoachingAttribute.hue: 'color tone',
};

class LlmCoachingContract {
  const LlmCoachingContract({
    required this.attribute,
    required this.attributeTopic,
    required this.direction,
    required this.severity,
    required this.targetExpression,
    required this.allowedTopics,
    required this.forbiddenTopics,
    required this.fallback,
  });

  final CoachingAttribute attribute;
  final String attributeTopic;
  final CoachingDirection direction;
  final CoachingSeverityBand severity;
  final String? targetExpression;
  final List<String> allowedTopics;
  final List<String> forbiddenTopics;

  final String fallback;

  factory LlmCoachingContract.fromDecision(CoachingDecision decision) {
    final ownTopics =
        kAttributeTopicKeywords[decision.attribute] ??
        [decision.attribute.name];
    final forbidden = <String>{};
    for (final entry in kAttributeTopicKeywords.entries) {
      if (entry.key == decision.attribute) continue;
      for (final keyword in entry.value) {
        if (!ownTopics.contains(keyword)) forbidden.add(keyword);
      }
    }

    return LlmCoachingContract(
      attribute: decision.attribute,
      attributeTopic:
          kAttributeHumanName[decision.attribute] ?? decision.attribute.name,
      direction: decision.direction,
      severity: decision.severityBand,
      targetExpression: decision.targetExpression,
      allowedTopics: ownTopics,
      forbiddenTopics: forbidden.toList(),
      fallback: decision.fallbackPhrase,
    );
  }

  String buildPrompt() {
    final buffer = StringBuffer()
      ..writeln(
        'Rewrite this photography coaching line in your own words. One short '
        'sentence, under 12 words. No numbers. Do not mention being an AI.',
      )
      ..writeln('Topic: $attributeTopic.');

    if (direction == CoachingDirection.left ||
        direction == CoachingDirection.right) {
      buffer.writeln(
        'Direction: ${direction.name}. Do not say the opposite side.',
      );
    } else if (direction == CoachingDirection.increase ||
        direction == CoachingDirection.decrease) {
      buffer.writeln('Direction: ${direction.name} this quality versus now.');
    }

    if (targetExpression != null) {
      buffer.writeln('Target expression: $targetExpression.');
    }

    buffer
      ..writeln('Intensity: ${severity.name}.')
      ..writeln(
        'Stay only on this topic — do not mention anything else about the photo.',
      )
      ..writeln(
        'Example line, same meaning, do not copy verbatim: "$fallback"',
      );

    return buffer.toString();
  }
}
