import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_vibrance/services/transcription_service.dart';
import 'package:open_vibrance/utils/common.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:clipboard/clipboard.dart';
import 'package:open_vibrance/transcription/eleven_labs_transcription_provider.dart';
import 'package:open_vibrance/utils/clipboard.dart';
import 'package:open_vibrance/utils/shortcut_helper.dart';
import 'package:open_vibrance/services/audio_service.dart';
import 'package:open_vibrance/widgets/drag_handle.dart';
import 'package:open_vibrance/widgets/dot_indicator.dart';
import 'package:open_vibrance/widgets/settings_box.dart' show SettingsBox;
import 'package:open_vibrance/widgets/constants.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;

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

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _initWindow();

    _registerHotKeys();
    _audioService = AudioService();
    _audioService.addListener(() {
      setState(() => _lastAmplitude = _audioService.amplitude);
    });
  }

  Future<void> _registerHotKeys() async {
    dprint('Registering hotkeys for $defaultTargetPlatform');
    HotKey hotKey = HotKey(
      key: PhysicalKeyboardKey.keyQ,
      modifiers: [HotKeyModifier.alt],
      scope: HotKeyScope.system,
    );
    _shortcutHelper.registerHotkey((
      hotKey: hotKey,
      onKeyDown: _onStartRecording,
      onKeyUp: _onStopRecording,
    ));
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
    final path = await _audioService.stop();
    if (path != null) {
      await _transcribeFile(path);
    } else {
      setState(() => _indicatorState = IndicatorState.idle);
    }
  }

  bool _canStartRecording() => _indicatorState == IndicatorState.idle;

  void _onStartRecording() {
    if (!_canStartRecording()) return;
    setState(() => _indicatorState = IndicatorState.recording);
    _startRecording();
  }

  void _onStopRecording() => _stopRecording();

  @override
  void onWindowMoved() {
    setState(() {
      _dragging = false;
      _hoveringWindow = true;
      _showWindowContent = true;
    });
  }

  @override
  void onWindowMove() {
    if (!_dragging) setState(() => _dragging = true);
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
      skipTaskbar: true,
      alwaysOnTop: true,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setHasShadow(false);
      await windowManager.setPosition(offset);
      await windowManager.setIgnoreMouseEvents(false);
      await windowManager.setAlwaysOnTop(true);
      windowManager.addListener(this);
      await windowManager.setAsFrameless();
      await acrylic.Window.setEffect(
        effect: acrylic.WindowEffect.transparent,
        color: Colors.transparent,
      );
      await windowManager.show();
    });
  }

  @override
  void dispose() {
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
  }

  void onMouseExitIndicator(PointerExitEvent event) {
    setState(() => _hoveringIndicator = false);
  }

  void onMouseEnterWindow(PointerEnterEvent event) {
    setState(() => _hoveringWindow = true);
  }

  void onMouseExitWindow(PointerExitEvent event) {
    setState(() {
      _hoveringWindow = false;
      _hoveringIndicator = false;
      _showWindowContent = false;
    });
  }

  Rect _getWindowBounds(Offset currentPosition, bool isExpanded) {
    Size newSize;
    Offset newPosition;
    if (isExpanded) {
      newPosition = Offset(
        currentPosition.dx,
        currentPosition.dy +
            expandedWindowSize.height -
            initialWindowSize.height * 0.5 -
            kDotSize +
            4,
      );
      newSize = initialWindowSize;
    } else {
      newPosition = Offset(
        currentPosition.dx,
        currentPosition.dy +
            initialWindowSize.height * 0.5 -
            expandedWindowSize.height +
            kDotSize -
            3.5,
      );
      newSize = expandedWindowSize;
    }
    return Rect.fromLTWH(
      newPosition.dx,
      newPosition.dy,
      newSize.width,
      newSize.height,
    );
  }

  Future<void> _handleToggleSettingsBox() async {
    var currentPosition = await windowManager.getPosition();
    var isExpanded = _indicatorState == IndicatorState.expanded;
    var bounds = _getWindowBounds(currentPosition, isExpanded);
    setState(() => _settingsBoxVisible = !isExpanded);
    await Future.delayed(const Duration(milliseconds: 50));
    windowManager.setMinimumSize(bounds.size);
    windowManager.setMaximumSize(bounds.size);
    windowManager.setBounds(bounds);
    var newState = isExpanded ? IndicatorState.idle : IndicatorState.expanded;
    setState(() => _indicatorState = newState);
  }

  void onIndicatorTap() {
    if (_indicatorState == IndicatorState.recording ||
        _indicatorState == IndicatorState.transcribing) {
      return;
    }
    _handleToggleSettingsBox();
  }

  AlignmentGeometry get _indicatorAlignment =>
      _indicatorState == IndicatorState.expanded
          ? Alignment.bottomCenter
          : Alignment.center;

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
            Container(
              alignment: _indicatorAlignment,
              decoration: getWindowBoxDecoration(),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildDragHandle(),
                  const SizedBox(width: 16),
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
            if (_settingsBoxVisible)
              SettingsBox(expandedWindowSize: expandedWindowSize),
          ],
        ),
      ),
    );
  }
}
