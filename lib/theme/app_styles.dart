import 'package:flutter/material.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:open_vibrance/theme/app_colors.dart';
import 'package:open_vibrance/widgets/constants.dart';

/// Shared component styles that can't be expressed via ThemeData.
abstract class AppStyles {
  static ButtonStyleData get dropdownButton => ButtonStyleData(
    height: 40,
    padding: EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: AppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(kRadiusMd),
      border: Border.all(color: AppColors.border),
    ),
  );

  static DropdownStyleData get dropdownMenu => DropdownStyleData(
    decoration: BoxDecoration(
      color: AppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(kRadiusMd),
      border: Border.all(color: AppColors.border),
    ),
    elevation: 0,
  );

  static IconStyleData get dropdownIcon => IconStyleData(
    icon: Icon(Icons.keyboard_arrow_down_rounded),
    iconSize: 20,
    iconEnabledColor: AppColors.textSecondary,
  );

  static MenuItemStyleData get dropdownMenuItem => MenuItemStyleData(
    height: 40,
    padding: EdgeInsets.symmetric(horizontal: 12),
    overlayColor: WidgetStatePropertyAll(AppColors.border),
  );
}
