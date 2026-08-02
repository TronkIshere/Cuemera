// core/constants/app_colors.dart
import 'package:flutter/material.dart';

@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.text,
    required this.textMuted,
    required this.accent,
    required this.targetZone,
    required this.success,
    required this.warning,
  });

  final Color background;
  final Color surface;
  final Color text;
  final Color textMuted;
  final Color accent;
  final Color targetZone;
  final Color success;
  final Color warning;

  static const dark = AppColors(
    background: Color(0xFF14141A),
    surface: Color(0xFF232329),
    text: Color(0xFFF3F1EA),
    textMuted: Color(0xFF9B978C),
    accent: Color(0xFFC9A227),
    targetZone: Color(0xFF5ED1C9),
    success: Color(0xFF7FA65C),
    warning: Color(0xFFE0A458),
  );

  static const light = AppColors(
    background: Color(0xFFF5F3EE),
    surface: Color(0xFFFFFFFF),
    text: Color(0xFF1B1A17),
    textMuted: Color(0xFF6B675C),
    accent: Color(0xFFB5822A),
    targetZone: Color(0xFF1F8F86),
    success: Color(0xFF4F7A34),
    warning: Color(0xFFB5762A),
  );

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? text,
    Color? textMuted,
    Color? accent,
    Color? targetZone,
    Color? success,
    Color? warning,
  }) {
    return AppColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      text: text ?? this.text,
      textMuted: textMuted ?? this.textMuted,
      accent: accent ?? this.accent,
      targetZone: targetZone ?? this.targetZone,
      success: success ?? this.success,
      warning: warning ?? this.warning,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      text: Color.lerp(text, other.text, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      targetZone: Color.lerp(targetZone, other.targetZone, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
    );
  }
}
