import 'dart:async';
import 'package:flutter/material.dart';
import 'package:open_vibrance/theme/app_color_theme.dart';
import 'package:open_vibrance/widgets/constants.dart';
import 'package:open_vibrance/widgets/hoverable_icon.dart';
import 'package:open_vibrance/widgets/provider_settings/transcription_provider_configuration_view.dart';
import 'package:open_vibrance/widgets/provider_settings/hotkeys_settings_view.dart';
import 'package:open_vibrance/widgets/provider_settings/history_view.dart';
import 'package:open_vibrance/widgets/provider_settings/theme_settings_view.dart';
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
      SettingsItem(
        title: 'Themes',
        icon: LucideIcons.palette,
        viewBuilder: (context) => const ThemeSettingsView(),
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
    final colors = context.colors;

    return Positioned(
      bottom: kDotSize * 2,
      left: kDotSize * 2.5,
      child: _buildSettingsContainer(
        colors: colors,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _buildHeader(colors),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: _selectedSetting != null
                    ? _selectedSetting!.viewBuilder(context)
                    : _buildMenu(colors),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsContainer({required AppColorTheme colors, required Widget child}) {
    return Container(
      width: widget.expandedWindowSize.width - kDotSize * 3,
      height: widget.expandedWindowSize.height - kDotSize * 3,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(kRadiusLg),
        border: Border.all(color: colors.border, width: 1),
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
                duration: kHoverDuration,
                child: AnimatedSlide(
                  offset: _showToast ? Offset.zero : const Offset(0, 0.3),
                  duration: kHoverDuration,
                  curve: kHoverCurve,
                  child: _Toast(onClose: _dismissToast),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(AppColorTheme colors) {
    return Row(
      children: [
        if (_selectedSetting != null)
          HoverableIcon(
            iconData: Icons.arrow_back_ios_new,
            onTap: () => setState(() => _selectedSetting = null),
            color: colors.iconDefault,
            hoverColor: colors.iconHover,
          ),
        if (_selectedSetting != null) SizedBox(width: 8),
        Text(
          _selectedSetting?.title ?? 'Settings',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: kFontSizeXl,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildMenu(AppColorTheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children:
          _settingsItems.map((item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: _MenuItem(
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
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(kRadiusMd),
        border: Border.all(color: colors.border, width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.content_paste, color: colors.textSecondary, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Copied to clipboard',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: kFontSizeMd,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          HoverableIcon(
            iconData: Icons.close,
            onTap: onClose,
            color: colors.iconDefault,
            hoverColor: colors.iconHover,
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
    final colors = context.colors;

    return MouseRegion(
      cursor: _isHovering ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: kHoverDuration,
          curve: kHoverCurve,
          decoration: BoxDecoration(
            color: _isHovering ? colors.surfaceElevated : colors.surface,
            borderRadius: BorderRadius.circular(kRadiusMd),
          ),
          padding: EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  TweenAnimationBuilder<Color?>(
                    tween: ColorTween(
                      end: _isHovering ? colors.iconHover : colors.iconDefault,
                    ),
                    duration: kHoverDuration,
                    curve: kHoverCurve,
                    builder: (context, color, _) => Icon(
                      widget.icon,
                      color: color,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  AnimatedDefaultTextStyle(
                    duration: kHoverDuration,
                    curve: kHoverCurve,
                    style: TextStyle(
                      color: _isHovering ? colors.textOnPrimary : colors.textPrimary,
                      fontWeight: FontWeight.w500,
                      fontSize: kFontSizeLg,
                    ),
                    child: Text(widget.title),
                  ),
                ],
              ),
              TweenAnimationBuilder<Color?>(
                tween: ColorTween(
                  end: _isHovering ? colors.iconHover : colors.iconDefault,
                ),
                duration: kHoverDuration,
                curve: kHoverCurve,
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
