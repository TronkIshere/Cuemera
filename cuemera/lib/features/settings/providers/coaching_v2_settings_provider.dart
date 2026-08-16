// features/settings/providers/coaching_v2_settings_provider.dart
//
// Feature flag for the coaching_state_machine.dart-based listener (audit
// §23 step 10/11) — deliberately separate from the flat
// voiceDirectorListenerProvider (voice_providers.dart), which keeps running
// unchanged while this flag is off. Per the audit's own sequencing: "flip
// the flag once step 10 has had real device soak time" — this flag is the
// thing to flip, and nothing here removes the old path.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/memory_service.dart';

const _coachingV2EnabledKey = 'coaching_state_machine_enabled';

class CoachingV2Settings {
  const CoachingV2Settings({required this.enabled});

  static const initial = CoachingV2Settings(enabled: false);

  final bool enabled;

  CoachingV2Settings copyWith({bool? enabled}) =>
      CoachingV2Settings(enabled: enabled ?? this.enabled);
}

class CoachingV2SettingsNotifier extends StateNotifier<CoachingV2Settings> {
  CoachingV2SettingsNotifier(this._ref) : super(CoachingV2Settings.initial) {
    _loadPersisted();
  }

  final Ref _ref;

  Future<void> _loadPersisted() async {
    final memoryService = await _ref.read(memoryServiceProvider.future);
    final persisted = memoryService.getHabit<bool>(
      _coachingV2EnabledKey,
      defaultValue: false,
    );
    state = state.copyWith(enabled: persisted ?? false);
  }

  Future<void> setEnabled(bool value) async {
    final memoryService = await _ref.read(memoryServiceProvider.future);
    await memoryService.setHabit(_coachingV2EnabledKey, value);
    state = state.copyWith(enabled: value);
  }
}

final coachingV2SettingsProvider =
    StateNotifierProvider<CoachingV2SettingsNotifier, CoachingV2Settings>(
      (ref) => CoachingV2SettingsNotifier(ref),
    );
