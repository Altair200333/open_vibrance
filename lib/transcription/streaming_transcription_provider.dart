import 'dart:typed_data';

import 'package:open_vibrance/transcription/types.dart';

/// A transcription provider that supports real-time streaming.
/// Separate from [TranscriptionProvider] — batch-only providers are unaffected.
abstract class StreamingTranscriptionProvider {
  /// Provider used for saved-file fallback and provider-specific post-processing.
  TranscriptionProviderKey get providerKey;

  /// Exact PCM sample rate the recorder must produce for this provider.
  int get requiredSampleRate;

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
