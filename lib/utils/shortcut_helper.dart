import 'dart:async';
import 'package:hotkey_manager/hotkey_manager.dart';

// Record type representing key state.
typedef KeyState = ({int ticks, Timer? keyDownTimer});

typedef KeyEventHandler = void Function();

// Parameters for registering a hotkey.
typedef RegisterHotkeyParams =
    ({HotKey hotKey, KeyEventHandler? onKeyDown, KeyEventHandler? onKeyUp});

/// Helper class to register and manage hotkey events.
class ShortcutHelper {
  final Map<String, KeyState> _keyState = {};
  final Map<String, RegisterHotkeyParams> _hotkeyParams = {};

  ShortcutHelper() {
    init();
  }

  Future<void> init() async {
    await hotKeyManager.unregisterAll();
  }

  String _getModifierKeyLabel(HotKeyModifier modifier) {
    return modifier.physicalKeys.map((key) => key.keyLabel).join('+');
  }

  /// Creates a unique key for a hotkey.
  String _makeUniqueKey(HotKey hotKey) {
    var modifiers = hotKey.modifiers ?? [];
    var modifierKeys = modifiers.map(
      (modifier) => _getModifierKeyLabel(modifier),
    );

    return [...modifierKeys, hotKey.key.keyLabel].join('+');
  }

  /// Registers a hotkey and sets up handlers.
  Future<void> registerHotkey(RegisterHotkeyParams params) async {
    var key = _makeUniqueKey(params.hotKey);
    _hotkeyParams[key] = params;

    await hotKeyManager.register(
      params.hotKey,
      keyDownHandler: (hotKey) {
        _onKeyDown(key);
      },
    );
  }

  int _getKeydownWatchDelay(int ticks) => ticks == 0 ? 1000 : 200;

  /// Starts countdown timer for key release.
  /// Debounce key release event when key stops emitting "pressed" events.
  void _startKeyDownTimer(String key) {
    final keyState = _keyState[key];
    if (keyState == null) return;

    var timer = keyState.keyDownTimer;
    final delay = _getKeydownWatchDelay(keyState.ticks);

    timer?.cancel();
    timer = Timer(Duration(milliseconds: delay), () {
      timer?.cancel();
      _onKeyRelease(key);
    });

    _keyState[key] = (ticks: keyState.ticks, keyDownTimer: timer);
  }

  void _onKeyDown(String key) {
    var keyState = _keyState[key];
    var params = _hotkeyParams[key];

    if (keyState == null) {
      keyState = (ticks: 0, keyDownTimer: null);
      params?.onKeyDown?.call();
    } else {
      keyState = (
        ticks: keyState.ticks + 1,
        keyDownTimer: keyState.keyDownTimer,
      );
    }

    _keyState[key] = keyState;

    // for now share implementation between platforms
    _startKeyDownTimer(key);
  }

  void _onKeyRelease(String key) {
    final keyState = _keyState[key];
    if (keyState == null) {
      return;
    }

    var params = _hotkeyParams[key];
    params?.onKeyUp?.call();

    _keyState.remove(key);
  }
}
