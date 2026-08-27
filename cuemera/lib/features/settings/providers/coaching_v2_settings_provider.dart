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

// Must match ai_coaching_providers.dart's private _aiCoachingEnabledKey
// exactly — duplicated here (rather than imported) because that key is
// library-private. Needed for the startup dependency check below.
const _aiCoachingEnabledKeyMirror = 'ai_coaching_enabled';

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
    final persisted =
        memoryService.getHabit<bool>(
          _coachingV2EnabledKey,
          defaultValue: false,
        ) ??
        false;

    // Coaching v2 now requires AI Coaching to be on (settings_screen.dart
    // greys out its switch otherwise). If v2 was persisted true from
    // before that requirement existed, or from AI Coaching later being
    // turned off elsewhere, correct it here too — otherwise it would
    // silently load as enabled (and camera_screen.dart would run it,
    // without AI) while its own switch shows disabled.
    final aiCoachingPersisted =
        memoryService.getHabit<bool>(
          _aiCoachingEnabledKeyMirror,
          defaultValue: false,
        ) ??
        false;

    if (persisted && !aiCoachingPersisted) {
      await memoryService.setHabit(_coachingV2EnabledKey, false);
      state = state.copyWith(enabled: false);
      return;
    }

    state = state.copyWith(enabled: persisted);
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
