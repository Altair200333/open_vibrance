import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:open_vibrance/services/hotkey_repository.dart';
import 'package:open_vibrance/theme/app_colors.dart';
import 'package:open_vibrance/widgets/constants.dart';
import 'package:open_vibrance/widgets/provider_settings/hotkey_constants.dart';

class HotkeysSettingsView extends StatefulWidget {
  final void Function(
    List<HotKeyModifier> modifiers,
    List<PhysicalKeyboardKey> keys,
  )
  onHotkeyChanged;
  final VoidCallback onRecordingStarted;

  const HotkeysSettingsView({
    super.key,
    required this.onHotkeyChanged,
    required this.onRecordingStarted,
  });

  @override
  State<HotkeysSettingsView> createState() => _HotkeysSettingsViewState();
}

class _HotkeysSettingsViewState extends State<HotkeysSettingsView> {
  HotkeyCombo? _currentCombo;
  bool _isRecording = false;
  String? _liveError;
  bool _isHoveringField = false;
  bool _isHoveringClose = false;

  final Set<PhysicalKeyboardKey> _pressedKeys = {};
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadHotkeySettings();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadHotkeySettings() async {
    final combo = await HotkeyRepository().readHotkey();
    if (mounted) {
      setState(() => _currentCombo = combo);
      if (combo != null) {
        widget.onHotkeyChanged(combo.modifiers, combo.keys);
      }
    }
  }

  void _startRecording() {
    widget.onRecordingStarted();
    setState(() {
      _isRecording = true;
      _liveError = null;
      _pressedKeys.clear();
    });
    _focusNode.requestFocus();
  }

  void _cancelRecording() {
    setState(() {
      _isRecording = false;
      _liveError = null;
    });
    if (_currentCombo != null) {
      widget.onHotkeyChanged(_currentCombo!.modifiers, _currentCombo!.keys);
    }
  }

  void _saveCombo(List<HotKeyModifier> modifiers, PhysicalKeyboardKey key) {
    final combo = HotkeyCombo(modifiers: modifiers, keys: [key]);
    HotkeyRepository().saveHotkey(combo);
    setState(() {
      _currentCombo = combo;
      _isRecording = false;
      _liveError = null;
    });
    widget.onHotkeyChanged(combo.modifiers, combo.keys);
  }

  ({Set<HotKeyModifier> mods, List<PhysicalKeyboardKey> keys}) _splitPressed() {
    final mods = <HotKeyModifier>{};
    final keys = <PhysicalKeyboardKey>[];
    for (final key in _pressedKeys) {
      final mod = physicalKeyToModifier[key];
      if (mod != null) {
        mods.add(mod);
      } else {
        keys.add(key);
      }
    }
    return (mods: mods, keys: keys);
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (!_isRecording) return KeyEventResult.ignored;

    if (event is KeyDownEvent) {
      if (event.physicalKey == PhysicalKeyboardKey.escape) {
        _cancelRecording();
        return KeyEventResult.handled;
      }
      _pressedKeys.add(event.physicalKey);
    } else if (event is KeyUpEvent) {
      _pressedKeys.remove(event.physicalKey);
    }

    final (:mods, :keys) = _splitPressed();

    // Real-time validation
    String? error;
    if (keys.isNotEmpty && mods.isEmpty) {
      error = 'Hold a modifier (Alt, Ctrl, Shift, Win)';
    } else if (keys.length > 1) {
      error = 'Too many keys — press only one key with modifier(s)';
    }

    // Valid combo: modifier(s) + exactly 1 key → save immediately
    if (mods.isNotEmpty && keys.length == 1 && error == null) {
      _saveCombo(mods.toList(), keys.first);
      return KeyEventResult.handled;
    }

    // Clear error when all keys released
    if (_pressedKeys.isEmpty) {
      error = null;
    }

    setState(() => _liveError = error);
    return KeyEventResult.handled;
  }

  String _getDisplayText() {
    if (!_isRecording) {
      return _currentCombo?.toString() ?? 'Alt + Q';
    }
    final (:mods, :keys) = _splitPressed();
    if (mods.isEmpty && keys.isEmpty) {
      return 'Press a key combination...';
    }
    final parts = <String>[
      ...mods.map((m) => modifierLabels[m] ?? ''),
      ...keys.map((k) => k.keyLabel),
    ];
    if (mods.isNotEmpty && keys.isEmpty) {
      parts.add('...');
    }
    return parts.join(' + ');
  }

  bool get _hasError => _isRecording && _liveError != null;

  Color _getBorderColor() {
    if (_hasError) return AppColors.error;
    if (_isRecording) return AppColors.borderFocus;
    if (_isHoveringField) return AppColors.borderHover;
    return AppColors.border;
  }

  Color _getTextColor() {
    if (_hasError) return AppColors.error;
    if (_isRecording) {
      return _pressedKeys.isEmpty ? AppColors.textHint : AppColors.textPrimary;
    }
    return AppColors.textPrimary;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Record hotkey',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: kFontSizeMd,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Click the field below and press modifier + key',
          style: TextStyle(color: AppColors.textHint, fontSize: kFontSizeSm),
        ),
        SizedBox(height: 12),
        Focus(
          focusNode: _focusNode,
          onKeyEvent: _onKeyEvent,
          onFocusChange: (hasFocus) {
            if (!hasFocus && _isRecording) _cancelRecording();
          },
          child: GestureDetector(
            onTap: !_isRecording ? _startRecording : null,
            child: MouseRegion(
              cursor:
                  !_isRecording
                      ? SystemMouseCursors.click
                      : SystemMouseCursors.basic,
              onEnter: (_) => setState(() => _isHoveringField = true),
              onExit: (_) => setState(() => _isHoveringField = false),
              child: AnimatedContainer(
                duration: kHoverDuration,
                curve: kHoverCurve,
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(kRadiusMd),
                  border: Border.all(color: _getBorderColor(), width: 1),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isRecording
                          ? Icons.fiber_manual_record
                          : Icons.keyboard_outlined,
                      color:
                          _isRecording ? AppColors.error : AppColors.iconDefault,
                      size: 16,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _getDisplayText(),
                        style: TextStyle(
                          color: _getTextColor(),
                          fontSize: kFontSizeLg,
                        ),
                      ),
                    ),
                    if (_isRecording)
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        onEnter:
                            (_) => setState(() => _isHoveringClose = true),
                        onExit:
                            (_) => setState(() => _isHoveringClose = false),
                        child: GestureDetector(
                          onTap: _cancelRecording,
                          child: Icon(
                            Icons.close,
                            color:
                                _isHoveringClose
                                    ? AppColors.iconHover
                                    : AppColors.iconDefault,
                            size: 16,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_isRecording) ...[
          SizedBox(height: 8),
          Text(
            _liveError ?? 'Press Esc to cancel',
            style: TextStyle(
              color:
                  _liveError != null ? AppColors.error : AppColors.textHint,
              fontSize: kFontSizeXs,
            ),
          ),
        ],
      ],
    );
  }
}
