import 'package:flutter/material.dart';
import 'package:open_vibrance/theme/app_color_theme.dart';
import 'package:open_vibrance/services/storage_service.dart';
import 'package:open_vibrance/widgets/constants.dart';

enum AppThemeMode {
  dark('Dark'),
  light('Light');

  final String displayName;
  const AppThemeMode(this.displayName);
}

abstract class AppThemes {
  static const dark = AppColorTheme(
    surface: Color(0xFF18181B),
    surfaceElevated: Color(0xFF27272A),
    border: Color(0xFF3F3F46),
    borderHover: Color(0xFF71717A),
    borderFocus: Color(0xFFA1A1AA),
    textPrimary: Color(0xFFD4D4D8),
    textSecondary: Color(0xFFA1A1AA),
    textHint: Color(0xFF71717A),
    textOnPrimary: Color(0xFFFFFFFF),
    iconDefault: Color(0xFF71717A),
    iconHover: Color(0xFFD4D4D8),
    error: Color(0xFFF56565),
    errorBg: Color(0xFFE53E3E),
    errorBorder: Color(0xFF63171B),
    errorText: Color(0xFFFC8181),
    accent: Color(0xFF4299E1),
    shadow: Color(0x8A000000),
  );

  static const light = AppColorTheme(
    surface: Color(0xFFF4F4F5),
    surfaceElevated: Color(0xFFFFFFFF),
    border: Color(0xFFD4D4D8),
    borderHover: Color(0xFFA1A1AA),
    borderFocus: Color(0xFF4299E1),
    textPrimary: Color(0xFF27272A),
    textSecondary: Color(0xFF52525B),
    textHint: Color(0xFFA1A1AA),
    textOnPrimary: Color(0xFF27272A),
    iconDefault: Color(0xFF71717A),
    iconHover: Color(0xFF3F3F46),
    error: Color(0xFFE53E3E),
    errorBg: Color(0xFFE53E3E),
    errorBorder: Color(0xFFFC8181),
    errorText: Color(0xFFC53030),
    accent: Color(0xFF4299E1),
    shadow: Color(0x33000000),
  );

  static ThemeData buildThemeData(AppColorTheme colors, AppThemeMode mode) {
    final brightness =
        mode == AppThemeMode.dark ? Brightness.dark : Brightness.light;
    final base =
        mode == AppThemeMode.dark ? ThemeData.dark() : ThemeData.light();

    return base.copyWith(
      scaffoldBackgroundColor: Colors.transparent,
      extensions: [colors],
      colorScheme: ColorScheme(
        brightness: brightness,
        surface: colors.surface,
        onSurface: colors.textPrimary,
        primary: colors.accent,
        onPrimary: colors.textOnPrimary,
        error: colors.error,
        onError: colors.textOnPrimary,
        secondary: colors.accent,
        onSecondary: colors.textOnPrimary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceElevated,
        hintStyle: TextStyle(color: colors.textHint),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kRadiusMd),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kRadiusMd),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kRadiusMd),
          borderSide: BorderSide(color: colors.borderFocus),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      ),
      textTheme: TextTheme(
        bodyMedium: TextStyle(color: colors.textPrimary),
      ),
    );
  }
}

class ThemeNotifier extends ChangeNotifier {
  AppThemeMode _themeMode = AppThemeMode.dark;

  AppThemeMode get themeMode => _themeMode;

  ThemeNotifier() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final saved = await SecureStorageService().readValue('app_theme');
    if (saved != null) {
      try {
        _themeMode = AppThemeMode.values.byName(saved);
        notifyListeners();
      } catch (_) {}
    }
  }

  void setTheme(AppThemeMode mode) {
    _themeMode = mode;
    SecureStorageService().saveValue('app_theme', mode.name);
    notifyListeners();
  }

  ThemeData get themeData {
    final colors =
        _themeMode == AppThemeMode.dark ? AppThemes.dark : AppThemes.light;
    return AppThemes.buildThemeData(colors, _themeMode);
  }
}
