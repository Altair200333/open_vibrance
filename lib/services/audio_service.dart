import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:open_vibrance/services/audio_spectrum_analyzer.dart';
import 'package:record/record.dart';

/// Creates the best-effort spectrum observer for a PCM sample rate.
typedef AudioSpectrumAnalyzerFactory =
    AudioSpectrumAnalyzer Function(int sampleRate);

/// Service to handle audio recording logic.
class AudioService extends ChangeNotifier {
  AudioService({
    AudioRecorder? recorder,
    AudioSpectrumAnalyzerFactory? spectrumAnalyzerFactory,
  }) : _recorder = recorder ?? AudioRecorder(),
       _spectrumAnalyzerFactory =
           spectrumAnalyzerFactory ??
           ((sampleRate) => AudioSpectrumAnalyzer(sampleRate: sampleRate));

  static const _pcmDrainTimeout = Duration(seconds: 2);
  static const amplitudeUpdateInterval = Duration(milliseconds: 50);
  static const silenceDb = -160.0;

  final AudioRecorder _recorder;
  final AudioSpectrumAnalyzerFactory _spectrumAnalyzerFactory;
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  double _amplitude = silenceDb;
  AudioSpectrumAnalyzer? _spectrumAnalyzer;
  AudioSpectrumFrame _spectrumFrame = AudioSpectrumFrame.unavailable;
  bool _spectrumDisabled = false;
  bool _disposed = false;

  // Streaming fields
  final BytesBuilder _pcmBuffer = BytesBuilder(copy: false);
  StreamSubscription<Uint8List>? _pcmSubscription;
  StreamController<Uint8List>? _pcmController;
  Completer<void>? _pcmDrainCompleter;
  Object? _pcmStreamError;
  int _streamSampleRate = 16000;

  /// Current amplitude in dB.
  double get amplitude => _amplitude;
  AudioSpectrumFrame get spectrumFrame => _spectrumFrame;

