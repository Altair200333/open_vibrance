import 'package:flutter/material.dart';
import 'package:open_vibrance/theme/app_colors.dart';
import 'package:open_vibrance/widgets/constants.dart';
import 'package:open_vibrance/widgets/provider_settings/transcription_provider_configuration_view.dart';

class SettingsItem {
  final String title;
  final WidgetBuilder viewBuilder;

  SettingsItem({required this.title, required this.viewBuilder});
}

class SettingsBox extends StatefulWidget {
  const SettingsBox({super.key, required this.expandedWindowSize});

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
        color: AppColors.gray700,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: child,
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        if (_selectedSetting != null)
          _HoverableIcon(
            iconData: Icons.arrow_back,
            onTap: () => setState(() => _selectedSetting = null),
          ),
        if (_selectedSetting != null) SizedBox(width: 8),
        Text(
          _selectedSetting?.title ?? 'Settings',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
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
  final double scaleFactor;

  const _HoverableIcon({
    required this.iconData,
    required this.onTap,
    this.color = Colors.white,
    this.scaleFactor = 1.3,
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
        child: AnimatedScale(
          scale: _isHovering ? widget.scaleFactor : 1.0,
          duration: const Duration(milliseconds: 100),
          child: Icon(widget.iconData, color: widget.color),
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
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            color: AppColors.gray700,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isHovering ? Colors.white : AppColors.gray500,
              width: 2,
            ),
          ),
          padding: EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.title,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              AnimatedScale(
                scale: _isHovering ? 1.4 : 1.0,
                duration: const Duration(milliseconds: 100),
                child: Icon(Icons.chevron_right, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
