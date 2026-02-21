import 'package:flutter/material.dart';

class AppColorTheme extends ThemeExtension<AppColorTheme> {
  final Color surface;
  final Color surfaceElevated;
  final Color border;
  final Color borderHover;
  final Color borderFocus;
  final Color textPrimary;
  final Color textSecondary;
  final Color textHint;
  final Color textOnPrimary;
  final Color iconDefault;
  final Color iconHover;
  final Color error;
  final Color errorBg;
  final Color errorBorder;
  final Color errorText;
  final Color accent;
  final Color shadow;

  const AppColorTheme({
    required this.surface,
    required this.surfaceElevated,
    required this.border,
    required this.borderHover,
    required this.borderFocus,
    required this.textPrimary,
    required this.textSecondary,
    required this.textHint,
    required this.textOnPrimary,
    required this.iconDefault,
    required this.iconHover,
    required this.error,
    required this.errorBg,
    required this.errorBorder,
    required this.errorText,
    required this.accent,
    required this.shadow,
  });

  @override
  AppColorTheme copyWith({
    Color? surface,
    Color? surfaceElevated,
    Color? border,
    Color? borderHover,
    Color? borderFocus,
    Color? textPrimary,
    Color? textSecondary,
    Color? textHint,
    Color? textOnPrimary,
    Color? iconDefault,
    Color? iconHover,
    Color? error,
    Color? errorBg,
    Color? errorBorder,
    Color? errorText,
    Color? accent,
    Color? shadow,
  }) {
    return AppColorTheme(
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      border: border ?? this.border,
      borderHover: borderHover ?? this.borderHover,
      borderFocus: borderFocus ?? this.borderFocus,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textHint: textHint ?? this.textHint,
      textOnPrimary: textOnPrimary ?? this.textOnPrimary,
      iconDefault: iconDefault ?? this.iconDefault,
      iconHover: iconHover ?? this.iconHover,
      error: error ?? this.error,
      errorBg: errorBg ?? this.errorBg,
      errorBorder: errorBorder ?? this.errorBorder,
      errorText: errorText ?? this.errorText,
      accent: accent ?? this.accent,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  AppColorTheme lerp(AppColorTheme? other, double t) {
    if (other is! AppColorTheme) return this;
    return AppColorTheme(
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderHover: Color.lerp(borderHover, other.borderHover, t)!,
      borderFocus: Color.lerp(borderFocus, other.borderFocus, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textHint: Color.lerp(textHint, other.textHint, t)!,
      textOnPrimary: Color.lerp(textOnPrimary, other.textOnPrimary, t)!,
      iconDefault: Color.lerp(iconDefault, other.iconDefault, t)!,
      iconHover: Color.lerp(iconHover, other.iconHover, t)!,
      error: Color.lerp(error, other.error, t)!,
      errorBg: Color.lerp(errorBg, other.errorBg, t)!,
      errorBorder: Color.lerp(errorBorder, other.errorBorder, t)!,
      errorText: Color.lerp(errorText, other.errorText, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}

extension AppColorThemeX on BuildContext {
  AppColorTheme get colors => Theme.of(this).extension<AppColorTheme>()!;
}
