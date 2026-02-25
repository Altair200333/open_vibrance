import 'dart:typed_data';

/// A transcription provider that supports real-time streaming.
/// Separate from [TranscriptionProvider] — batch-only providers are unaffected.
abstract class StreamingTranscriptionProvider {
  /// Streams transcription results as audio chunks arrive via [pcmStream].
  ///
  /// Each emission is the full aggregated text so far: all committed segments
  /// joined, plus the latest partial transcript appended.
  ///
  /// When [pcmStream] ends (recording stopped), sends a final commit to the
  /// server, waits for the last committed transcript, then closes the stream.
  Stream<String> transcribeStream(
    Stream<Uint8List> pcmStream, {
    required int sampleRate,
  });
}
