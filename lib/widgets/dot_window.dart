import 'dart:async';
import 'package:clipboard/clipboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_vibrance/services/transcription_service.dart';
import 'package:open_vibrance/services/recording_session.dart';
import 'package:open_vibrance/utils/clipboard.dart';
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
import 'package:open_vibrance/services/history_repository.dart';
import 'package:open_vibrance/models/history_entry.dart';

class DotWindow extends StatefulWidget {
  const DotWindow({super.key});

  @override
  State<DotWindow> createState() => _DotWindowState();
}

class _DotWindowState extends State<DotWindow> with WindowListener {
  IndicatorState _indicatorState = IndicatorState.idle;
  bool _dragging = false;
  bool _hoveringIndicator = false;
  bool _showWindowContent = false;
  bool _settingsBoxVisible = false;

  late final AudioService _audioService;

  final ShortcutHelper _shortcutHelper = ShortcutHelper();
  final TranscriptionService _transcriptionService = TranscriptionService();
  final HistoryRepository _historyRepository = HistoryRepository();
  Timer? _exitDebounce;
  Size _actualIdleSize = initialWindowSize;

  RecordingSession? _session;
  Future<void>? _startRecordingFuture;
  Future<void>? _stopRecordingFuture;
  bool _disposed = false;
  bool? _windowInteractive;
  bool _desiredWindowInteractive = false;
  bool _updatingWindowInteraction = false;
  final Stopwatch _mouseTraceClock = Stopwatch()..start();
  int _mouseTraceSequence = 0;
  Duration _lastHoverTraceAt = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initWindow();

    _registerHotKeys();

