// features/settings/providers/ai_coaching_providers.dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/memory_service.dart';
import '../../voice_director/providers/coaching_phrase_model_providers.dart';
import '../../voice_director/services/model_lifecycle.dart';

const _aiCoachingEnabledKey = 'ai_coaching_enabled';

class AiCoachingSettings {
  const AiCoachingSettings({
    required this.enabled,
    required this.isInstalling,
    required this.installProgress,
    required this.installError,
    required this.aiUnavailable,
  });

  static const initial = AiCoachingSettings(
    enabled: false,
    isInstalling: false,
    installProgress: null,
    installError: null,
    aiUnavailable: false,
  );

  final bool enabled;
  final bool isInstalling;
  final int? installProgress;
  final String? installError;

  final bool aiUnavailable;

  AiCoachingSettings copyWith({
    bool? enabled,
    bool? isInstalling,
    int? installProgress,
    String? installError,
    bool clearError = false,
    bool? aiUnavailable,
  }) {
    return AiCoachingSettings(
      enabled: enabled ?? this.enabled,
      isInstalling: isInstalling ?? this.isInstalling,
      installProgress: installProgress ?? this.installProgress,
      installError: clearError ? null : (installError ?? this.installError),
      aiUnavailable: aiUnavailable ?? this.aiUnavailable,
    );
  }
}

class AiCoachingSettingsNotifier extends StateNotifier<AiCoachingSettings> {
  AiCoachingSettingsNotifier(this._ref) : super(AiCoachingSettings.initial) {
    _lifecycle = _ref.read(modelLifecycleManagerProvider);
    _recoveryTimer = Timer.periodic(_recoveryCheckInterval, (_) {
      if (!state.enabled) return;
      if (_lifecycle.state != ModelLifecycleState.error) return;
      unawaited(_install());
    });
    _loadPersisted();
  }

  static const _recoveryCheckInterval = Duration(seconds: 5);

  final Ref _ref;
  late final ModelLifecycleManager _lifecycle;
  Timer? _recoveryTimer;

  Future<void> _loadPersisted() async {
    final memoryService = await _ref.read(memoryServiceProvider.future);
    final persisted = memoryService.getHabit<bool>(
      _aiCoachingEnabledKey,
      defaultValue: false,
    );
    if (persisted == true) {
      state = state.copyWith(enabled: true);
      unawaited(_install());
    }
  }

  Future<void> setEnabled(bool value) async {
    final memoryService = await _ref.read(memoryServiceProvider.future);
    await memoryService.setHabit(_aiCoachingEnabledKey, value);
    state = state.copyWith(enabled: value, clearError: true);
    if (value) {
      _lifecycle.resetBackoff();
      await _install();
    }
  }

  Future<void> _install() async {
    final service = _ref.read(coachingPhraseModelServiceProvider);
    if (service == null) {
      state = state.copyWith(
        installError: 'AI coaching is not available on this build.',
        aiUnavailable: false,
      );
      return;
    }
    if (_lifecycle.state == ModelLifecycleState.ready) return;
    if (_lifecycle.isInBackoff) return;

    state = state.copyWith(
      isInstalling: true,
      installProgress: 0,
      clearError: true,
    );

    await _lifecycle.ensureReady(
      service,
      onProgress: (percent) {
        state = state.copyWith(installProgress: percent);
      },
    );

    final ready = _lifecycle.state == ModelLifecycleState.ready;
    state = state.copyWith(
      isInstalling: false,
      installProgress: ready ? 100 : state.installProgress,
      installError: ready ? null : 'Download failed. Retrying automatically.',
      clearError: ready,
      aiUnavailable: !ready,
    );
    _ref.read(coachingAiUnavailableProvider.notifier).state = !ready;
  }

  @override
  void dispose() {
    _recoveryTimer?.cancel();
    super.dispose();
  }
}

final aiCoachingSettingsProvider =
    StateNotifierProvider<AiCoachingSettingsNotifier, AiCoachingSettings>(
      (ref) => AiCoachingSettingsNotifier(ref),
    );
