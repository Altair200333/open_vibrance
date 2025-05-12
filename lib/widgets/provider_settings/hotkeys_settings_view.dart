import 'package:flutter/material.dart';
import 'package:open_vibrance/theme/app_colors.dart';

class HotkeysSettingsView extends StatelessWidget {
  const HotkeysSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.gray700,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hotkeys Configuration',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 16),
          // TODO: Add hotkey configuration UI here
          Text(
            'Coming soon...',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
