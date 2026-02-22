import 'dart:async';
import 'dart:io' show Platform;
import 'package:hotkey_manager/hotkey_manager.dart';

typedef KeyState = ({
  int ticks,
  Timer? keyDownTimer,
  int lastEventTimeMs,
  List<int> intervals,
});

typedef KeyEventHandler = void Function();

typedef RegisterHotkeyParams =
    ({HotKey hotKey, KeyEventHandler? onKeyDown, KeyEventHandler? onKeyUp});

/// Registers system-wide hotkeys and provides onKeyDown/onKeyUp callbacks.
///
/// Key release detection is platform-specific:
///
/// **macOS** — Carbon API provides native key-up events. The keyUpHandler
/// is registered directly, giving instant release detection with no latency.
/// No timer-based workaround is needed.
///
/// **Windows / Linux** — The underlying APIs (Win32 RegisterHotKey, X11
/// keybinder) only fire key-down events, with no key-up. While a key is
/// held, the OS sends repeated key-down messages at the keyboard repeat
/// rate. Release is detected by a timer-based debounce: if no repeat
/// event arrives within an adaptive timeout, the key is considered
/// released. The timeout adapts to the user's actual repeat rate using
/// the median of the last 5 observed intervals (multiplied by 3).
/// Intervals outside [10ms, 2000ms] are filtered out to reject event
/// batching artifacts and system stalls.
class ShortcutHelper {
  static const int _maxIntervals = 5;
  static const int _firstPressDelay = 1500;
  static const int _warmupDelay = 600;
  static const int _minAdaptiveDelay = 300;
  static const int _maxAdaptiveDelay = 2000;
  static const int _intervalMultiplier = 3;
  static const int _minValidInterval = 10;
  static const int _maxValidInterval = 2000;

  final Map<String, KeyState> _keyState = {};
  final Map<String, RegisterHotkeyParams> _hotkeyParams = {};
  final Stopwatch _stopwatch = Stopwatch()..start();

  ShortcutHelper();

  int _monotonicNowMs() => _stopwatch.elapsedMilliseconds;

  Future<void> init() async {
    for (final state in _keyState.values) {
      state.keyDownTimer?.cancel();
    }
    _keyState.clear();
    _hotkeyParams.clear();
    await hotKeyManager.unregisterAll();
  }

  Future<void> dispose() async {
    for (final state in _keyState.values) {
      state.keyDownTimer?.cancel();
    }
    _keyState.clear();
    _hotkeyParams.clear();
    await hotKeyManager.unregisterAll();
  }

  String _getModifierKeyLabel(HotKeyModifier modifier) {
    return modifier.physicalKeys.map((key) => key.keyLabel).join('+');
  }

  String _makeUniqueKey(HotKey hotKey) {
    var modifiers = hotKey.modifiers ?? [];
    var modifierKeys = modifiers.map(
      (modifier) => _getModifierKeyLabel(modifier),
    );

    return [...modifierKeys, hotKey.key.keyLabel].join('+');
  }

  Future<void> registerHotkey(RegisterHotkeyParams params) async {
    var key = _makeUniqueKey(params.hotKey);
    _hotkeyParams[key] = params;

    await hotKeyManager.register(
      params.hotKey,
      keyDownHandler: (hotKey) {
        _onKeyDown(key);
      },
      keyUpHandler: Platform.isMacOS
          ? (hotKey) {
              _onNativeKeyUp(key);
            }
          : null,
    );
  }

  void _onNativeKeyUp(String key) {
    final keyState = _keyState[key];
    if (keyState == null) return;
    keyState.keyDownTimer?.cancel();
    _keyState.remove(key);
    _hotkeyParams[key]?.onKeyUp?.call();
  }

  int _median(List<int> values) {
    final sorted = [...values]..sort();
    return sorted[sorted.length ~/ 2];
  }

  int _getKeydownWatchDelay(KeyState state) {
    if (state.ticks == 0) return _firstPressDelay;
    if (state.intervals.length < 3) return _warmupDelay;
    final median = _median(state.intervals);
    return (median * _intervalMultiplier).clamp(
      _minAdaptiveDelay,
      _maxAdaptiveDelay,
    );
  }

  void _startKeyDownTimer(String key) {
    final keyState = _keyState[key];
    if (keyState == null) return;

    final delay = _getKeydownWatchDelay(keyState);

    keyState.keyDownTimer?.cancel();
    final timer = Timer(Duration(milliseconds: delay), () {
      _onKeyRelease(key);
    });

    _keyState[key] = (
      ticks: keyState.ticks,
      keyDownTimer: timer,
      lastEventTimeMs: keyState.lastEventTimeMs,
      intervals: keyState.intervals,
    );
  }

  void _onKeyDown(String key) {
    var keyState = _keyState[key];
    var params = _hotkeyParams[key];
    final now = _monotonicNowMs();

    if (keyState == null) {
      keyState = (
        ticks: 0,
        keyDownTimer: null,
        lastEventTimeMs: now,
        intervals: <int>[],
      );
      params?.onKeyDown?.call();
    } else {
      final gap = now - keyState.lastEventTimeMs;
      final expectedDelay = _getKeydownWatchDelay(keyState);

      if (gap >= expectedDelay) {
        keyState.keyDownTimer?.cancel();
        _keyState.remove(key);
        params?.onKeyUp?.call();
        return;
      } else {
        final intervals = keyState.intervals;
        if (gap >= _minValidInterval && gap <= _maxValidInterval) {
          intervals.add(gap);
          if (intervals.length > _maxIntervals) {
            intervals.removeAt(0);
          }
        }

        keyState = (
          ticks: keyState.ticks + 1,
          keyDownTimer: keyState.keyDownTimer,
          lastEventTimeMs: now,
          intervals: intervals,
        );
      }
    }

    _keyState[key] = keyState;

    if (!Platform.isMacOS) {
      _startKeyDownTimer(key);
    }
  }

  void _onKeyRelease(String key) {
    final keyState = _keyState[key];
    if (keyState == null) return;

    var params = _hotkeyParams[key];
    params?.onKeyUp?.call();

    _keyState.remove(key);
  }
}
