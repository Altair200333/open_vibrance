import 'dart:async';

import 'package:open_vibrance/transcription/streaming_transcription_provider.dart';

sealed class RecordingSession {
  final String recordingPath;
  RecordingSession({required this.recordingPath});

  /// Idempotent — safe to call multiple times.
  Future<void> dispose();
}

class StreamingSession extends RecordingSession {
  final StreamingTranscriptionProvider provider;
  final Completer<void> transcriptDone;
  String lastTranscript = '';
  Object? transcriptError;
  bool cancelled = false;

  /// Assigned after construction; nullable so dispose() can use ?.cancel().
  StreamSubscription<String>? transcriptSubscription;

  bool _disposed = false;

  StreamingSession({
    required super.recordingPath,
    required this.provider,
    required this.transcriptDone,
  });

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    cancelled = true;
    // Complete BEFORE cancel — cancel does NOT trigger onDone,
    // so any pending await on transcriptDone.future would hang.
    if (!transcriptDone.isCompleted) {
      transcriptDone.complete();
    }
    await transcriptSubscription?.cancel();
  }
}

class BatchSession extends RecordingSession {
  BatchSession({required super.recordingPath});

  @override
  Future<void> dispose() async {}
}
