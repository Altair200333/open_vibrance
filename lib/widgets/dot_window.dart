import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_vibrance/services/transcription_service.dart';
import 'package:open_vibrance/utils/common.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:open_vibrance/utils/shortcut_helper.dart';
import 'package:open_vibrance/services/audio_service.dart';
import 'package:open_vibrance/widgets/drag_handle.dart';
import 'package:open_vibrance/widgets/dot_indicator.dart';
import 'package:open_vibrance/widgets/settings_box.dart' show SettingsBox;
import 'package:open_vibrance/widgets/constants.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:open_vibrance/services/hotkey_repository.dart';
class DotWindow extends StatefulWidget {
  const DotWindow({super.key});

  @override
  State<DotWindow> createState() => _DotWindowState();
}

class _DotWindowState extends State<DotWindow> with WindowListener {
  IndicatorState _indicatorState = IndicatorState.idle;
  bool _dragging = false;
  bool _hoveringWindow = false;
  bool _hoveringIndicator = false;
  bool _showWindowContent = false;
  bool _settingsBoxVisible = false;

  double _pointerX = 0;
  double _pointerY = 0;

  late final AudioService _audioService;
  double _lastAmplitude = 0;

  final ShortcutHelper _shortcutHelper = ShortcutHelper();
  final TranscriptionService _transcriptionService = TranscriptionService();
  Timer? _exitDebounce;
  Size _actualIdleSize = initialWindowSize;

  @override
  void initState() {
    super.initState();
    _initWindow();

    _registerHotKeys();

    _audioService = AudioService();
    _audioService.addListener(() {
      setState(() => _lastAmplitude = _audioService.amplitude);
    });
  }

  Future<void> _registerHotKeys() async {
    dprint('Registering hotkeys for $defaultTargetPlatform');

    final combo = await HotkeyRepository().readHotkey();
    final modifier = combo?.modifier ?? HotKeyModifier.alt;
    final keys = combo?.keys ?? [PhysicalKeyboardKey.keyQ];

    await _applyHotkeyChanges(modifier, keys);
  }

  Future<void> _startRecording() async {
    try {
      await _audioService.start();
    } catch (e) {
      dprint('Recording failed: $e');
      setState(() => _indicatorState = IndicatorState.idle);
    }
  }

  Future<void> _transcribeFile(String path) async {
    try {
      setState(() => _indicatorState = IndicatorState.transcribing);

      await _transcriptionService.transcribeFileAndPaste(path);
    } catch (e) {
      dprint('Error transcribing file: $e');
    } finally {
      setState(() => _indicatorState = IndicatorState.idle);
    }
  }

  Future<void> _stopRecording() async {
    if (!_canStopRecording()) {
      dprint('Not recording, cant stop');
      return;
    }
    final path = await _audioService.stop();
    if (path != null) {
      await _transcribeFile(path);
    } else {
      setState(() => _indicatorState = IndicatorState.idle);
    }
  }

  bool _canStartRecording() => _indicatorState == IndicatorState.idle;

  bool _canStopRecording() => _indicatorState == IndicatorState.recording;

  void _onStartRecording() {
    if (!_canStartRecording()) {
      return;
    }
    setState(() => _indicatorState = IndicatorState.recording);
    _startRecording();
  }

  void _onStopRecording() => _stopRecording();

  @override
  void onWindowMoved() async {
    setState(() {
      _dragging = false;
      _hoveringWindow = true;
      _showWindowContent = true;
    });
  }

  @override
  void onWindowMove() {
    _exitDebounce?.cancel();
    if (!_dragging) {
      setState(() => _dragging = true);
    }
  }

