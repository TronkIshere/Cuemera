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

  /// The structured decision this action came from — decoupled from
  /// `phrase` so a future phrase-generation step (Track 2, Phase 2) can
  /// vary the spoken text without needing a new action shape, and so
  /// dedupe (see `voice_providers.dart`) can key off what the decision
  /// *is* rather than the exact wording.
  final CoachingDecision decision;
}
