// core/theme/app_theme.dart
import 'package:cuemera/core/constants/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get darkTheme => _build(AppColors.dark, Brightness.dark);
  static ThemeData get lightTheme => _build(AppColors.light, Brightness.light);

  static ThemeData _build(AppColors colors, Brightness brightness) {
    final base = ThemeData(brightness: brightness, useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: colors.background,
      extensions: [colors],
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: colors.accent,
        onPrimary: colors.background,
        secondary: colors.targetZone,
        onSecondary: colors.background,
        surface: colors.surface,
        onSurface: colors.text,
        error: colors.warning,
        onError: colors.background,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        iconTheme: IconThemeData(color: colors.text),
        titleTextStyle: AppTypography.heading2(colors),
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.textMuted.withOpacity(0.15)),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.accent,
          foregroundColor: colors.background,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          textStyle: AppTypography.body(
            colors,
          ).copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      textTheme: AppTypography.buildTextTheme(colors),
      iconTheme: IconThemeData(color: colors.text),
      dividerTheme: DividerThemeData(
        color: colors.textMuted.withOpacity(0.15),
        thickness: 1,
      ),
    );
  }
}