  /// Checks if microphone permission is granted.
  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Starts recording audio and listens for amplitude changes.
  /// If [path] is provided, records to that path; otherwise uses a temp file.
  Future<void> start({String? path}) async {
    _resetMeter();
    final granted = await _recorder.hasPermission();
    if (!granted) {
      throw Exception('Microphone permission denied');
    }

    final recordingPath =
        path ?? '${Directory.systemTemp.path}/last_recording.wav';

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.wav),
      path: recordingPath,
    );
    _amplitudeSubscription = _recorder
        .onAmplitudeChanged(amplitudeUpdateInterval)
        .listen((amplitude) {
          _amplitude = amplitude.current;
          _notifyMeterListeners();
        });
  }

  /// Stops recording and returns the path to the recorded file.
  Future<String?> stop() async {
    final path = await _recorder.stop();
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    _resetMeter();
    return path;
  }

  /// Starts streaming recording. Returns a `Stream<Uint8List>` of raw PCM chunks.
  /// Chunks are also accumulated internally for WAV file construction on stop.
  Future<Stream<Uint8List>> startStreaming({int sampleRate = 16000}) async {
    _resetMeter();
    final granted = await _recorder.hasPermission();
    if (!granted) throw Exception('Microphone permission denied');

    _streamSampleRate = sampleRate;
    _pcmBuffer.clear();
    try {
      _spectrumAnalyzer = _spectrumAnalyzerFactory(sampleRate);
      _spectrumDisabled = false;
    } catch (_) {
      _spectrumAnalyzer = null;
      _spectrumDisabled = true;
    }

    final rawStream = await _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
      ),
    );

    // Tee: buffer chunks for WAV construction + forward to caller.
    final controller = StreamController<Uint8List>();
    final drainCompleter = Completer<void>();
    _pcmController = controller;
    _pcmDrainCompleter = drainCompleter;
    _pcmStreamError = null;
    _pcmSubscription = rawStream.listen(
      (chunk) {
        _pcmBuffer.add(chunk);
        if (!controller.isClosed) {
          controller.add(chunk);
        }
        // Visualization is an observer only: transcription and WAV buffering
        // always receive the original chunk before any best-effort DSP work.
        if (!_spectrumDisabled) {
          try {
            _spectrumAnalyzer?.addPcm16(chunk, _onSpectrumFrame);
          } catch (_) {
            _disableSpectrum();
          }
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _pcmStreamError ??= error;
        _disableSpectrum();
        if (!controller.isClosed) {
          controller.addError(error, stackTrace);
        }
      },
      onDone: () {
        // Stream ordering guarantees every preceding PCM event was tee'd before
        // this callback. Closing queues downstream done after those chunks.
        if (!controller.isClosed) {
          unawaited(_closeControllerIgnoringErrors(controller));
        }
        if (!drainCompleter.isCompleted) {
          drainCompleter.complete();
        }
      },
    );

    // Amplitude monitoring
    _amplitudeSubscription = _recorder
        .onAmplitudeChanged(amplitudeUpdateInterval)
        .listen((a) {
          _amplitude = a.current;
          if (!_spectrumFrame.hasSpectrum) {
            _notifyMeterListeners();
          }
        });

    return _pcmController!.stream;
  }

  /// Stops streaming, builds WAV from buffered PCM, writes to [path].
  Future<String> stopStreaming(String path) async {
    final pcmDrain = _pcmDrainCompleter;
    await _recorder.stop();

    if (pcmDrain != null) {
      await pcmDrain.future.timeout(
        _pcmDrainTimeout,
        onTimeout:
            () =>
                throw TimeoutException(
                  'Raw PCM stream did not finish after recorder stop',
                ),
      );
    }

    // The raw stream's onDone is the drain barrier. Do not cancel the normal
    // path subscription: all queued PCM is now in both the WAV buffer and the
    // downstream stream, ahead of its done event.
    _pcmSubscription = null;
    _pcmController = null;
    _pcmDrainCompleter = null;
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    _resetMeter();

    final streamError = _pcmStreamError;
    _pcmStreamError = null;
    if (streamError != null) {
      _pcmBuffer.clear();
      throw Exception('Raw PCM stream failed: $streamError');
    }

    final pcmBytes = _pcmBuffer.toBytes();
    _pcmBuffer.clear();

    final wavBytes = _buildWav(pcmBytes, sampleRate: _streamSampleRate);
    await File(path).writeAsBytes(wavBytes);

    return path;
  }

  void _onSpectrumFrame(AudioSpectrumFrame frame) {
    if (_disposed || _spectrumDisabled) return;
    _spectrumFrame = frame;
    _notifyMeterListeners();
  }

  void _disableSpectrum() {
    if (_spectrumDisabled) return;
    final hadSpectrum = _spectrumFrame.hasSpectrum;
    _spectrumDisabled = true;
    try {
      _spectrumAnalyzer?.reset();
    } catch (_) {}
    _spectrumFrame = AudioSpectrumFrame.unavailable;
    if (hadSpectrum) _notifyMeterListeners();
  }

  void _resetMeter() {
    final changed = _amplitude != silenceDb || _spectrumFrame.hasSpectrum;
    _amplitude = silenceDb;
    _spectrumFrame = AudioSpectrumFrame.unavailable;
    _spectrumDisabled = false;
    try {
      _spectrumAnalyzer?.reset();
    } catch (_) {
      _spectrumDisabled = true;
    }
    if (changed) _notifyMeterListeners();
  }

  void _notifyMeterListeners() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _closeControllerIgnoringErrors(
    StreamController<Uint8List> controller,
  ) async {
    try {
      await controller.close();
    } catch (_) {}
  }

  Future<void> _cancelSubscriptionIgnoringErrors(
    StreamSubscription<dynamic> subscription,
  ) async {
    try {
      await subscription.cancel();
    } catch (_) {}
  }

  Future<void> _disposeRecorderIgnoringErrors() async {
    try {
      await _recorder.dispose();
    } catch (_) {}
  }

  /// Constructs a standard 44-byte-header WAV file from raw PCM16 mono data.
  Uint8List _buildWav(Uint8List pcm, {required int sampleRate}) {
    final header = ByteData(44);
    final dataLength = pcm.length;

    // RIFF header
    header.setUint8(0, 0x52);
    header.setUint8(1, 0x49); // "RI"
    header.setUint8(2, 0x46);
    header.setUint8(3, 0x46); // "FF"
    header.setUint32(4, 36 + dataLength, Endian.little);
    header.setUint8(8, 0x57);
    header.setUint8(9, 0x41); // "WA"
    header.setUint8(10, 0x56);
    header.setUint8(11, 0x45); // "VE"

    // fmt chunk
    header.setUint8(12, 0x66);
    header.setUint8(13, 0x6D); // "fm"
    header.setUint8(14, 0x74);
    header.setUint8(15, 0x20); // "t "
    header.setUint32(16, 16, Endian.little); // chunk size
    header.setUint16(20, 1, Endian.little); // PCM format
    header.setUint16(22, 1, Endian.little); // mono
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    header.setUint16(32, 2, Endian.little); // block align
    header.setUint16(34, 16, Endian.little); // bits per sample

    // data chunk
    header.setUint8(36, 0x64);
    header.setUint8(37, 0x61); // "da"
    header.setUint8(38, 0x74);
    header.setUint8(39, 0x61); // "ta"
    header.setUint32(40, dataLength, Endian.little);

    final result =
        BytesBuilder(copy: false)
          ..add(header.buffer.asUint8List())
          ..add(pcm);
    return result.toBytes();
  }

  /// Best-effort cleanup of all recording state. Used on error paths.
  Future<void> forceReset() async {
    try {
      await _recorder.stop();
    } catch (_) {}
    try {
      await _pcmSubscription?.cancel();
    } catch (_) {}
    _pcmSubscription = null;
    final controller = _pcmController;
    if (controller != null && !controller.isClosed) {
      unawaited(_closeControllerIgnoringErrors(controller));
    }
    _pcmController = null;
    final drainCompleter = _pcmDrainCompleter;
    if (drainCompleter != null && !drainCompleter.isCompleted) {
      drainCompleter.complete();
    }
    _pcmDrainCompleter = null;
    _pcmStreamError = null;
    _pcmBuffer.clear();
    try {
      await _amplitudeSubscription?.cancel();
    } catch (_) {}
    _amplitudeSubscription = null;
    _resetMeter();
  }

  @override
  void dispose() {
    _disposed = true;
    _spectrumDisabled = true;
    try {
      _spectrumAnalyzer?.reset();
    } catch (_) {}
    _spectrumAnalyzer = null;
    _spectrumFrame = AudioSpectrumFrame.unavailable;
    final pcmSubscription = _pcmSubscription;
    if (pcmSubscription != null) {
      unawaited(_cancelSubscriptionIgnoringErrors(pcmSubscription));
    }
    final controller = _pcmController;
    if (controller != null && !controller.isClosed) {
      unawaited(_closeControllerIgnoringErrors(controller));
    }
    final drainCompleter = _pcmDrainCompleter;
    if (drainCompleter != null && !drainCompleter.isCompleted) {
      drainCompleter.complete();
    }
    final amplitudeSubscription = _amplitudeSubscription;
    if (amplitudeSubscription != null) {
      unawaited(_cancelSubscriptionIgnoringErrors(amplitudeSubscription));
    }
    unawaited(_disposeRecorderIgnoringErrors());
    super.dispose();
  }
}
