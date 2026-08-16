// features/voice_director/services/model_lifecycle.dart

import 'dart:async';

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
    this.installStallTimeout = const Duration(minutes: 2),
    this.installHardCeiling = const Duration(minutes: 30),
  });

  final LifecycleErrorReporter? onError;

  /// Capped backoff — does not grow unbounded and does not require an app
  /// restart to clear, unlike the current coachingAiUnavailableProvider.
  final List<Duration> retryBackoff;

  /// service.ensureInstalled() has no timeout of its own. Aborts only if no
  /// progress event arrives for this long — a slow-but-alive download (e.g.
  /// HuggingFace's Xet CDN reporting in sparse, uneven jumps like 0% then
  /// nothing until 92%) keeps resetting this on every event it does send,
  /// so it's never killed for being slow, only for going fully silent.
  final Duration installStallTimeout;

  /// Backstop in case progress events never stop arriving but the install
  /// itself never finishes either. Doesn't cancel the underlying native
  /// call (Future.timeout can't), so a very slow install may still finish
  /// in the background after this fires.
  final Duration installHardCeiling;

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
    Timer? stallTimer;
    try {
      _state = ModelLifecycleState.installing;

      final completer = Completer<void>();
      void armStallTimer() {
        stallTimer?.cancel();
        stallTimer = Timer(installStallTimeout, () {
          if (!completer.isCompleted) {
            completer.completeError(
              TimeoutException('no install progress for $installStallTimeout'),
            );
          }
        });
      }

      armStallTimer();
      unawaited(
        service
            .ensureInstalled(
              onProgress: (percent) {
                armStallTimer();
                onProgress?.call(percent);
              },
            )
            .then((_) {
              if (!completer.isCompleted) completer.complete();
            })
            .catchError((Object e, StackTrace st) {
              if (!completer.isCompleted) completer.completeError(e, st);
            }),
      );

      await completer.future.timeout(installHardCeiling);
      stallTimer?.cancel();

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
      stallTimer?.cancel();
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
        // generate() returning null without throwing (busy, timeout inside
        // the service, etc.) still counts toward backoff — a silent null
        // is not evidence-free, it's evidence of *something* going wrong,
        // even though we don't have a specific exception for it.
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
