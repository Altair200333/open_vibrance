import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

/// Service to handle audio recording logic.
class AudioService extends ChangeNotifier {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  double _amplitude = 0.0;

  // Streaming fields
  final BytesBuilder _pcmBuffer = BytesBuilder(copy: false);
  StreamSubscription<Uint8List>? _pcmSubscription;
  StreamController<Uint8List>? _pcmController;
  int _streamSampleRate = 16000;

  /// Current amplitude in dB.
  double get amplitude => _amplitude;

  /// Checks if microphone permission is granted.
  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Starts recording audio and listens for amplitude changes.
  /// If [path] is provided, records to that path; otherwise uses a temp file.
  Future<void> start({String? path}) async {
    final granted = await _recorder.hasPermission();
    if (!granted) {
      throw Exception('Microphone permission denied');
    }

    final recordingPath = path ?? '${Directory.systemTemp.path}/last_recording.wav';

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.wav),
      path: recordingPath,
    );
    _amplitudeSubscription = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 100))
        .listen((amplitude) {
          _amplitude = amplitude.current;
          notifyListeners();
        });
  }

  /// Stops recording and returns the path to the recorded file.
  Future<String?> stop() async {
    final path = await _recorder.stop();
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    notifyListeners();
    return path;
  }

  /// Starts streaming recording. Returns a Stream<Uint8List> of raw PCM chunks.
  /// Chunks are also accumulated internally for WAV file construction on stop.
  Future<Stream<Uint8List>> startStreaming({int sampleRate = 16000}) async {
    final granted = await _recorder.hasPermission();
    if (!granted) throw Exception('Microphone permission denied');

    _streamSampleRate = sampleRate;
    _pcmBuffer.clear();

    final rawStream = await _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
      ),
    );

    // Tee: buffer chunks for WAV construction + forward to caller
    _pcmController = StreamController<Uint8List>();
    _pcmSubscription = rawStream.listen(
      (chunk) {
        _pcmBuffer.add(chunk);
        _pcmController?.add(chunk);
      },
      onError: (e) => _pcmController?.addError(e),
      onDone: () => _pcmController?.close(),
    );

    // Amplitude monitoring
    _amplitudeSubscription = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 100))
        .listen((a) {
          _amplitude = a.current;
          notifyListeners();
        });

    return _pcmController!.stream;
  }

  /// Stops streaming, builds WAV from buffered PCM, writes to [path].
  Future<String> stopStreaming(String path) async {
    await _recorder.stop();
    await _pcmSubscription?.cancel();
    _pcmSubscription = null;
    // Explicitly close — cancelling subscription does NOT trigger onDone
    await _pcmController?.close();
    _pcmController = null;
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;

    final pcmBytes = _pcmBuffer.toBytes();
    _pcmBuffer.clear();

    final wavBytes = _buildWav(pcmBytes, sampleRate: _streamSampleRate);
    await File(path).writeAsBytes(wavBytes);

    notifyListeners();
    return path;
  }

  /// Constructs a standard 44-byte-header WAV file from raw PCM16 mono data.
  Uint8List _buildWav(Uint8List pcm, {required int sampleRate}) {
    final header = ByteData(44);
    final dataLength = pcm.length;

    // RIFF header
    header.setUint8(0, 0x52); header.setUint8(1, 0x49); // "RI"
    header.setUint8(2, 0x46); header.setUint8(3, 0x46); // "FF"
    header.setUint32(4, 36 + dataLength, Endian.little);
    header.setUint8(8, 0x57); header.setUint8(9, 0x41); // "WA"
    header.setUint8(10, 0x56); header.setUint8(11, 0x45); // "VE"

    // fmt chunk
    header.setUint8(12, 0x66); header.setUint8(13, 0x6D); // "fm"
    header.setUint8(14, 0x74); header.setUint8(15, 0x20); // "t "
    header.setUint32(16, 16, Endian.little);   // chunk size
    header.setUint16(20, 1, Endian.little);    // PCM format
    header.setUint16(22, 1, Endian.little);    // mono
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    header.setUint16(32, 2, Endian.little);    // block align
    header.setUint16(34, 16, Endian.little);   // bits per sample

    // data chunk
    header.setUint8(36, 0x64); header.setUint8(37, 0x61); // "da"
    header.setUint8(38, 0x74); header.setUint8(39, 0x61); // "ta"
    header.setUint32(40, dataLength, Endian.little);

    final result = BytesBuilder(copy: false)
      ..add(header.buffer.asUint8List())
      ..add(pcm);
    return result.toBytes();
  }

  @override
  void dispose() {
    _pcmSubscription?.cancel();
    _pcmController?.close();
    _amplitudeSubscription?.cancel();
    _recorder.dispose();
    super.dispose();
  }
}
