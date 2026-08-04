// features/voice_director/domain/priority_engine.dart
class PriorityAction {
  const PriorityAction({
    required this.phrase,
    required this.severity,
    required this.sourceLayer,
  });

  final String phrase;
  final int severity;
  final String sourceLayer;
}
