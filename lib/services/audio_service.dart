import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

/// Service to handle audio recording logic.
class AudioService extends ChangeNotifier {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  double _amplitude = 0.0;

  /// Current amplitude in dB.
  double get amplitude => _amplitude;

  /// Checks if microphone permission is granted.
  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Starts recording audio to a temporary file and listens for amplitude changes.
  Future<void> start() async {
    final granted = await _recorder.hasPermission();
    if (!granted) {
      throw Exception('Microphone permission denied');
    }

    final tempDir = Directory.systemTemp;
    final recordingPath = '${tempDir.path}/last_recording.wav';

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

  @override
  void dispose() {
    _amplitudeSubscription?.cancel();
    _recorder.dispose();
    super.dispose();
  }
}
