import 'dart:async';
import 'package:flutter/material.dart';
import 'package:open_vibrance/theme/app_colors.dart';
import 'package:open_vibrance/widgets/constants.dart';
import 'package:open_vibrance/widgets/hoverable_icon.dart';
import 'package:open_vibrance/widgets/provider_settings/transcription_provider_configuration_view.dart';
import 'package:open_vibrance/widgets/provider_settings/hotkeys_settings_view.dart';
import 'package:open_vibrance/widgets/provider_settings/history_view.dart';
import 'package:open_vibrance/services/history_repository.dart';
import 'package:open_vibrance/services/transcription_service.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class SettingsItem {
  final String title;
  final IconData icon;
  final WidgetBuilder viewBuilder;

  SettingsItem({required this.title, required this.icon, required this.viewBuilder});
}

class SettingsBox extends StatefulWidget {
  final void Function(List<HotKeyModifier> modifiers, List<PhysicalKeyboardKey> keys)
      onHotkeyChanged;
  final VoidCallback onRecordingStarted;
  final HistoryRepository historyRepository;
  final TranscriptionService transcriptionService;

  const SettingsBox({
    super.key,
    required this.expandedWindowSize,
    required this.onHotkeyChanged,
    required this.onRecordingStarted,
    required this.historyRepository,
    required this.transcriptionService,
  });

  final Size expandedWindowSize;

  @override
  State<SettingsBox> createState() => _SettingsBoxState();
}

class _SettingsBoxState extends State<SettingsBox> {
  SettingsItem? _selectedSetting;
  bool _showToast = false;
  Timer? _toastTimer;

  late final List<SettingsItem> _settingsItems;

  @override
  void initState() {
    super.initState();

    _settingsItems = [
      SettingsItem(
        title: 'Transcription Provider',
        icon: LucideIcons.settings,
        viewBuilder: (context) => TranscriptionProviderConfigurationView(),
      ),
      SettingsItem(
        title: 'Hotkeys',
        icon: LucideIcons.keyboard,
        viewBuilder:
            (context) => HotkeysSettingsView(
              onHotkeyChanged: widget.onHotkeyChanged,
              onRecordingStarted: widget.onRecordingStarted,
            ),
      ),
      SettingsItem(
        title: 'History',
        icon: LucideIcons.history,
        viewBuilder:
            (context) => HistoryView(
              historyRepository: widget.historyRepository,
              transcriptionService: widget.transcriptionService,
              onCopied: _showCopiedToast,
            ),
      ),
    ];
  }

  void _showCopiedToast() {
    _toastTimer?.cancel();
    setState(() => _showToast = true);
    _toastTimer = Timer(const Duration(seconds: 3), _dismissToast);
  }

  void _dismissToast() {
    _toastTimer?.cancel();
    if (mounted) setState(() => _showToast = false);
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
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
      child: Stack(
        children: [
          child,
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: IgnorePointer(
              ignoring: !_showToast,
              child: AnimatedOpacity(
                opacity: _showToast ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: AnimatedSlide(
                  offset: _showToast ? Offset.zero : const Offset(0, 0.3),
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  child: _Toast(onClose: _dismissToast),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        if (_selectedSetting != null)
          HoverableIcon(
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

  Widget _buildMenuItem({required String title, required IconData icon, required VoidCallback onTap}) {
    return _MenuItem(title: title, icon: icon, onTap: onTap);
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
                icon: item.icon,
                onTap: () => setState(() => _selectedSetting = item),
              ),
            );
          }).toList(),
    );
  }
}

class _Toast extends StatelessWidget {
  final VoidCallback onClose;

  const _Toast({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.zinc800,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.zinc700, width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.content_paste, color: AppColors.zinc400, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Copied to clipboard',
              style: TextStyle(
                color: AppColors.zinc300,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          HoverableIcon(
            iconData: Icons.close,
            onTap: onClose,
            color: AppColors.zinc500,
            hoverColor: AppColors.zinc300,
          ),
        ],
      ),
    );
  }
}

class _MenuItem extends StatefulWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  const _MenuItem({required this.title, required this.icon, required this.onTap});

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
              Row(
                children: [
                  TweenAnimationBuilder<Color?>(
                    tween: ColorTween(
                      end: _isHovering ? AppColors.zinc300 : AppColors.zinc500,
                    ),
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                    builder: (context, color, _) => Icon(
                      widget.icon,
                      color: color,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
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
                ],
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
