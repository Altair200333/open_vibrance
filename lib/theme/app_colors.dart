import 'package:flutter/material.dart';

/// Centralized color system for the app.
///
/// Raw scales contain the actual color values.
/// Semantic tokens provide intent-based aliases for UI usage.
abstract class AppColors {
  // ── Raw scales (only values actually used in the app) ──

  static const zinc900 = Color(0xFF18181B);
  static const zinc800 = Color(0xFF27272A);
  static const zinc700 = Color(0xFF3F3F46);
  static const zinc600 = Color(0xFF52525B);
  static const zinc500 = Color(0xFF71717A);
  static const zinc400 = Color(0xFFA1A1AA);
  static const zinc300 = Color(0xFFD4D4D8);

  static const red300 = Color(0xFFFC8181);
  static const red400 = Color(0xFFF56565);
  static const red500 = Color(0xFFE53E3E);
  static const red900 = Color(0xFF63171B);

  static const blue400 = Color(0xFF4299E1);

  static const black = Color(0xFF000000);
  static const white = Color(0xFFFFFFFF);

  // ── Semantic tokens ──

  static const surface = zinc900;
  static const surfaceElevated = zinc800;
  static const border = zinc700;
  static const borderHover = zinc500;
  static const borderFocus = zinc400;

  static const textPrimary = zinc300;
  static const textSecondary = zinc400;
  static const textHint = zinc500;
  static const textOnPrimary = white;

  static const iconDefault = zinc500;
  static const iconHover = zinc300;

  static const error = red400;
  static const errorBg = red500;
  static const errorBorder = red900;
  static const errorText = red300;

  static const accent = blue400;

  static const shadow = Color(0x8A000000);
}
