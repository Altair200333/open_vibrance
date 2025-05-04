import 'package:clipboard/clipboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_vibrance/transcription/eleven_labs_transcription_provider.dart';
import 'package:open_vibrance/utils/clipboard.dart';
import 'package:open_vibrance/widgets/settings_box.dart';
import 'package:window_manager/window_manager.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:hotkey_manager/hotkey_manager.dart';
import 'dart:async';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:open_vibrance/utils/shortcut_helper.dart';
import 'package:open_vibrance/widgets/drag_handle.dart';
import 'package:record/record.dart';
import 'dart:io';

const double dotSize = 20;
const Size initialWindowSize = Size(100, 30);
const Size expandedWindowSize = Size(600, 600);

enum IndicatorState { idle, hovered, recording, transcribing, expanded }

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // initialize acrylic & window_manager
  await acrylic.Window.initialize();
  await windowManager.ensureInitialized();

  runApp(const DotApp());
}

class DotApp extends StatelessWidget {
  const DotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _DotWindow(),
    );
  }
}

class _DotWindow extends StatefulWidget {
  const _DotWindow();

  @override
  State<_DotWindow> createState() => _DotWindowState();
}

class _DotWindowState extends State<_DotWindow> with WindowListener {
  // Replace boolean flags with a single enum
  IndicatorState _indicatorState = IndicatorState.idle;
  bool _dragging = false;
  bool _hoveringWindow = false;
  bool _showWindowContent = false;
  bool _settingsBoxVisible = false;

  double _pointerX = 0;
  AudioRecorder? _audioRecorder;

  final ShortcutHelper _shortcutHelper = ShortcutHelper();

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _initWindow();

