// features/voice_director/domain/priority_engine.dart
import 'package:cuemera/features/voice_director/models/coaching_decision.dart';

class PriorityAction {
  const PriorityAction({
    required this.phrase,
    required this.severity,
    required this.sourceLayer,
    required this.decision,
  });

  final String phrase;
  final int severity;
  final String sourceLayer;
  final CoachingDecision decision;
}
