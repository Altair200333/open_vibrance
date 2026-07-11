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

class _DotWindowState extends State<DotWindow>
    with WindowListener, SingleTickerProviderStateMixin {
  IndicatorState _indicatorState = IndicatorState.idle;
  bool _dragging = false;
  bool _hoveringIndicator = false;
  bool _showWindowContent = false;
  bool _settingsBoxVisible = false;
  bool _settingsTransitioning = false;

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
  late final AnimationController _settingsTransitionController;
  late final CurvedAnimation _settingsTransition;

  @override
  void initState() {
    super.initState();
    _settingsTransitionController = AnimationController(
      vsync: this,
      duration: kSettingsTransitionDuration,
      reverseDuration: kSettingsTransitionDuration,
    );
    _settingsTransition = CurvedAnimation(
      parent: _settingsTransitionController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
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
    } on TickerCanceled {
      // Expected when the app is disposed during the transition.
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
      !_disposed &&
      !_settingsTransitioning &&
      _indicatorState == IndicatorState.idle;

  bool _canStopRecording() =>
      !_disposed && _indicatorState == IndicatorState.recording;

  void _onStartRecording() {
    if (!_canStartRecording()) return;
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
      // Keep the full transition range available so opening/closing only needs
      // one native bounds update instead of extra platform-channel calls.
      await windowManager.setMinimumSize(initialWindowSize);
      await windowManager.setMaximumSize(expandedWindowSize);

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
    _settingsTransition.dispose();
    _settingsTransitionController.dispose();
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

  Widget _buildDragHandle() {
    final canShow = _canShowDragHandle;
    return DragHandle(
      dragging: canShow && _dragging,
      showWindowContent: canShow && _showWindowContent,
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

  void onHoverIndicator(PointerHoverEvent _) {
    _updateIndicatorHoveringState();
    if (_canShowDragHandle) {
      unawaited(_setWindowInteractive(true));
    }
  }

  void onMouseEnterIndicator(PointerEnterEvent _) {
    _updateIndicatorHoveringState();
    if (_canShowDragHandle) {
      unawaited(_setWindowInteractive(true));
    }
  }

  void onMouseExitIndicator(PointerExitEvent _) {
    setState(() => _hoveringIndicator = false);
  }

  void onMouseEnterWindow(PointerEnterEvent _) {
    _exitDebounce?.cancel();
  }

  void onMouseExitWindow(PointerExitEvent _) {
    if (_indicatorState == IndicatorState.expanded ||
        _dragging ||
        _settingsTransitioning) {
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
    _desiredWindowInteractive = interactive;
    if (_updatingWindowInteraction) return;

    _updatingWindowInteraction = true;
    try {
      while (_windowInteractive != _desiredWindowInteractive) {
        final target = _desiredWindowInteractive;
        try {
          await windowManager.setIgnoreMouseEvents(!target, forward: !target);
          _windowInteractive = target;
        } catch (e) {
          dprint('Failed to update window interaction: $e');
          return;
        }
      }
    } finally {
      _updatingWindowInteraction = false;
    }
  }

  Future<void> _handleToggleSettingsBox() async {
    if (_settingsTransitioning) return;
    _settingsTransitioning = true;
    final isExpanded = _indicatorState == IndicatorState.expanded;

    try {
      // Use actual bounds to preserve the exact bottom edge across DPI and OS
      // rounding instead of relying on the nominal idle size.
      final currentPos = await windowManager.getPosition();
      final currentSize = await windowManager.getSize();
      final Size targetSize;
      if (isExpanded) {
        targetSize = _actualIdleSize;
      } else {
        _actualIdleSize = currentSize;
        targetSize = expandedWindowSize;
      }

      final newTop = currentPos.dy + currentSize.height - targetSize.height;
      final bounds = Rect.fromLTWH(
        currentPos.dx,
        newTop,
        targetSize.width,
        targetSize.height,
      );

      if (!mounted) return;
      if (isExpanded) {
        await _collapseSettingsBox(bounds);
      } else {
        await _expandSettingsBox(bounds);
      }
    } catch (e) {
      dprint('Settings transition failed: $e');
    } finally {
      _settingsTransitioning = false;
    }
  }

  Future<void> _expandSettingsBox(Rect bounds) async {
    // Resize first while only the bottom-pinned indicator is painted. The new
    // area is transparent, so the geometry change itself has nothing to flash.
    await windowManager.setBounds(bounds);
    await _waitForNextFrame();
    if (!mounted) return;

    _settingsTransitionController.value = 0;
    setState(() {
      _settingsBoxVisible = true;
      _indicatorState = IndicatorState.expanded;
    });
    await _setWindowInteractive(true);

    // Build and lay out the panel at opacity zero before its first visible
    // animation frame.
    await _waitForNextFrame();
    if (!mounted) return;
    await _settingsTransitionController.forward().orCancel;
  }

  Future<void> _collapseSettingsBox(Rect bounds) async {
    // Morph the indicator back while the panel fades toward its anchor.
    setState(() => _indicatorState = IndicatorState.idle);
    await _settingsTransitionController.reverse().orCancel;
    if (!mounted) return;

    setState(() => _settingsBoxVisible = false);
    await _waitForNextFrame();
    if (!mounted) return;

    // Once only the indicator remains, shrinking the transparent HWND cannot
    // expose a clipped SettingsBox frame.
    await windowManager.setBounds(bounds);
    await _waitForNextFrame();
    if (!await _isCursorInsideWindow()) {
      await _setWindowInteractive(false);
    }
  }

  Future<bool> _isCursorInsideWindow() async {
    try {
      final diagnostics = await windowManager.getMouseDiagnostics();
      if (diagnostics.isEmpty) return _hoveringIndicator;
      return diagnostics['cursorInside'] == true;
    } catch (_) {
      // Non-Windows implementations may not expose native diagnostics.
      return _hoveringIndicator;
    }
  }

  Future<void> _waitForNextFrame() async {
    if (!mounted) return;
    final binding = WidgetsBinding.instance;
    binding.scheduleFrame();
    await binding.endOfFrame;
  }

  bool _canToggleSettingsBox() {
    return !_settingsTransitioning &&
        (_indicatorState == IndicatorState.idle ||
            _indicatorState == IndicatorState.expanded);
  }

  void onIndicatorTap() {
    if (!_canToggleSettingsBox()) return;
    unawaited(_handleToggleSettingsBox());
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
                transitionAnimation: _settingsTransition,
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
