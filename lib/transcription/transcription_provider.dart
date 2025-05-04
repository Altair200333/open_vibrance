import 'dart:typed_data';

/// A base interface for voice transcription services.
abstract class TranscriptionProvider {
  /// Transcribes the given audio bytes and returns the transcription as a [String].
  Future<String> transcribe(Uint8List audioBytes);
}