    _audioService = AudioService();
  }

  Future<void> _registerHotKeys() async {
    dprint('Registering hotkeys for $defaultTargetPlatform');

    final combo = await HotkeyRepository().readHotkey();
    final modifiers = combo?.modifiers ?? [HotKeyModifier.alt];
    final keys = combo?.keys ?? [PhysicalKeyboardKey.keyQ];

    await _applyHotkeyChanges(modifiers, keys);
  }

  Future<void> _startRecording() async {
    String? path;
    try {
      path = await _historyRepository.generateRecordingPath();
      if (_disposed) return;
      final streamingProvider =
          await _transcriptionService.getStreamingProvider();
      if (_disposed) return;

      if (streamingProvider != null) {
        final pcmStream = await _audioService.startStreaming();
        if (_disposed) {
          await _audioService.forceReset();
          return;
        }
        final transcriptDone = Completer<void>();

        final session = StreamingSession(
          recordingPath: path,
          provider: streamingProvider,
          transcriptDone: transcriptDone,
        );

        // Callbacks reference `session` safely — they fire after this sync block.
        session.transcriptSubscription = streamingProvider
            .transcribeStream(pcmStream, sampleRate: 16000)
            .listen(
              (text) {
                session.lastTranscript = text;
              },
              onError: (e) {
                dprint('Streaming transcription error: $e');
                session.transcriptError = e;
                if (!transcriptDone.isCompleted) transcriptDone.complete();
              },
              onDone: () {
                if (!transcriptDone.isCompleted) transcriptDone.complete();
              },
            );

        if (_disposed) {
          await session.dispose();
          await _audioService.forceReset();
          return;
        }
        _session = session;
      } else {
        await _audioService.start(path: path);
        if (_disposed) {
          await _audioService.forceReset();
          return;
        }
        _session = BatchSession(recordingPath: path);
      }
    } catch (e) {
      dprint('Recording failed: $e');
      if (_disposed) return;
      try {
        await _audioService.forceReset();
      } catch (_) {}
      await _saveErrorEntry(path: path);
      await _endSession();
      if (!mounted) {
        return;
      }
      await _showErrorThenIdle();
    }
  }

  Future<void> _stopRecording() async {
    if (!_canStopRecording()) {
      return;
    }

    // Serialize with _startRecording — do NOT set state yet.
    if (_startRecordingFuture != null) {
      try {
        await _startRecordingFuture;
      } catch (_) {}
      _startRecordingFuture = null;
    }

    if (_disposed || !mounted) {
      return;
    }

    // Re-check: start may have failed (→idle) or another stop may have
    // already set transcribing. Either way, nothing to do.
    if (!_canStopRecording()) {
      dprint('Recording start failed or already stopping');
      return;
    }

    setState(() => _indicatorState = IndicatorState.transcribing);

    final session = _session;
    if (session == null) {
      if (mounted) {
        setState(() => _indicatorState = IndicatorState.idle);
      }
      return;
    }

    try {
      switch (session) {
        case StreamingSession():
          await _stopStreaming(session);
        case BatchSession():
          await _stopBatch(session);
      }
    } catch (e) {
      dprint('Stop recording error: $e');
      if (_disposed) return;
      try {
        await _audioService.forceReset();
      } catch (_) {}
      await _saveErrorEntry(path: session.recordingPath);
      if (!mounted) {
        return;
      }
      await _showErrorThenIdle();
    } finally {
      await _endSession();
    }
  }

  Future<void> _stopStreaming(StreamingSession session) async {
    final path = await _audioService.stopStreaming(session.recordingPath);
    await session.transcriptDone.future;
    if (_disposed || session.cancelled) return;
    var transcription = session.lastTranscript;

    if (session.transcriptError != null) {
      dprint(
        'Realtime finalization failed, using saved WAV batch fallback: '
        '${session.transcriptError}',
      );
      transcription = await _transcriptionService
          .transcribeFileWithElevenLabsBatch(path);
      if (_disposed || session.cancelled) return;
    }

    // Save history FIRST — clipboard failure must not lose the transcription
    await _saveHistoryEntry(
      path: path,
      transcription: transcription.isNotEmpty ? transcription : null,
      success: transcription.isNotEmpty,
    );

    if (_disposed || session.cancelled) return;

    if (transcription.isNotEmpty) {
      try {
        await FlutterClipboard.copy(transcription);
        await Future.delayed(const Duration(milliseconds: 100));
        await pasteContent();
      } catch (e) {
        dprint('Clipboard/paste failed: $e');
      }
    }

    if (!mounted) {
      return;
    }
    setState(() => _indicatorState = IndicatorState.idle);
  }

  Future<void> _stopBatch(BatchSession session) async {
    final path = await _audioService.stop();

    if (_disposed) return;

    if (path == null) {
      await _saveErrorEntry(path: session.recordingPath);
      if (!mounted) {
        return;
      }
      setState(() => _indicatorState = IndicatorState.idle);
      return;
    }

    final transcription = await _transcriptionService.transcribeFileAndPaste(
      path,
    );

    if (_disposed) return;

    await _saveHistoryEntry(
      path: path,
      transcription: transcription,
      success: true,
    );

    if (!mounted) {
      return;
    }
    setState(() => _indicatorState = IndicatorState.idle);
  }

  Future<void> _endSession() async {
    try {
      await _session?.dispose();
    } catch (e) {
      dprint('Session dispose error: $e');
    } finally {
      _session = null;
    }
  }

  /// Throws on failure — callers in success paths let this propagate to their
  /// catch block (which saves an error entry and shows the error indicator).
  Future<void> _saveHistoryEntry({
    required String path,
    String? transcription,
    required bool success,
  }) async {
    await _historyRepository.addEntry(
      HistoryEntry(
        id: _historyRepository.idFromPath(path),
        audioFilePath: path,
        transcription: transcription,
        timestamp: DateTime.now(),
        success: success,
      ),
    );
    if (success) {
      _historyRepository.cleanup();
    }
  }

  /// Saves an error entry. Accepts explicit [path] for cases where _session
  /// hasn't been assigned yet. Swallows exceptions (already in error path).
  Future<void> _saveErrorEntry({String? path}) async {
    final recordingPath = path ?? _session?.recordingPath;
    if (recordingPath == null) {
      return;
    }
    try {
      await _saveHistoryEntry(path: recordingPath, success: false);
    } catch (e) {
      dprint('Failed to save error entry: $e');
    }
  }

  Future<void> _showErrorThenIdle() async {
    if (!mounted) {
      return;
    }
    setState(() => _indicatorState = IndicatorState.error);
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) {
      return;
    }
    setState(() => _indicatorState = IndicatorState.idle);
  }

  bool _canStartRecording() =>
      !_disposed && _indicatorState == IndicatorState.idle;

  bool _canStopRecording() =>
      !_disposed && _indicatorState == IndicatorState.recording;

  void _onStartRecording() {
    if (!_canStartRecording()) {
      _mouseTrace('recording.start.ignored');
      return;
    }
    _mouseTraceWithNative('recording.start');
    _exitDebounce?.cancel();
    setState(() {
      _indicatorState = IndicatorState.recording;
      _dragging = false;
      _hoveringIndicator = false;
      _showWindowContent = false;
    });
    unawaited(_setWindowInteractive(false));
    _startRecordingFuture = _startRecording();
  }

  void _onStopRecording() {
    if (_stopRecordingFuture != null) return;

    late final Future<void> stopFuture;
    stopFuture = _stopRecording()
        .catchError((e) {
          dprint('Unhandled stop recording error: $e');
        })
        .whenComplete(() {
          if (identical(_stopRecordingFuture, stopFuture)) {
            _stopRecordingFuture = null;
          }
        });
    _stopRecordingFuture = stopFuture;
  }

  @override
  void onWindowMoved() {
    setState(() => _dragging = false);
    _mouseTraceWithNative('window.moved');
  }

  @override
  void onWindowMove() {
    _exitDebounce?.cancel();
    if (!_dragging) {
      _mouseTrace('window.move');
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
      await _setWindowInteractive(false);
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _exitDebounce?.cancel();
    // Cancel transcript finalization immediately. `_disposed` prevents the
    // stop path from saving or pasting any provisional value.
    final sessionDisposal = _endSession();
    unawaited(
      _disposeRecordingResources(
        _startRecordingFuture,
        _stopRecordingFuture,
        sessionDisposal,
      ),
    );
    _shortcutHelper.dispose();
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _disposeRecordingResources(
    Future<void>? startFuture,
    Future<void>? stopFuture,
    Future<void> sessionDisposal,
  ) async {
    try {
      await startFuture;
    } catch (_) {}
    try {
      await stopFuture;
    } catch (_) {}
    await sessionDisposal;
    await _endSession();
    try {
      await _audioService.forceReset();
    } catch (_) {}
    _audioService.dispose();
  }

  BoxDecoration? getWindowBoxDecoration() {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.transparent, width: 1.5),
    );
  }

  void _mouseTrace(String event, {String details = ''}) {
    final sequence = (++_mouseTraceSequence).toString().padLeft(3, '0');
    final elapsed = _mouseTraceClock.elapsedMilliseconds.toString().padLeft(
      6,
      '0',
    );
    final suffix = details.isEmpty ? '' : ' $details';
    dprint(
      '[mouse #$sequence +${elapsed}ms] $event$suffix | '
      'state=${_indicatorState.name} dragging=$_dragging '
      'indicatorHover=$_hoveringIndicator handle=$_showWindowContent '
      'desiredInteractive=$_desiredWindowInteractive '
      'appliedInteractive=$_windowInteractive '
      'modeUpdate=$_updatingWindowInteraction',
    );
  }

  void _mouseTraceWithNative(String event, {String details = ''}) {
    _mouseTrace(event, details: details);
    unawaited(_traceNativeMouse(event));
  }

  Future<void> _traceNativeMouse(String cause) async {
    try {
      final diagnostics = await windowManager.getMouseDiagnostics();
      _mouseTrace('native.$cause', details: diagnostics.toString());
    } catch (e) {
      _mouseTrace('native.$cause.error', details: '$e');
    }
  }

  Widget _buildDragHandle() {
    final canShow = _canShowDragHandle;
    return DragHandle(
      dragging: canShow && _dragging,
      showWindowContent: canShow && _showWindowContent,
      onHoverChanged: (hovering) {
        _mouseTrace(hovering ? 'handle.enter' : 'handle.exit');
      },
      onDragStart: () => _mouseTraceWithNative('handle.dragStart'),
    );
  }

  bool get _canShowDragHandle =>
      _indicatorState == IndicatorState.idle ||
      _indicatorState == IndicatorState.expanded;

  void _updateIndicatorHoveringState() {
    if (_hoveringIndicator && (!_canShowDragHandle || _showWindowContent)) {
      return;
    }
    setState(() {
      _hoveringIndicator = true;
      if (_canShowDragHandle) {
        _showWindowContent = true;
      }
    });
  }

  void onHoverIndicator(PointerHoverEvent event) {
    _updateIndicatorHoveringState();
    final elapsed = _mouseTraceClock.elapsed;
    if (_windowInteractive != true &&
        elapsed - _lastHoverTraceAt >= const Duration(milliseconds: 250)) {
      _lastHoverTraceAt = elapsed;
      _mouseTrace('indicator.hover', details: 'local=${event.localPosition}');
    }
    if (_canShowDragHandle) {
      unawaited(_setWindowInteractive(true));
    }
  }

  void onMouseEnterIndicator(PointerEnterEvent event) {
    _mouseTrace('indicator.enter', details: 'local=${event.localPosition}');
    _updateIndicatorHoveringState();
    if (_canShowDragHandle) {
      unawaited(_setWindowInteractive(true));
    }
  }

  void onMouseExitIndicator(PointerExitEvent event) {
    _mouseTrace('indicator.exit', details: 'local=${event.localPosition}');
    setState(() => _hoveringIndicator = false);
  }

  void onMouseEnterWindow(PointerEnterEvent event) {
    _exitDebounce?.cancel();
    _mouseTraceWithNative(
      'window.enter',
      details: 'local=${event.localPosition}',
    );
  }

  void onMouseExitWindow(PointerExitEvent event) {
    _mouseTraceWithNative(
      'window.exit',
      details: 'local=${event.localPosition}',
    );
    if (_indicatorState == IndicatorState.expanded || _dragging) {
      _mouseTrace('window.exit.ignored');
      return;
    }

    // A transparent -> interactive Win32 transition can briefly emit a stale
    // leave followed by an enter while the cursor is still inside. Keep the UI
    // stable across that transient pair; a real exit has no matching enter and
    // therefore reaches this callback after the debounce.
    _exitDebounce?.cancel();
    _exitDebounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted || _dragging || _indicatorState == IndicatorState.expanded) {
        return;
      }
      setState(() {
        _hoveringIndicator = false;
        _showWindowContent = false;
      });
      unawaited(_setWindowInteractive(false));
    });
  }

  Future<void> _setWindowInteractive(bool interactive) async {
    final previousDesired = _desiredWindowInteractive;
    _desiredWindowInteractive = interactive;
    final desiredChanged = previousDesired != interactive;
    if (desiredChanged) {
      _mouseTrace('mode.request', details: 'interactive=$interactive');
    }
    if (_updatingWindowInteraction) {
      if (desiredChanged) {
        _mouseTrace('mode.queued', details: 'interactive=$interactive');
      }
      return;
    }

    _updatingWindowInteraction = true;
    try {
      while (_windowInteractive != _desiredWindowInteractive) {
        final target = _desiredWindowInteractive;
        _mouseTrace('mode.apply.begin', details: 'interactive=$target');
        try {
          await windowManager.setIgnoreMouseEvents(!target, forward: !target);
          _windowInteractive = target;
          _mouseTrace('mode.apply.done', details: 'interactive=$target');
          unawaited(_traceNativeMouse('mode.$target'));
        } catch (e) {
          _mouseTrace('mode.apply.error', details: '$e');
          return;
        }
      }
    } finally {
      _updatingWindowInteraction = false;
    }
  }

  Future<void> _handleToggleSettingsBox() async {
    final isExpanded = _indicatorState == IndicatorState.expanded;
    _mouseTraceWithNative(
      'menu.toggle.begin',
      details: isExpanded ? 'collapse' : 'expand',
    );

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

    if (!mounted) return;
    setState(() {
      _settingsBoxVisible = !isExpanded;
      _indicatorState =
          isExpanded ? IndicatorState.idle : IndicatorState.expanded;
    });

    // Hide window during resize to prevent visual flash & overflow
    // (setBounds is not visually atomic on Windows — position and size
    //  may apply in separate frames, causing a brief glitch).
    await windowManager.setOpacity(0);

    // Relax constraints to allow target size, then set bounds atomically.
    // Locking min=max after setBounds can trigger Windows to re-adjust position.
    await windowManager.setMinimumSize(initialWindowSize);
    await windowManager.setMaximumSize(expandedWindowSize);
    await windowManager.setBounds(bounds);

    await windowManager.setOpacity(1);

    if (isExpanded) {
      await _setWindowInteractive(false);
    }
    _mouseTraceWithNative(
      'menu.toggle.done',
      details: isExpanded ? 'collapsed' : 'expanded',
    );
  }

  bool _canToggleSettingsBox() {
    return _indicatorState == IndicatorState.idle ||
        _indicatorState == IndicatorState.expanded;
  }

  void onIndicatorTap() {
    _mouseTraceWithNative('indicator.tap');
    if (!_canToggleSettingsBox()) {
      _mouseTrace('indicator.tap.ignored');
      return;
    }
    _handleToggleSettingsBox();
  }

  void _onRecordingStarted() {
    _shortcutHelper.init();
  }

  void _onHotkeyChanged(
    List<HotKeyModifier> modifiers,
    List<PhysicalKeyboardKey> keys,
  ) {
    _applyHotkeyChanges(modifiers, keys);
  }

  Future<void> _applyHotkeyChanges(
    List<HotKeyModifier> modifiers,
    List<PhysicalKeyboardKey> keys,
  ) async {
    await _shortcutHelper.init();

    for (var key in keys) {
      final hotKey = HotKey(
        key: key,
        modifiers: modifiers,
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
                onRecordingStarted: _onRecordingStarted,
                historyRepository: _historyRepository,
                transcriptionService: _transcriptionService,
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
                      _buildDragHandle(),
                      ListenableBuilder(
                        listenable: _audioService,
                        builder:
                            (context, _) => DotIndicator(
                              state: _indicatorState,
                              onTap: onIndicatorTap,
                              onTapDown:
                                  (details) => _mouseTrace(
                                    'indicator.tapDown',
                                    details: 'local=${details.localPosition}',
                                  ),
                              onTapCancel:
                                  () => _mouseTrace('indicator.tapCancel'),
                              onEnter: onMouseEnterIndicator,
                              onExit: onMouseExitIndicator,
                              onHover: onHoverIndicator,
                              volume: _audioService.amplitude,
                              isHovered: _hoveringIndicator,
                            ),
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