    _registerHotKeys();
  }

  Future<void> _registerHotKeys() async {
    print('Registering hotkeys for ${defaultTargetPlatform}');

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
    // instantiate recorder if needed
    _audioRecorder = AudioRecorder();
    final recorder = _audioRecorder;
    if (recorder == null) {
      return;
    }

    // check/request permission
    var hasPermission = await recorder.hasPermission();
    if (!hasPermission) {
      return;
    }

    // start file recording for debugging
    await recorder.start(
      const RecordConfig(encoder: AudioEncoder.wav),
      path: 'last_recording.wav',
    );
  }

  Future<void> _transcribeFile(String path) async {
    var bytes = await File(path).readAsBytes();
    var transcriptionProvider = ElevenLabsTranscriptionProvider();
    try {
      setState(() => _indicatorState = IndicatorState.transcribing);
      var transcription = await transcriptionProvider.transcribe(bytes);
      print('Transcription: $transcription');

      await FlutterClipboard.copy(transcription);
      await Future.delayed(Duration(milliseconds: 50));
      await pasteContent();
    } catch (e) {
      print('Error transcribing file: $e');
    } finally {
      setState(() => _indicatorState = IndicatorState.idle);
    }
  }

  Future<void> _stopRecording() async {
    final recorder = _audioRecorder;
    if (recorder == null) {
      return;
    }

    final path = await recorder.stop();

    if (path != null) {
      await _transcribeFile(path);
    } else {
      setState(() => _indicatorState = IndicatorState.idle);
    }

    recorder.dispose();
    _audioRecorder = null;
  }

  void _onStartRecording() {
    if (_indicatorState != IndicatorState.idle &&
        _indicatorState != IndicatorState.hovered) {
      return;
    }
    print('onStartRecording');
    setState(() => _indicatorState = IndicatorState.recording);

    _startRecording();
  }

  void _onStopRecording() {
    print('onStopRecording');

    _stopRecording();
  }

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
    if (!_dragging) {
      setState(() => _dragging = true);
    }
  }

  Future<void> _initWindow() async {
    // 1. get primary display geometry
    final display = await screenRetriever.getPrimaryDisplay();
    final offset = Offset(
      display.size.width / 2 - dotSize / 2,
      display.size.height / 2 - dotSize / 2,
    );

    // 2. configure window options
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

    // 3. show window with transparency effect
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setHasShadow(false);
      await windowManager.setPosition(offset);
      await windowManager.setIgnoreMouseEvents(false);
      await windowManager.setAlwaysOnTop(true);

      windowManager.addListener(this);
      // USE TO DISABLE WINDOW BORDER
      await windowManager.setAsFrameless();

      // native transparency effect before showing to avoid flicker
      await acrylic.Window.setEffect(
        effect: acrylic.WindowEffect.transparent,
        color: Colors.transparent,
      );
      await windowManager.show();
    });
  }

  @override
  void dispose() {
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
      if (_indicatorState != IndicatorState.recording &&
          _indicatorState != IndicatorState.transcribing &&
          _indicatorState != IndicatorState.expanded) {
        _indicatorState = IndicatorState.hovered;
      }
      _showWindowContent = true;
    });
  }

  void onHoverIndicator(PointerHoverEvent event) {
    setState(() => _pointerX = event.localPosition.dx);
    _updateIndicatorHoveringState();
  }

  void onMouseEnterIndicator(PointerEnterEvent event) {
    _updateIndicatorHoveringState();
  }

  void onMouseExitIndicator(PointerExitEvent event) {
    setState(() {
      if (_indicatorState != IndicatorState.recording &&
          _indicatorState != IndicatorState.transcribing &&
          _indicatorState != IndicatorState.expanded) {
        _indicatorState = IndicatorState.idle;
      }
    });
  }

  void onMouseEnterWindow(PointerEnterEvent event) {
    setState(() => _hoveringWindow = true);
  }

  void onMouseExitWindow(PointerExitEvent event) {
    setState(() {
      _hoveringWindow = false;
      _showWindowContent = false;
    });
  }

  Rect _getWindowBounds(Offset currentPosition, bool isExpanded) {
    Size newSize;
    Offset newPosition;
    if (isExpanded) {
      // collapse window
      newPosition = Offset(
        currentPosition.dx,
        currentPosition.dy +
            expandedWindowSize.height -
            initialWindowSize.height * 0.5 -
            dotSize +
            4, // hacky offset to avoid jumping
      );
      newSize = initialWindowSize;
    } else {
      // expand window
      newPosition = Offset(
        currentPosition.dx,
        currentPosition.dy +
            initialWindowSize.height * 0.5 -
            expandedWindowSize.height +
            dotSize -
            3.5, // hacky offset to avoid jumping
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

  AlignmentGeometry get _indicatorAlignment {
    var isExpanded = _indicatorState == IndicatorState.expanded;
    if (isExpanded) {
      return Alignment.bottomCenter;
    }
    return Alignment.center;
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
            Container(
              alignment: _indicatorAlignment,
              decoration: getWindowBoxDecoration(),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildDragHandle(),
                  SizedBox(width: 16),
                  DotIndicator(
                    state: _indicatorState,
                    onTap: onIndicatorTap,
                    onEnter: onMouseEnterIndicator,
                    onExit: onMouseExitIndicator,
                    onHover: onHoverIndicator,
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

// Extracted DotIndicator widget
class DotIndicator extends StatelessWidget {
  final IndicatorState state;
  final VoidCallback onTap;
  final PointerEnterEventListener onEnter;
  final PointerExitEventListener onExit;
  final PointerHoverEventListener onHover;

  const DotIndicator({
    super.key,
    required this.state,
    required this.onTap,
    required this.onEnter,
    required this.onExit,
    required this.onHover,
  });

  double get _indicatorDotWidth {
    switch (state) {
      case IndicatorState.recording:
        return dotSize;
      case IndicatorState.transcribing:
        return dotSize;
      case IndicatorState.expanded:
        return dotSize;
      case IndicatorState.hovered:
        return dotSize * 2.5;
      case IndicatorState.idle:
      default:
        return dotSize * 2;
    }
  }

  double get _indicatorDotHeight {
    switch (state) {
      case IndicatorState.recording:
        return dotSize;
      case IndicatorState.transcribing:
        return dotSize;
      case IndicatorState.expanded:
        return dotSize;
      case IndicatorState.hovered:
        return dotSize;
      case IndicatorState.idle:
      default:
        return dotSize * 0.5;
    }
  }

  BoxDecoration get _indicatorDotDecoration {
    switch (state) {
      case IndicatorState.recording:
        return BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(dotSize),
          border: Border.all(color: Colors.white, width: 2),
        );
      case IndicatorState.transcribing:
        return BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(dotSize),
          border: Border.all(color: Colors.blue, width: 2),
        );
      case IndicatorState.expanded:
        return BoxDecoration(
          color: Colors.blue,
          borderRadius: BorderRadius.circular(dotSize),
          border: Border.all(color: Colors.white, width: 2),
        );
      case IndicatorState.hovered:
        return BoxDecoration(
          color: Colors.blue,
          borderRadius: BorderRadius.circular(5),
        );
      case IndicatorState.idle:
      default:
        return BoxDecoration(
          color: Colors.grey.withAlpha(120),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white70, width: 1.5),
        );
    }
  }

  Widget? get _indicatorDotContent {
    switch (state) {
      case IndicatorState.recording:
      case IndicatorState.transcribing:
        return null;
      case IndicatorState.expanded:
        return Icon(Icons.close, color: Colors.white, size: dotSize * 0.65);
      case IndicatorState.hovered:
      case IndicatorState.idle:
      default:
        return AnimatedOpacity(
          opacity: state == IndicatorState.hovered ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
          child: LayoutBuilder(
            builder: (context, constraints) {
              const count = 3;
              return Row(
                spacing: 5.0,
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(count, (index) {
                  final size =
                      state == IndicatorState.hovered
                          ? dotSize * 0.25
                          : dotSize * 0.1;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: size,
                    height: size,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  );
                }),
              );
            },
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: onEnter,
        onExit: onExit,
        onHover: onHover,
        child: SizedBox(
          width: dotSize * 2.5,
          height: dotSize,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeInOutCubic,
              width: _indicatorDotWidth,
              height: _indicatorDotHeight,
              decoration: _indicatorDotDecoration,
              child: _indicatorDotContent,
            ),
          ),
        ),
      ),
    );
  }
}
