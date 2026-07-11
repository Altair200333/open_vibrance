import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:open_vibrance/transcription/streaming_transcription_provider.dart';
import 'package:open_vibrance/transcription/transcription_provider.dart';
import 'package:open_vibrance/utils/common.dart';

class _WavInfo {
  final int channels;
  final int sampleRate;
  final int bitsPerSample;
  final Uint8List pcmBytes;

  const _WavInfo({
    required this.channels,
    required this.sampleRate,
    required this.bitsPerSample,
    required this.pcmBytes,
  });
}

const _supportedSampleRates = {8000, 16000, 22050, 24000, 44100, 48000};

const _errorTypes = {
  'error',
  'auth_error',
  'quota_exceeded',
  'rate_limited',
  'session_time_limit_exceeded',
  'chunk_size_exceeded',
  'insufficient_audio_activity',
  'transcriber_error',
  'input_error',
  'queue_overflow',
  'commit_throttled',
  'unaccepted_terms',
  'resource_exhausted',
};

typedef RealtimeWebSocketConnector =
    Future<WebSocket> Function(String url, {Map<String, dynamic>? headers});

Future<void> _cancelIgnoringErrors(
  StreamSubscription<dynamic> subscription,
) async {
  try {
    await subscription.cancel();
  } catch (_) {}
}

Future<void> _closeIgnoringErrors(WebSocket socket) async {
  try {
    await socket.close();
  } catch (_) {}
}

Future<WebSocket> _defaultWebSocketConnector(
  String url, {
  Map<String, dynamic>? headers,
}) => WebSocket.connect(url, headers: headers);

enum _CommitKind { periodic, finalBarrier }

/// Mutable state for a single streaming transcription session.
class _StreamingState {
  _StreamingState({
    required this.sampleRate,
    required this.periodicCommitBytes,
    required this.maxQueuedBytes,
    required this.periodicCommitTimeout,
    required this.finalCommitTimeout,
  });

  final int sampleRate;
  final int periodicCommitBytes;
  final int maxQueuedBytes;
  final Duration periodicCommitTimeout;
  final Duration finalCommitTimeout;
  final StringBuffer committed = StringBuffer();
  String latestPartial = '';
  bool sessionStarted = false;
  bool inputEnded = false;
  bool terminal = false;
  bool isCancelled = false;
  bool cleanedUp = false;
  bool hasAcknowledgedCommit = false;
  bool needsBatchFallback = false;
  _CommitKind? commitInFlight;
  int segmentBytesSent = 0;
  int pendingBytes = 0;
  final ListQueue<Uint8List> pendingChunks = ListQueue<Uint8List>();
  Timer? sessionStartedTimer;
  Timer? commitAckTimer;
  WebSocket? ws;
  StreamSubscription<Uint8List>? pcmSub;
  late final StreamController<String> controller;

  void cleanup() {
    if (cleanedUp) return;
    cleanedUp = true;
    sessionStartedTimer?.cancel();
    commitAckTimer?.cancel();
    final pcmSubscription = pcmSub;
    if (pcmSubscription != null) {
      unawaited(_cancelIgnoringErrors(pcmSubscription));
    }
    final socket = ws;
    if (socket != null) {
      unawaited(_closeIgnoringErrors(socket));
    }
  }
}

