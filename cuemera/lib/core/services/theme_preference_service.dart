// core/services/theme_preference_service.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemePreferenceService extends StateNotifier<ThemeMode> {
  static const String _key = 'dark_mode_enabled';

  ThemePreferenceService() : super(ThemeMode.dark);

  bool get isDarkMode => state == ThemeMode.dark;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_key) ?? true;
    state = enabled ? ThemeMode.dark : ThemeMode.light;
  }

  Future<void> setDarkMode(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, enabled);
    state = enabled ? ThemeMode.dark : ThemeMode.light;
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemePreferenceService, ThemeMode>(
      (ref) => ThemePreferenceService(),
    );
