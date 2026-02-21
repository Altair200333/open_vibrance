import 'package:flutter/material.dart';
import 'package:open_vibrance/theme/app_colors.dart';
import 'package:open_vibrance/widgets/constants.dart';
import 'package:open_vibrance/widgets/provider_settings/transcription_provider_configuration_view.dart';
import 'package:open_vibrance/widgets/provider_settings/hotkeys_settings_view.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

class SettingsItem {
  final String title;
  final WidgetBuilder viewBuilder;

  SettingsItem({required this.title, required this.viewBuilder});
}

class SettingsBox extends StatefulWidget {
  final void Function(List<HotKeyModifier> modifiers, List<PhysicalKeyboardKey> keys)
      onHotkeyChanged;
  final VoidCallback onRecordingStarted;

  const SettingsBox({
    super.key,
    required this.expandedWindowSize,
    required this.onHotkeyChanged,
    required this.onRecordingStarted,
  });

  final Size expandedWindowSize;

  @override
  State<SettingsBox> createState() => _SettingsBoxState();
}

class _SettingsBoxState extends State<SettingsBox> {
  SettingsItem? _selectedSetting;

  late final List<SettingsItem> _settingsItems;

  @override
  void initState() {
    super.initState();

    _settingsItems = [
      SettingsItem(
        title: 'Transcription Provider',
        viewBuilder: (context) => TranscriptionProviderConfigurationView(),
      ),
      SettingsItem(
        title: 'Hotkeys',
        viewBuilder:
            (context) => HotkeysSettingsView(
              onHotkeyChanged: widget.onHotkeyChanged,
              onRecordingStarted: widget.onRecordingStarted,
            ),
      ),
    ];
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: kDotSize * 2,
      left: kDotSize * 2.5,
      child: _buildSettingsContainer(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              SizedBox(height: 16),
              _selectedSetting != null
                  ? _selectedSetting!.viewBuilder(context)
                  : _buildMenu(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsContainer({required Widget child}) {
    return Container(
      width: widget.expandedWindowSize.width - kDotSize * 3,
      height: widget.expandedWindowSize.height - kDotSize * 3,
      decoration: BoxDecoration(
        color: AppColors.zinc900,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.zinc700, width: 1),
      ),
      child: child,
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        if (_selectedSetting != null)
          _HoverableIcon(
            iconData: Icons.arrow_back_ios_new,
            onTap: () => setState(() => _selectedSetting = null),
            color: AppColors.zinc500,
            hoverColor: AppColors.zinc300,
          ),
        if (_selectedSetting != null) SizedBox(width: 8),
        Text(
          _selectedSetting?.title ?? 'Settings',
          style: TextStyle(
            color: AppColors.zinc300,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildMenuItem({required String title, required VoidCallback onTap}) {
    return _MenuItem(title: title, onTap: onTap);
  }

  Widget _buildMenu() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children:
          _settingsItems.map((item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: _buildMenuItem(
                title: item.title,
                onTap: () => setState(() => _selectedSetting = item),
              ),
            );
          }).toList(),
    );
  }
}

class _HoverableIcon extends StatefulWidget {
  final IconData iconData;
  final VoidCallback onTap;
  final Color color;
  final Color? hoverColor;

  const _HoverableIcon({
    required this.iconData,
    required this.onTap,
    this.color = Colors.white,
    this.hoverColor,
  });

  @override
  __HoverableIconState createState() => __HoverableIconState();
}

class __HoverableIconState extends State<_HoverableIcon> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: _isHovering ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Icon(
          widget.iconData,
          color: _isHovering && widget.hoverColor != null
              ? widget.hoverColor
              : widget.color,
          size: 20,
        ),
      ),
    );
  }
}

class _MenuItem extends StatefulWidget {
  final String title;
  final VoidCallback onTap;

  const _MenuItem({required this.title, required this.onTap});

  @override
  __MenuItemState createState() => __MenuItemState();
}

class __MenuItemState extends State<_MenuItem> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: _isHovering ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: _isHovering ? AppColors.zinc800 : AppColors.zinc900,
            borderRadius: BorderRadius.circular(8),
          ),
          padding: EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                style: TextStyle(
                  color: _isHovering ? Colors.white : AppColors.zinc300,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
                child: Text(widget.title),
              ),
              TweenAnimationBuilder<Color?>(
                tween: ColorTween(
                  end: _isHovering ? AppColors.zinc300 : AppColors.zinc500,
                ),
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                builder: (context, color, _) => Icon(
                  Icons.chevron_right,
                  color: color,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
