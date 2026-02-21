import 'package:flutter/material.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:provider/provider.dart';
import 'package:open_vibrance/theme/app_color_theme.dart';
import 'package:open_vibrance/theme/app_themes.dart';
import 'package:open_vibrance/theme/app_styles.dart';
import 'package:open_vibrance/widgets/constants.dart';

class ThemeSettingsView extends StatelessWidget {
  const ThemeSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final themeNotifier = context.watch<ThemeNotifier>();
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'App Theme',
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: kFontSizeMd,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Select a visual theme for the interface',
          style: TextStyle(color: colors.textHint, fontSize: kFontSizeSm),
        ),
        SizedBox(height: 8),
        DropdownButtonHideUnderline(
          child: DropdownButton2<AppThemeMode>(
            value: themeNotifier.themeMode,
            onChanged: (mode) {
              if (mode != null) themeNotifier.setTheme(mode);
            },
            items: AppThemeMode.values
                .map(
                  (mode) => DropdownMenuItem<AppThemeMode>(
                    value: mode,
                    child: Text(
                      mode.displayName,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: kFontSizeLg,
                      ),
                    ),
                  ),
                )
                .toList(),
            buttonStyleData: AppStyles.dropdownButton(colors),
            dropdownStyleData: AppStyles.dropdownMenu(colors),
            iconStyleData: AppStyles.dropdownIcon(colors),
            menuItemStyleData: AppStyles.dropdownMenuItem(colors),
          ),
        ),
      ],
    );
  }
}
