// features/voice_director/services/model_lifecycle.dart

import '../models/coaching_decision.dart';
import 'coaching_phrase_model_service.dart';

enum ModelLifecycleState {
  uninitialized,
  initializing,
  installing,
  loading,
  ready,
  generating,
  error,
  recovering,
}

typedef LifecycleErrorReporter =
    void Function(Object error, StackTrace stackTrace, String context);

class ModelLifecycleManager {
  ModelLifecycleManager({
    this.onError,
    this.retryBackoff = const [
      Duration(seconds: 5),
      Duration(seconds: 15),
      Duration(seconds: 60),
    ],
  });

  final LifecycleErrorReporter? onError;

  final List<Duration> retryBackoff;

  ModelLifecycleState _state = ModelLifecycleState.uninitialized;
  Object? _lastError;
  DateTime? _lastErrorAt;
  int _consecutiveFailures = 0;

  ModelLifecycleState get state => _state;
  bool get canAttemptGeneration => _state == ModelLifecycleState.ready;
  Object? get lastError => _lastError;

  bool get isInBackoff {
    if (_state != ModelLifecycleState.error || _lastErrorAt == null)
      return false;
    final index = (_consecutiveFailures - 1).clamp(0, retryBackoff.length - 1);
    return DateTime.now().difference(_lastErrorAt!) < retryBackoff[index];
  }

  void resetBackoff() {
    _lastErrorAt = null;
  }

  Future<void> ensureReady(
    CoachingPhraseModelService service, {
    void Function(int percent)? onProgress,
  }) async {
    if (_state == ModelLifecycleState.ready) return;
    if (_state == ModelLifecycleState.installing ||
        _state == ModelLifecycleState.loading)
      return;
    if (isInBackoff) return;

    if (_state == ModelLifecycleState.error) {
      _state = ModelLifecycleState.recovering;
    }

    _state = ModelLifecycleState.initializing;
    try {
      _state = ModelLifecycleState.installing;
      await service.ensureInstalled(onProgress: onProgress);

      _state = ModelLifecycleState.loading;
      if (!service.isReady) {
        throw StateError(
          'ensureInstalled() completed without throwing but service.isReady is false — '
          'this is the exact W5/M2 symptom the audit flagged as the top-priority item to verify.',
        );
      }

      _state = ModelLifecycleState.ready;
      _consecutiveFailures = 0;
      _lastError = null;
    } catch (e, st) {
      _state = ModelLifecycleState.error;
      _lastError = e;
      _lastErrorAt = DateTime.now();
      _consecutiveFailures++;
      onError?.call(
        e,
        st,
        'model lifecycle: ensureReady failed (attempt $_consecutiveFailures)',
      );
    }
  }

  Future<String?> generate(
    CoachingPhraseModelService service,
    CoachingDecision decision,
  ) async {
    if (!canAttemptGeneration) return null;

    _state = ModelLifecycleState.generating;
    try {
      final result = await service.generate(decision);
      _state = ModelLifecycleState.ready;
      if (result != null) {
        _consecutiveFailures = 0;
      } else {
        _consecutiveFailures++;
      }
      return result;
    } catch (e, st) {
      _state = ModelLifecycleState.error;
      _lastError = e;
      _lastErrorAt = DateTime.now();
      _consecutiveFailures++;
      onError?.call(
        e,
        st,
        'model lifecycle: generate failed (attempt $_consecutiveFailures)',
      );
      return null;
    }
  }

  String debugLine() =>
      'AI: modelState=${_state.name.toUpperCase()} '
      'consecutiveFailures=$_consecutiveFailures '
      'lastError=${_lastError?.runtimeType.toString() ?? 'none'}';
}
