import 'package:flutter/material.dart';
import 'package:open_vibrance/theme/app_color_theme.dart';
import 'package:open_vibrance/services/storage_service.dart';
import 'package:open_vibrance/widgets/constants.dart';

enum AppThemeMode {
  dark('Dark', Brightness.dark),
  light('Light', Brightness.light),
  aubergine('Aubergine', Brightness.dark),
  dracula('Dracula', Brightness.dark),
  nord('Nord', Brightness.dark),
  solarized('Solarized', Brightness.dark),
  chocoMint('Choco Mint', Brightness.dark);

  final String displayName;
  final Brightness brightness;
  const AppThemeMode(this.displayName, this.brightness);
}

abstract class AppThemes {
  // ── Zinc (default dark) ──
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

  // ── Zinc (light) ──
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

  // ── Aubergine (Slack classic purple) ──
  static const aubergine = AppColorTheme(
    surface: Color(0xFF2C0A2E),
    surfaceElevated: Color(0xFF3F0E40),
    border: Color(0xFF5B2C5D),
    borderHover: Color(0xFF8B5A8E),
    borderFocus: Color(0xFF1164A3),
    textPrimary: Color(0xFFE8D5E9),
    textSecondary: Color(0xFFCDB0CF),
    textHint: Color(0xFF8B5A8E),
    textOnPrimary: Color(0xFFFFFFFF),
    iconDefault: Color(0xFF8B5A8E),
    iconHover: Color(0xFFE8D5E9),
    error: Color(0xFFCD2553),
    errorBg: Color(0xFFCD2553),
    errorBorder: Color(0xFF7A1535),
    errorText: Color(0xFFFF6B8A),
    accent: Color(0xFF1164A3),
    shadow: Color(0x801A0520),
  );

  // ── Dracula ──
  static const dracula = AppColorTheme(
    surface: Color(0xFF282A36),
    surfaceElevated: Color(0xFF44475A),
    border: Color(0xFF6272A4),
    borderHover: Color(0xFFBD93F9),
    borderFocus: Color(0xFF8BE9FD),
    textPrimary: Color(0xFFF8F8F2),
    textSecondary: Color(0xFFBFBFBF),
    textHint: Color(0xFF6272A4),
    textOnPrimary: Color(0xFFF8F8F2),
    iconDefault: Color(0xFF6272A4),
    iconHover: Color(0xFFF8F8F2),
    error: Color(0xFFFF5555),
    errorBg: Color(0xFFFF5555),
    errorBorder: Color(0xFF8B2252),
    errorText: Color(0xFFFF7B7B),
    accent: Color(0xFFBD93F9),
    shadow: Color(0x800F1015),
  );

  // ── Nord (arctic) ──
  static const nord = AppColorTheme(
    surface: Color(0xFF2E3440),
    surfaceElevated: Color(0xFF3B4252),
    border: Color(0xFF4C566A),
    borderHover: Color(0xFFD8DEE9),
    borderFocus: Color(0xFF88C0D0),
    textPrimary: Color(0xFFECEFF4),
    textSecondary: Color(0xFFD8DEE9),
    textHint: Color(0xFF616E88),
    textOnPrimary: Color(0xFFECEFF4),
    iconDefault: Color(0xFF616E88),
    iconHover: Color(0xFFECEFF4),
    error: Color(0xFFBF616A),
    errorBg: Color(0xFFBF616A),
    errorBorder: Color(0xFF8B3F47),
    errorText: Color(0xFFD88C92),
    accent: Color(0xFF88C0D0),
    shadow: Color(0x801A1E26),
  );

  // ── Solarized Dark ──
  static const solarized = AppColorTheme(
    surface: Color(0xFF002B36),
    surfaceElevated: Color(0xFF073642),
    border: Color(0xFF586E75),
    borderHover: Color(0xFF839496),
    borderFocus: Color(0xFF268BD2),
    textPrimary: Color(0xFF93A1A1),
    textSecondary: Color(0xFF839496),
    textHint: Color(0xFF586E75),
    textOnPrimary: Color(0xFFFDF6E3),
    iconDefault: Color(0xFF586E75),
    iconHover: Color(0xFF93A1A1),
    error: Color(0xFFDC322F),
    errorBg: Color(0xFFDC322F),
    errorBorder: Color(0xFF8B2020),
    errorText: Color(0xFFEF6560),
    accent: Color(0xFF268BD2),
    shadow: Color(0x80001B22),
  );

  // ── Choco Mint ──
  static const chocoMint = AppColorTheme(
    surface: Color(0xFF2B1D11),
    surfaceElevated: Color(0xFF3D2B1C),
    border: Color(0xFF5C4A39),
    borderHover: Color(0xFF7A6A5A),
    borderFocus: Color(0xFF4ECDC4),
    textPrimary: Color(0xFFE8DED3),
    textSecondary: Color(0xFFBAA89A),
    textHint: Color(0xFF7A6A5A),
    textOnPrimary: Color(0xFFE8DED3),
    iconDefault: Color(0xFF7A6A5A),
    iconHover: Color(0xFFE8DED3),
    error: Color(0xFFE74C3C),
    errorBg: Color(0xFFE74C3C),
    errorBorder: Color(0xFF8B2E23),
    errorText: Color(0xFFFF7B6B),
    accent: Color(0xFF4ECDC4),
    shadow: Color(0x801A0F07),
  );

  static AppColorTheme colorTheme(AppThemeMode mode) {
    return switch (mode) {
      AppThemeMode.dark => dark,
      AppThemeMode.light => light,
      AppThemeMode.aubergine => aubergine,
      AppThemeMode.dracula => dracula,
      AppThemeMode.nord => nord,
      AppThemeMode.solarized => solarized,
      AppThemeMode.chocoMint => chocoMint,
    };
  }

  static ThemeData buildThemeData(AppColorTheme colors, AppThemeMode mode) {
    final base = mode.brightness == Brightness.dark
        ? ThemeData.dark()
        : ThemeData.light();

    return base.copyWith(
      scaffoldBackgroundColor: Colors.transparent,
      extensions: [colors],
      colorScheme: ColorScheme(
        brightness: mode.brightness,
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
    final colors = AppThemes.colorTheme(_themeMode);
    return AppThemes.buildThemeData(colors, _themeMode);
  }
}