class ElevenLabsRealtimeTranscriptionProvider
    implements TranscriptionProvider, StreamingTranscriptionProvider {
  final String _apiKey;
  final RealtimeWebSocketConnector _connectWebSocket;
  final Duration _periodicCommitInterval;
  final Duration _connectTimeout;
  final Duration _sessionStartedTimeout;
  final Duration _periodicCommitTimeout;
  final Duration _finalCommitTimeout;
  final Duration _maxQueuedAudio;

  ElevenLabsRealtimeTranscriptionProvider(
    this._apiKey, {
    RealtimeWebSocketConnector? connectWebSocket,
    Duration periodicCommitInterval = const Duration(seconds: 20),
    Duration connectTimeout = const Duration(seconds: 10),
    Duration sessionStartedTimeout = const Duration(seconds: 5),
    Duration periodicCommitTimeout = const Duration(seconds: 10),
    Duration finalCommitTimeout = const Duration(seconds: 30),
    Duration maxQueuedAudio = const Duration(seconds: 15),
  }) : assert(periodicCommitInterval.inMicroseconds > 0),
       assert(connectTimeout.inMicroseconds > 0),
       assert(sessionStartedTimeout.inMicroseconds > 0),
       assert(periodicCommitTimeout.inMicroseconds > 0),
       assert(finalCommitTimeout.inMicroseconds > 0),
       assert(maxQueuedAudio.inMicroseconds > 0),
       _connectWebSocket = connectWebSocket ?? _defaultWebSocketConnector,
       _periodicCommitInterval = periodicCommitInterval,
       _connectTimeout = connectTimeout,
       _sessionStartedTimeout = sessionStartedTimeout,
       _periodicCommitTimeout = periodicCommitTimeout,
       _finalCommitTimeout = finalCommitTimeout,
       _maxQueuedAudio = maxQueuedAudio;

  _WavInfo _parseWav(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);

    if (bytes.length < 12 ||
        String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
      throw Exception('Invalid WAV file: missing RIFF/WAVE header');
    }

    int? channels;
    int? sampleRate;
    int? bitsPerSample;
    Uint8List? pcmBytes;

    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = data.getUint32(offset + 4, Endian.little);
      final chunkDataStart = offset + 8;

      if (chunkId == 'fmt ' && chunkSize >= 16) {
        final audioFormat = data.getUint16(chunkDataStart, Endian.little);
        if (audioFormat != 1) {
          throw Exception(
            'Unsupported WAV format: only PCM (format=1) is supported, '
            'got format=$audioFormat',
          );
        }
        channels = data.getUint16(chunkDataStart + 2, Endian.little);
        sampleRate = data.getUint32(chunkDataStart + 4, Endian.little);
        bitsPerSample = data.getUint16(chunkDataStart + 14, Endian.little);
      } else if (chunkId == 'data') {
        final end = min(chunkDataStart + chunkSize, bytes.length);
        pcmBytes = Uint8List.sublistView(bytes, chunkDataStart, end);
      }

      // Chunks are word-aligned
      offset = chunkDataStart + chunkSize;
      if (chunkSize.isOdd) offset++;
    }

    if (channels == null || sampleRate == null || bitsPerSample == null) {
      throw Exception('Invalid WAV file: missing fmt chunk');
    }
    if (pcmBytes == null) {
      throw Exception('Invalid WAV file: missing data chunk');
    }
    if (bitsPerSample != 16) {
      throw Exception(
        'Unsupported bit depth: $bitsPerSample-bit. '
        'Realtime API requires 16-bit PCM',
      );
    }
    if (!_supportedSampleRates.contains(sampleRate)) {
      throw Exception(
        'Unsupported sample rate: ${sampleRate}Hz. '
        'Realtime API supports: ${_supportedSampleRates.join(', ')}',
      );
    }

    return _WavInfo(
      channels: channels,
      sampleRate: sampleRate,
      bitsPerSample: bitsPerSample,
      pcmBytes: pcmBytes,
    );
  }

  Uint8List _stereoToMono(Uint8List stereoData) {
    final stereo = ByteData.sublistView(stereoData);
    final monoLength = stereoData.length ~/ 2;
    final mono = Uint8List(monoLength);
    final monoView = ByteData.sublistView(mono);

    // Each stereo frame = 4 bytes (2x int16)
    for (var i = 0; i < stereoData.length - 3; i += 4) {
      final left = stereo.getInt16(i, Endian.little);
      final right = stereo.getInt16(i + 2, Endian.little);
      final mixed = ((left + right) ~/ 2).clamp(-32768, 32767);
      monoView.setInt16(i ~/ 2, mixed, Endian.little);
    }

    return mono;
  }

  Iterable<Uint8List> _chunkPcm(
    Uint8List pcm,
    int bytesPerSecond, {
    int chunkMs = 200,
  }) sync* {
    final chunkSize = bytesPerSecond * chunkMs ~/ 1000;
    for (var offset = 0; offset < pcm.length; offset += chunkSize) {
      yield Uint8List.sublistView(
        pcm,
        offset,
        min(offset + chunkSize, pcm.length),
      );
    }
  }

  String _buildWsUrl(int sampleRate) =>
      'wss://api.elevenlabs.io/v1/speech-to-text/realtime'
      '?model_id=scribe_v2_realtime'
      '&audio_format=pcm_$sampleRate'
      '&commit_strategy=manual';

  void _sendChunk(WebSocket ws, Uint8List chunk, int sampleRate) {
    if (ws.readyState != WebSocket.open) {
      throw StateError('WebSocket is not open');
    }
    ws.add(
      jsonEncode({
        'message_type': 'input_audio_chunk',
        'audio_base_64': base64Encode(chunk),
        'commit': false,
        'sample_rate': sampleRate,
      }),
    );
  }

  void _sendCommit(WebSocket ws, int sampleRate) {
    if (ws.readyState != WebSocket.open) {
      throw StateError('WebSocket is not open');
    }
    ws.add(
      jsonEncode({
        'message_type': 'input_audio_chunk',
        'audio_base_64': '',
        'commit': true,
        'sample_rate': sampleRate,
      }),
    );
  }

  String _errorMessage(String type, Map<String, dynamic> msg) {
    final details = msg['error'] ?? msg['message'] ?? 'No details';
    return switch (type) {
      'auth_error' => 'Invalid ElevenLabs API key',
      'quota_exceeded' => 'ElevenLabs quota exceeded — check your plan',
      'rate_limited' => 'Rate limited — try again later',
      'session_time_limit_exceeded' =>
        'Recording too long for realtime — use Scribe v2 batch',
      'chunk_size_exceeded' => 'Audio chunk too large',
      'insufficient_audio_activity' => 'No speech detected in audio',
      'transcriber_error' => 'Transcription error: $details',
      'input_error' => 'Input error: $details',
      'queue_overflow' => 'Server overloaded — try again later',
      'commit_throttled' => 'ElevenLabs commit was throttled',
      'unaccepted_terms' => 'ElevenLabs Scribe terms are not accepted',
      'resource_exhausted' => 'ElevenLabs resources are exhausted',
      _ => 'ElevenLabs realtime error: $type - $details',
    };
  }

  @override
  Future<String> transcribe(Uint8List audioBytes) async {
    final wavInfo = _parseWav(audioBytes);
    dprint(
      'WAV: ${wavInfo.channels}ch, ${wavInfo.sampleRate}Hz, '
      '${wavInfo.bitsPerSample}-bit, ${wavInfo.pcmBytes.length} PCM bytes',
    );

    final monoData =
        wavInfo.channels == 2
            ? _stereoToMono(wavInfo.pcmBytes)
            : wavInfo.pcmBytes;

    // Reuse the same serialized commit-barrier protocol as live audio. The
    // queue limit is raised to the already-resident file size so a long WAV can
    // be queued while the WebSocket handshake is still in progress.
    final chunks = _chunkPcm(monoData, wavInfo.sampleRate * 2);
    var result = '';
    await for (final transcript in _createTranscriptionStream(
      Stream<Uint8List>.fromIterable(chunks),
      sampleRate: wavInfo.sampleRate,
      maxQueuedBytes: max(monoData.length, 1),
    )) {
      result = transcript;
    }
    return result;
  }

  @override
  Stream<String> transcribeStream(
    Stream<Uint8List> pcmStream, {
    required int sampleRate,
  }) => _createTranscriptionStream(pcmStream, sampleRate: sampleRate);

  Stream<String> _createTranscriptionStream(
    Stream<Uint8List> pcmStream, {
    required int sampleRate,
    int? maxQueuedBytes,
  }) {
    final state = _StreamingState(
      sampleRate: sampleRate,
      periodicCommitBytes: _pcmBytesForDuration(
        sampleRate,
        _periodicCommitInterval,
      ),
      maxQueuedBytes:
          maxQueuedBytes ?? _pcmBytesForDuration(sampleRate, _maxQueuedAudio),
      periodicCommitTimeout: _periodicCommitTimeout,
      finalCommitTimeout: _finalCommitTimeout,
    );

    state.controller = StreamController<String>(
      onCancel: () {
        if (state.terminal) return;
        state.isCancelled = true;
        state.terminal = true;
        state.cleanup();
      },
    );

    unawaited(_runStreamingSession(state, pcmStream));
    return state.controller.stream;
  }

  Future<void> _runStreamingSession(
    _StreamingState state,
    Stream<Uint8List> pcmStream,
  ) async {
    var connectionAbandoned = false;
    WebSocket? connectedSocket;
    try {
      // Subscribe before connecting so short recordings and connection
      // failures cannot leave AudioService's single-subscription stream
      // unobserved. Keep this inside the terminal catch: listen() may throw
      // synchronously for an invalid single-subscription stream.
      state.pcmSub = pcmStream.listen(
        (chunk) => _onPcmChunk(state, chunk),
        onError: (Object error) {
          _fail(state, Exception('Audio stream error: $error'));
        },
        onDone: () {
          if (state.terminal) return;
          state.inputEnded = true;
          _advance(state);
        },
      );

      final connectFuture = _connectWebSocket(
        _buildWsUrl(state.sampleRate),
        headers: {'xi-api-key': _apiKey},
      );
      unawaited(
        connectFuture.then<void>((socket) async {
          connectedSocket = socket;
          if (connectionAbandoned) {
            await _closeIgnoringErrors(socket);
          }
        }, onError: (_) {}),
      );

      final ws = await connectFuture.timeout(_connectTimeout);

      if (state.terminal || state.isCancelled) {
        connectionAbandoned = true;
        await _closeIgnoringErrors(ws);
        return;
      }
      state.ws = ws;
      state.sessionStartedTimer = Timer(_sessionStartedTimeout, () {
        _fail(
          state,
          TimeoutException('ElevenLabs realtime session did not start'),
        );
      });

      ws.listen(
        (raw) {
          if (state.terminal) return;
          try {
            final encoded = raw is String ? raw : utf8.decode(raw as List<int>);
            final msg = jsonDecode(encoded) as Map<String, dynamic>;
            _onWebSocketMessage(state, msg);
          } catch (error) {
            _fail(state, Exception('Invalid realtime STT message: $error'));
          }
        },
        onError: (e) {
          _fail(state, Exception('WebSocket error: $e'));
        },
        onDone: () {
          if (!state.terminal && !state.isCancelled) {
            _fail(
              state,
              Exception(
                'WebSocket closed before final transcript acknowledgment',
              ),
            );
          }
        },
      );
    } catch (e) {
      connectionAbandoned = true;
      final socket = connectedSocket;
      if (socket != null && !identical(socket, state.ws)) {
        unawaited(_closeIgnoringErrors(socket));
      }
      _fail(state, e);
    }
  }

  int _pcmBytesForDuration(int sampleRate, Duration duration) {
    final bytes =
        sampleRate *
        2 *
        duration.inMicroseconds ~/
        Duration.microsecondsPerSecond;
    return bytes > 0 ? bytes : 1;
  }

  void _onPcmChunk(_StreamingState state, Uint8List chunk) {
    if (state.terminal) return;
    if (state.inputEnded) {
      _fail(state, StateError('PCM arrived after the input stream ended'));
      return;
    }

    if (!state.sessionStarted || state.commitInFlight != null) {
      _queuePcmChunk(state, chunk);
      return;
    }

    _sendPcmChunk(state, chunk);
    _advance(state);
  }

  void _queuePcmChunk(_StreamingState state, Uint8List chunk) {
    state.pendingChunks.addLast(chunk);
    state.pendingBytes += chunk.length;
    if (state.pendingBytes > state.maxQueuedBytes) {
      _fail(
        state,
        TimeoutException('Realtime STT is not consuming queued audio'),
      );
    }
  }

  void _sendPcmChunk(_StreamingState state, Uint8List chunk) {
    if (state.terminal) return;
    try {
      _sendChunk(state.ws!, chunk, state.sampleRate);
      state.segmentBytesSent += chunk.length;
    } catch (error) {
      _fail(state, Exception('Failed to send PCM audio: $error'));
    }
  }

  void _flushPendingChunks(_StreamingState state) {
    if (state.terminal ||
        !state.sessionStarted ||
        state.commitInFlight != null) {
      return;
    }

    while (state.pendingChunks.isNotEmpty &&
        !state.terminal &&
        state.commitInFlight == null) {
      final chunk = state.pendingChunks.removeFirst();
      state.pendingBytes -= chunk.length;
      _sendPcmChunk(state, chunk);

      if (!state.terminal &&
          state.segmentBytesSent >= state.periodicCommitBytes) {
        _requestCommit(state, _CommitKind.periodic);
      }
    }

    if (!state.terminal && state.commitInFlight == null) {
      _advance(state);
    }
  }

  void _advance(_StreamingState state) {
    if (state.terminal ||
        !state.sessionStarted ||
        state.commitInFlight != null) {
      return;
    }

    if (state.pendingChunks.isNotEmpty) {
      _flushPendingChunks(state);
      return;
    }

    if (state.inputEnded) {
      if (state.needsBatchFallback) {
        _fail(
          state,
          StateError(
            'Realtime commit correlation was lost; batch fallback required',
          ),
        );
      } else if (state.segmentBytesSent == 0 && state.hasAcknowledgedCommit) {
        _finishSuccess(state);
      } else {
        _requestCommit(state, _CommitKind.finalBarrier);
      }
      return;
    }

    if (state.segmentBytesSent >= state.periodicCommitBytes) {
      _requestCommit(state, _CommitKind.periodic);
    }
  }

  void _requestCommit(_StreamingState state, _CommitKind kind) {
    if (state.terminal || state.commitInFlight != null) return;
    if (!state.sessionStarted) {
      _fail(state, StateError('Commit attempted before session_started'));
      return;
    }
    if (kind == _CommitKind.finalBarrier) {
      if (!state.inputEnded) {
        _fail(state, StateError('Final commit attempted before input ended'));
        return;
      }
      if (state.pendingChunks.isNotEmpty) {
        _fail(state, StateError('Final commit attempted before PCM drain'));
        return;
      }
    }

    state.commitInFlight = kind;
    if (kind == _CommitKind.periodic) {
      // ElevenLabs does not expose a commit correlation id. Once a session has
      // more than one commit, a delayed earlier transcript could otherwise be
      // mistaken for the final ACK. Keep realtime updates running, but require
      // the saved-WAV batch result as the final authority on key release.
      state.needsBatchFallback = true;
    }
    try {
      _sendCommit(state.ws!, state.sampleRate);
    } catch (error) {
      state.commitInFlight = null;
      _fail(state, Exception('Failed to send commit: $error'));
      return;
    }

    state.segmentBytesSent = 0;
    state.commitAckTimer?.cancel();
    final timeout =
        kind == _CommitKind.finalBarrier
            ? state.finalCommitTimeout
            : state.periodicCommitTimeout;
    state.commitAckTimer = Timer(timeout, () {
      _fail(
        state,
        TimeoutException(
          kind == _CommitKind.finalBarrier
              ? 'Final transcript was not acknowledged'
              : 'Periodic transcript commit was not acknowledged',
        ),
      );
    });
  }

  void _onWebSocketMessage(_StreamingState state, Map<String, dynamic> msg) {
    final type = msg['message_type'] as String?;
    switch (type) {
      case 'session_started':
        if (state.sessionStarted) {
          _fail(state, StateError('Duplicate session_started event'));
          return;
        }
        dprint('Realtime STT session started: ${msg['session_id']}');
        state.sessionStarted = true;
        state.sessionStartedTimer?.cancel();
        _flushPendingChunks(state);

      case 'partial_transcript':
        state.latestPartial = msg['text'] as String? ?? '';
        final aggregated =
            state.committed.isEmpty
                ? state.latestPartial
                : '${state.committed.toString().trim()} ${state.latestPartial}';
        if (aggregated.trim().isNotEmpty && !state.controller.isClosed) {
          state.controller.add(aggregated.trim());
        }

      case 'committed_transcript':
        _onCommittedTranscript(state, msg['text'] as String? ?? '');

      default:
        if (type != null && _errorTypes.contains(type)) {
          _fail(state, Exception(_errorMessage(type, msg)));
        } else if (type != null &&
            type != 'committed_transcript_with_timestamps') {
          dprint('Unknown realtime STT message: $type');
        }
    }
  }

  void _onCommittedTranscript(_StreamingState state, String text) {
    if (state.terminal) return;

    if (text.isNotEmpty) {
      if (state.committed.isNotEmpty) state.committed.write(' ');
      state.committed.write(text);
    }
    state.latestPartial = '';
    if (!state.controller.isClosed) {
      // Emit even an empty committed value so callers cannot retain a stale
      // partial as the final transcript.
      state.controller.add(state.committed.toString().trim());
    }

    final kind = state.commitInFlight;
    if (kind == null) {
      // The documented ~36s server auto-commit should be unreachable because
      // we commit every 20s. Keep recording, but require the WAV batch fallback
      // rather than guessing which later event acknowledges the final barrier.
      state.needsBatchFallback = true;
      state.segmentBytesSent = 0;
      dprint('Uncorrelated realtime committed transcript; fallback required');
      _advance(state);
      return;
    }

    state.commitAckTimer?.cancel();
    state.commitInFlight = null;
    state.hasAcknowledgedCommit = true;

    if (kind == _CommitKind.finalBarrier) {
      if (!state.inputEnded ||
          state.pendingChunks.isNotEmpty ||
          state.segmentBytesSent != 0) {
        _fail(
          state,
          StateError('Final commit acknowledged with unsent PCM audio'),
        );
      } else if (state.needsBatchFallback) {
        _fail(
          state,
          StateError(
            'Realtime final transcript is ambiguous; batch fallback required',
          ),
        );
      } else {
        _finishSuccess(state);
      }
      return;
    }

    _flushPendingChunks(state);
  }

  void _finishSuccess(_StreamingState state) {
    if (state.terminal) return;
    state.terminal = true;
    state.sessionStartedTimer?.cancel();
    state.commitAckTimer?.cancel();
    if (!state.controller.isClosed) {
      unawaited(state.controller.close());
    }
    state.cleanup();
  }

  void _fail(_StreamingState state, Object error) {
    if (state.terminal || state.isCancelled) return;
    state.terminal = true;
    state.sessionStartedTimer?.cancel();
    state.commitAckTimer?.cancel();
    if (!state.controller.isClosed) {
      state.controller.addError(error);
      unawaited(state.controller.close());
    }
    state.cleanup();
  }
}
