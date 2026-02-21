import 'package:flutter/material.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:open_vibrance/theme/app_color_theme.dart';
import 'package:open_vibrance/widgets/constants.dart';

/// Shared component styles that can't be expressed via ThemeData.
abstract class AppStyles {
  static ButtonStyleData dropdownButton(AppColorTheme colors) => ButtonStyleData(
    height: 40,
    padding: EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: colors.surfaceElevated,
      borderRadius: BorderRadius.circular(kRadiusMd),
      border: Border.all(color: colors.border),
    ),
  );

  static DropdownStyleData dropdownMenu(AppColorTheme colors) => DropdownStyleData(
    decoration: BoxDecoration(
      color: colors.surfaceElevated,
      borderRadius: BorderRadius.circular(kRadiusMd),
      border: Border.all(color: colors.border),
    ),
    elevation: 0,
  );

  static IconStyleData dropdownIcon(AppColorTheme colors) => IconStyleData(
    icon: Icon(Icons.keyboard_arrow_down_rounded),
    iconSize: 20,
    iconEnabledColor: colors.textSecondary,
  );

  static MenuItemStyleData dropdownMenuItem(AppColorTheme colors) => MenuItemStyleData(
    height: 40,
    padding: EdgeInsets.symmetric(horizontal: 12),
    overlayColor: WidgetStatePropertyAll(colors.border),
  );
}