  Future<void> _initWindow() async {
    final display = await screenRetriever.getPrimaryDisplay();
    final offset = Offset(
      display.size.width / 2 - kDotSize / 2,
      display.size.height / 2 - kDotSize / 2,
    );
    const options = WindowOptions(
      size: initialWindowSize,
      maximumSize: initialWindowSize,
      minimumSize: initialWindowSize,
      center: false,
      backgroundColor: Colors.transparent,
      titleBarStyle: TitleBarStyle.hidden,
      // skipTaskbar: true,
      alwaysOnTop: true,
    );

    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setPosition(offset);
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setAsFrameless();
      await windowManager.setHasShadow(false);
      // Re-apply size: waitUntilReadyToShow calls setSize before setMinimumSize,
      // so Windows enforces SM_CYMINTRACK (~36px) as minimum height.
      // Now that minimumSize is set, the correct 30px height is allowed.
      await windowManager.setSize(initialWindowSize);

      windowManager.addListener(this);

      await acrylic.Window.setEffect(
        effect: acrylic.WindowEffect.transparent,
        color: Colors.transparent,
      );
      await windowManager.show();
      await windowManager.setIgnoreMouseEvents(true, forward: true);
    });
  }

  @override
  void dispose() {
    _exitDebounce?.cancel();
    _audioService.dispose();
    windowManager.removeListener(this);
    super.dispose();
  }

  BoxDecoration? getWindowBoxDecoration() {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.transparent, width: 1.5),
    );
  }

  Widget _buildDragHandle() {
    return DragHandle(
      dragging: _dragging,
      showWindowContent: _showWindowContent,
    );
  }

  void _updateIndicatorHoveringState() {
    setState(() {
      _hoveringIndicator = true;
      _showWindowContent = true;
    });
  }

  void onHoverIndicator(PointerHoverEvent event) {
    setState(() {
      _pointerX = event.localPosition.dx;
      _pointerY = event.localPosition.dy;
    });
    _updateIndicatorHoveringState();
  }

  void onMouseEnterIndicator(PointerEnterEvent event) {
    _updateIndicatorHoveringState();
    _activateWindow();
  }

  void onMouseExitIndicator(PointerExitEvent event) {
    setState(() => _hoveringIndicator = false);
  }

  void onMouseEnterWindow(PointerEnterEvent event) {
    _exitDebounce?.cancel();
    setState(() => _hoveringWindow = true);
  }

  Future<void> _activateWindow() async {
    await windowManager.setIgnoreMouseEvents(false);
  }

  void onMouseExitWindow(PointerExitEvent event) {
    setState(() => _hoveringWindow = false);
    if (_indicatorState != IndicatorState.expanded && !_dragging) {
      _exitDebounce?.cancel();
      _exitDebounce = Timer(const Duration(milliseconds: 150), () {
        if (!_dragging) {
          setState(() {
            _hoveringIndicator = false;
            _showWindowContent = false;
          });
          _deactivateWindow();
        }
      });
    }
  }

  Future<void> _deactivateWindow() async {
    await windowManager.setIgnoreMouseEvents(true, forward: true);
  }

  Future<void> _handleToggleSettingsBox() async {
    final isExpanded = _indicatorState == IndicatorState.expanded;

    // Use actual window bounds to avoid DPI/OS rounding discrepancies
    final currentPos = await windowManager.getPosition();
    final currentSize = await windowManager.getSize();
    final Size targetSize;
    if (isExpanded) {
      // Collapsing: use the actual idle size (may differ from nominal due to OS constraints)
      targetSize = _actualIdleSize;
    } else {
      // Expanding: save actual idle size before growing
      _actualIdleSize = currentSize;
      targetSize = expandedWindowSize;
    }

    // Keep the bottom edge pinned at the same screen position
    final newTop = currentPos.dy + currentSize.height - targetSize.height;
    final bounds = Rect.fromLTWH(
      currentPos.dx,
      newTop,
      targetSize.width,
      targetSize.height,
    );

    setState(() {
      _settingsBoxVisible = !isExpanded;
      _indicatorState = isExpanded ? IndicatorState.idle : IndicatorState.expanded;
    });

    // Relax constraints to allow target size, then set bounds atomically.
    // Locking min=max after setBounds can trigger Windows to re-adjust position.
    await windowManager.setMinimumSize(initialWindowSize);
    await windowManager.setMaximumSize(expandedWindowSize);
    await windowManager.setBounds(bounds);

    // Restore click-through after collapsing back to idle
    if (isExpanded) {
      await windowManager.setIgnoreMouseEvents(true, forward: true);
    }
  }

  bool _canToggleSettingsBox() {
    return _indicatorState == IndicatorState.idle ||
        _indicatorState == IndicatorState.expanded;
  }

  void onIndicatorTap() {
    if (!_canToggleSettingsBox()) {
      return;
    }
    _handleToggleSettingsBox();
  }

  void _onHotkeyChanged(
    HotKeyModifier modifier,
    List<PhysicalKeyboardKey> keys,
  ) {
    _applyHotkeyChanges(modifier, keys);
  }

  Future<void> _applyHotkeyChanges(
    HotKeyModifier modifier,
    List<PhysicalKeyboardKey> keys,
  ) async {
    await _shortcutHelper.init();

    for (var key in keys) {
      final hotKey = HotKey(
        key: key,
        modifiers: [modifier],
        scope: HotKeyScope.system,
      );
      await _shortcutHelper.registerHotkey((
        hotKey: hotKey,
        onKeyDown: _onStartRecording,
        onKeyUp: _onStopRecording,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: MouseRegion(
        onEnter: onMouseEnterWindow,
        onExit: onMouseExitWindow,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(decoration: getWindowBoxDecoration()),
            if (_settingsBoxVisible)
              SettingsBox(
                expandedWindowSize: expandedWindowSize,
                onHotkeyChanged: _onHotkeyChanged,
              ),
            Positioned(
              left: 0,
              bottom: 0,
              child: SizedBox(
                width: initialWindowSize.width,
                height: initialWindowSize.height,
                child: Container(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (_showWindowContent) ...[
                        _buildDragHandle(),
                        const SizedBox(width: 16),
                      ],
                      DotIndicator(
                        state: _indicatorState,
                        onTap: onIndicatorTap,
                        onEnter: onMouseEnterIndicator,
                        onExit: onMouseExitIndicator,
                        onHover: onHoverIndicator,
                        volume: _lastAmplitude,
                        isHovered: _hoveringIndicator,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
