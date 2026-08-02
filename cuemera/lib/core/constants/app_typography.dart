// core/constants/app_typography.dart
import 'package:cuemera/core/constants/app_colors.dart';
import 'package:flutter/material.dart';

abstract class AppTypography {
  static const TextStyle _heading1 = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );
  static const TextStyle _heading2 = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 1.25,
  );
  static const TextStyle _body = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );
  static const TextStyle _bodyMuted = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );
  static const TextStyle _caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.3,
  );
  static const TextStyle _score = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.1,
  );

  static TextStyle heading1(AppColors colors) =>
      _heading1.copyWith(color: colors.text);
  static TextStyle heading2(AppColors colors) =>
      _heading2.copyWith(color: colors.text);
  static TextStyle body(AppColors colors) => _body.copyWith(color: colors.text);
  static TextStyle bodyMuted(AppColors colors) =>
      _bodyMuted.copyWith(color: colors.textMuted);
  static TextStyle caption(AppColors colors) =>
      _caption.copyWith(color: colors.textMuted);
  static TextStyle score(AppColors colors) =>
      _score.copyWith(color: colors.accent);

  static TextTheme buildTextTheme(AppColors colors) {
    return TextTheme(
      headlineLarge: heading1(colors),
      headlineMedium: heading2(colors),
      headlineSmall: heading2(colors),
      titleLarge: heading2(colors),
      titleMedium: body(colors).copyWith(fontWeight: FontWeight.w600),
      bodyLarge: body(colors),
      bodyMedium: body(colors),
      bodySmall: bodyMuted(colors),
      labelLarge: body(colors).copyWith(fontWeight: FontWeight.w600),
      labelSmall: caption(colors),
    );
  }
}
