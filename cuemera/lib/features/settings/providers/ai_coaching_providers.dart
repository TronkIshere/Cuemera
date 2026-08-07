// features/settings/providers/ai_coaching_providers.dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/memory_service.dart';
import '../../voice_director/providers/coaching_phrase_model_providers.dart';

const _aiCoachingEnabledKey = 'ai_coaching_enabled';

class AiCoachingSettings {
  const AiCoachingSettings({
    required this.enabled,
    required this.isInstalling,
    required this.installProgress,
    required this.installError,
  });

  static const initial = AiCoachingSettings(
    enabled: false,
    isInstalling: false,
    installProgress: null,
    installError: null,
  );

  final bool enabled;
  final bool isInstalling;
  final int? installProgress;
  final String? installError;

  AiCoachingSettings copyWith({
    bool? enabled,
    bool? isInstalling,
    int? installProgress,
    String? installError,
    bool clearError = false,
  }) {
    return AiCoachingSettings(
      enabled: enabled ?? this.enabled,
      isInstalling: isInstalling ?? this.isInstalling,
      installProgress: installProgress ?? this.installProgress,
      installError: clearError ? null : (installError ?? this.installError),
    );
  }
}

class AiCoachingSettingsNotifier extends StateNotifier<AiCoachingSettings> {
  AiCoachingSettingsNotifier(this._ref) : super(AiCoachingSettings.initial) {
    _loadPersisted();
  }

  final Ref _ref;

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
    if (value) await _install();
  }

  Future<void> _install() async {
    final service = _ref.read(coachingPhraseModelServiceProvider);
    if (service == null) {
      state = state.copyWith(
        installError: 'AI coaching is not available on this build.',
      );
      return;
    }
    if (service.isReady) return;

    state = state.copyWith(
      isInstalling: true,
      installProgress: 0,
      clearError: true,
    );
    try {
      await service.ensureInstalled(
        onProgress: (percent) {
          state = state.copyWith(installProgress: percent);
        },
      );
      state = state.copyWith(isInstalling: false, installProgress: 100);
    } catch (_) {
      state = state.copyWith(
        isInstalling: false,
        installError: 'Download failed. Using standard coaching for now.',
      );
    }
  }
}

final aiCoachingSettingsProvider =
    StateNotifierProvider<AiCoachingSettingsNotifier, AiCoachingSettings>(
      (ref) => AiCoachingSettingsNotifier(ref),
    );
