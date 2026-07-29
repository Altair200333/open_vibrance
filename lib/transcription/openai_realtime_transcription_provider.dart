import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:open_vibrance/transcription/streaming_transcription_provider.dart';
import 'package:open_vibrance/transcription/types.dart';

typedef OpenAIRealtimeWebSocketConnector =
    Future<WebSocket> Function(String url, {Map<String, dynamic>? headers});

Future<WebSocket> _connectOpenAIWebSocket(
  String url, {
  Map<String, dynamic>? headers,
}) => WebSocket.connect(url, headers: headers);

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

final class _RealtimeState {
  _RealtimeState({
    required this.maxQueuedBytes,
    required this.sessionUpdatedTimeout,
    required this.commitAckTimeout,
    required this.finalTranscriptTimeout,
  });

  final int maxQueuedBytes;
  final Duration sessionUpdatedTimeout;
  final Duration commitAckTimeout;
  final Duration finalTranscriptTimeout;
  final ListQueue<Uint8List> pendingChunks = ListQueue<Uint8List>();
  final Map<String, StringBuffer> earlyDeltas = <String, StringBuffer>{};
  final Map<String, String> earlyCompleted = <String, String>{};

  int pendingBytes = 0;
  int bytesSent = 0;
  bool sessionUpdated = false;
  bool inputEnded = false;
  bool commitSent = false;
  bool terminal = false;
  bool cancelled = false;
  bool cleanedUp = false;
  String? committedItemId;
  String partialTranscript = '';
  Timer? sessionUpdatedTimer;
  Timer? commitAckTimer;
  Timer? finalTranscriptTimer;
  WebSocket? socket;
  StreamSubscription<dynamic>? socketSubscription;
  StreamSubscription<Uint8List>? pcmSubscription;
  late final StreamController<String> controller;

  void cleanup() {
    if (cleanedUp) return;
    cleanedUp = true;
    sessionUpdatedTimer?.cancel();
    commitAckTimer?.cancel();
    finalTranscriptTimer?.cancel();

    final pcm = pcmSubscription;
    if (pcm != null) {
      unawaited(_cancelIgnoringErrors(pcm));
    }
    final websocketEvents = socketSubscription;
    if (websocketEvents != null) {
      unawaited(_cancelIgnoringErrors(websocketEvents));
    }
    final websocket = socket;
    if (websocket != null) {
      unawaited(_closeIgnoringErrors(websocket));
    }
  }
}

/// Streams PCM audio through an OpenAI transcription-only Realtime session.
///
/// The provider deliberately disables server VAD. A recording is successful
/// only after every local PCM chunk has been appended, the server acknowledges
/// the manual commit, and the matching transcription item completes.
final class OpenAIRealtimeTranscriptionProvider
    implements StreamingTranscriptionProvider {
  static const int inputSampleRate = 24000;
  static const int _maxAppendBytes = 15 * 1024 * 1024;

  /// Opens a dedicated transcription session. The ASR model is selected
  /// independently in `session.update`.
  static const String webSocketUrl =
      'wss://api.openai.com/v1/realtime?intent=transcription';

  OpenAIRealtimeTranscriptionProvider({
    required String apiKey,
    String? prompt,
    OpenAIRealtimeWebSocketConnector? connectWebSocket,
    Duration connectTimeout = const Duration(seconds: 10),
    Duration sessionUpdatedTimeout = const Duration(seconds: 5),
    Duration commitAckTimeout = const Duration(seconds: 10),
    Duration finalTranscriptTimeout = const Duration(seconds: 30),
    Duration maxQueuedAudio = const Duration(seconds: 15),
  }) : assert(connectTimeout.inMicroseconds > 0),
       assert(sessionUpdatedTimeout.inMicroseconds > 0),
       assert(commitAckTimeout.inMicroseconds > 0),
       assert(finalTranscriptTimeout.inMicroseconds > 0),
       assert(maxQueuedAudio.inMicroseconds > 0),
       _apiKey = apiKey.trim(),
       _prompt = prompt,
       _connectWebSocket = connectWebSocket ?? _connectOpenAIWebSocket,
       _connectTimeout = connectTimeout,
       _sessionUpdatedTimeout = sessionUpdatedTimeout,
       _commitAckTimeout = commitAckTimeout,
       _finalTranscriptTimeout = finalTranscriptTimeout,
       _maxQueuedAudio = maxQueuedAudio;

  final String _apiKey;
  final String? _prompt;
  final OpenAIRealtimeWebSocketConnector _connectWebSocket;
  final Duration _connectTimeout;
  final Duration _sessionUpdatedTimeout;
  final Duration _commitAckTimeout;
  final Duration _finalTranscriptTimeout;
  final Duration _maxQueuedAudio;

  @override
  TranscriptionProviderKey get providerKey => TranscriptionProviderKey.openai;

  @override
  int get requiredSampleRate => inputSampleRate;

  @override
  Stream<String> transcribeStream(
    Stream<Uint8List> pcmStream, {
    required int sampleRate,
  }) {
    if (sampleRate != inputSampleRate) {
      return Stream<String>.error(
        ArgumentError.value(
          sampleRate,
          'sampleRate',
          'GPT Live Transcribe requires 24000 Hz PCM',
        ),
      );
    }

    final maxQueuedBytes = _pcmBytesForDuration(sampleRate, _maxQueuedAudio);
    final state = _RealtimeState(
      maxQueuedBytes: maxQueuedBytes,
      sessionUpdatedTimeout: _sessionUpdatedTimeout,
      commitAckTimeout: _commitAckTimeout,
      finalTranscriptTimeout: _finalTranscriptTimeout,
    );
    state.controller = StreamController<String>(
      onCancel: () {
        if (state.terminal) return;
        state.cancelled = true;
        state.terminal = true;
        state.cleanup();
      },
    );

    unawaited(_start(state, pcmStream));
    return state.controller.stream;
  }

  int _pcmBytesForDuration(int sampleRate, Duration duration) {
    final bytes =
        sampleRate *
        2 *
        duration.inMicroseconds ~/
        Duration.microsecondsPerSecond;
    return bytes > 0 ? bytes : 1;
  }

  Future<void> _start(_RealtimeState state, Stream<Uint8List> pcmStream) async {
    try {
      if (_apiKey.isEmpty) {
        throw StateError('OpenAI API key not found');
      }

      state.pcmSubscription = pcmStream.listen(
        (chunk) => _onPcmChunk(state, chunk),
        onError: (Object error, StackTrace stackTrace) {
          _fail(state, error, stackTrace);
        },
        onDone: () {
          if (state.terminal) return;
          state.inputEnded = true;
          _advance(state);
        },
      );

      final connectFuture = _connectWebSocket(
        webSocketUrl,
        headers: <String, dynamic>{'Authorization': 'Bearer $_apiKey'},
      );
      unawaited(
        connectFuture.then<void>((socket) async {
          if (state.terminal && !identical(state.socket, socket)) {
            await _closeIgnoringErrors(socket);
          }
        }, onError: (_) {}),
      );

      final socket = await connectFuture.timeout(_connectTimeout);
      if (state.terminal) {
        await _closeIgnoringErrors(socket);
        return;
      }

      state.socket = socket;
      state.socketSubscription = socket.listen(
        (message) => _onServerMessage(state, message),
        onError: (Object error, StackTrace stackTrace) {
          _fail(
            state,
            Exception('OpenAI Realtime WebSocket error: $error'),
            stackTrace,
          );
        },
        onDone: () {
          if (!state.terminal) {
            _fail(
              state,
              StateError(
                'OpenAI Realtime connection closed before final transcript',
              ),
            );
          }
        },
      );

      state.sessionUpdatedTimer = Timer(state.sessionUpdatedTimeout, () {
        _fail(
          state,
          TimeoutException(
            'OpenAI Realtime session.update was not acknowledged',
            state.sessionUpdatedTimeout,
          ),
        );
      });
      _sendSessionUpdate(state);
    } catch (error, stackTrace) {
      _fail(state, error, stackTrace);
    }
  }

  void _sendSessionUpdate(_RealtimeState state) {
    final transcription = <String, dynamic>{
      'model': 'gpt-live-transcribe',
      'delay': 'xhigh',
    };
    final prompt = _prompt;
    if (prompt != null && prompt.trim().isNotEmpty) {
      transcription['prompt'] = prompt;
    }

    _send(state, <String, dynamic>{
      'type': 'session.update',
      'session': <String, dynamic>{
        'type': 'transcription',
        'audio': <String, dynamic>{
          'input': <String, dynamic>{
            'format': <String, dynamic>{
              'type': 'audio/pcm',
              'rate': inputSampleRate,
            },
            'transcription': transcription,
            'turn_detection': null,
          },
        },
      },
    });
  }

  void _onPcmChunk(_RealtimeState state, Uint8List chunk) {
    if (state.terminal || chunk.isEmpty) return;
    if (state.inputEnded) {
      _fail(state, StateError('PCM arrived after the input stream ended'));
      return;
    }
    if (chunk.length > _maxAppendBytes) {
      _fail(
        state,
        StateError(
          'OpenAI Realtime audio chunk exceeds the 15 MiB event limit',
        ),
      );
      return;
    }

    if (!state.sessionUpdated) {
      if (state.pendingBytes + chunk.length > state.maxQueuedBytes) {
        _fail(
          state,
          StateError(
            'OpenAI Realtime audio queue overflow before session.updated',
          ),
        );
        return;
      }
      final queued = Uint8List.fromList(chunk);
      state.pendingChunks.add(queued);
      state.pendingBytes += queued.length;
      return;
    }

    _sendPcmChunk(state, chunk);
  }

  void _sendPcmChunk(_RealtimeState state, Uint8List chunk) {
    try {
      _send(state, <String, dynamic>{
        'type': 'input_audio_buffer.append',
        'audio': base64Encode(chunk),
      });
      state.bytesSent += chunk.length;
    } catch (error, stackTrace) {
      _fail(
        state,
        Exception('Failed to send PCM audio to OpenAI: $error'),
        stackTrace,
      );
    }
  }

  void _advance(_RealtimeState state) {
    if (state.terminal || !state.sessionUpdated) return;

    while (state.pendingChunks.isNotEmpty && !state.terminal) {
      final chunk = state.pendingChunks.removeFirst();
      state.pendingBytes -= chunk.length;
      _sendPcmChunk(state, chunk);
    }

    if (!state.inputEnded || state.terminal || state.commitSent) return;
    if (state.bytesSent == 0) {
      _finishSuccess(state, '');
      return;
    }

    try {
      state.commitSent = true;
      state.commitAckTimer = Timer(state.commitAckTimeout, () {
        _fail(
          state,
          TimeoutException(
            'OpenAI Realtime audio commit was not acknowledged',
            state.commitAckTimeout,
          ),
        );
      });
      _send(state, <String, dynamic>{'type': 'input_audio_buffer.commit'});
    } catch (error, stackTrace) {
      _fail(
        state,
        Exception('Failed to commit OpenAI audio buffer: $error'),
        stackTrace,
      );
    }
  }

  void _send(_RealtimeState state, Map<String, dynamic> event) {
    final socket = state.socket;
    if (socket == null || socket.readyState != WebSocket.open) {
      throw StateError('OpenAI Realtime WebSocket is not open');
    }
    socket.add(jsonEncode(event));
  }

  void _onServerMessage(_RealtimeState state, dynamic rawMessage) {
    if (state.terminal) return;

    try {
      final String encoded;
      if (rawMessage is String) {
        encoded = rawMessage;
      } else if (rawMessage is List<int>) {
        encoded = utf8.decode(rawMessage);
      } else {
        throw FormatException(
          'Unexpected OpenAI Realtime message type: '
          '${rawMessage.runtimeType}',
        );
      }

      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException(
          'OpenAI Realtime event must be a JSON object',
        );
      }
      final type = decoded['type'];
      if (type is! String || type.isEmpty) {
        throw const FormatException(
          'OpenAI Realtime event is missing a string type',
        );
      }

      switch (type) {
        case 'session.created':
          break;
        case 'session.updated':
          _onSessionUpdated(state);
          break;
        case 'input_audio_buffer.committed':
          _onCommitted(state, decoded);
          break;
        case 'conversation.item.input_audio_transcription.delta':
          _onDelta(state, decoded);
          break;
        case 'conversation.item.input_audio_transcription.completed':
          _onCompleted(state, decoded);
          break;
        case 'conversation.item.input_audio_transcription.failed':
          _onTranscriptionFailed(state, decoded);
          break;
        case 'error':
          _fail(state, Exception(_serverErrorMessage(decoded)));
          break;
        default:
          break;
      }
    } catch (error, stackTrace) {
      _fail(state, error, stackTrace);
    }
  }

  void _onSessionUpdated(_RealtimeState state) {
    if (state.sessionUpdated) return;
    state.sessionUpdated = true;
    state.sessionUpdatedTimer?.cancel();
    _advance(state);
  }

  void _onCommitted(_RealtimeState state, Map<String, dynamic> event) {
    if (!state.commitSent) {
      _fail(
        state,
        StateError('OpenAI acknowledged an audio commit we did not send'),
      );
      return;
    }
    if (state.committedItemId != null) {
      _fail(state, StateError('OpenAI sent more than one commit ACK'));
      return;
    }

    final itemId = _requiredString(event, 'item_id');
    state.commitAckTimer?.cancel();
    state.committedItemId = itemId;

    final bufferedDeltas = state.earlyDeltas.remove(itemId);
    if (bufferedDeltas != null && bufferedDeltas.isNotEmpty) {
      state.partialTranscript = bufferedDeltas.toString();
      state.controller.add(state.partialTranscript);
    }

    final completed = state.earlyCompleted.remove(itemId);
    if (completed != null) {
      _finishSuccess(state, completed);
      return;
    }

    state.finalTranscriptTimer = Timer(state.finalTranscriptTimeout, () {
      _fail(
        state,
        TimeoutException(
          'OpenAI Realtime final transcript was not received',
          state.finalTranscriptTimeout,
        ),
      );
    });
  }

  void _onDelta(_RealtimeState state, Map<String, dynamic> event) {
    final itemId = _requiredString(event, 'item_id');
    final delta = _requiredString(event, 'delta', allowEmpty: true);
    final committedItemId = state.committedItemId;

    if (committedItemId == null) {
      state.earlyDeltas.putIfAbsent(itemId, StringBuffer.new).write(delta);
      return;
    }
    if (itemId != committedItemId) return;

    state.partialTranscript += delta;
    state.controller.add(state.partialTranscript);
  }

  void _onCompleted(_RealtimeState state, Map<String, dynamic> event) {
    final itemId = _requiredString(event, 'item_id');
    final transcript = _requiredString(event, 'transcript', allowEmpty: true);
    final committedItemId = state.committedItemId;

    if (committedItemId == null) {
      state.earlyCompleted[itemId] = transcript;
      return;
    }
    if (itemId != committedItemId) return;
    _finishSuccess(state, transcript);
  }

  void _onTranscriptionFailed(
    _RealtimeState state,
    Map<String, dynamic> event,
  ) {
    final itemId = _requiredString(event, 'item_id');
    final committedItemId = state.committedItemId;
    if (committedItemId != null && itemId != committedItemId) return;

    _fail(
      state,
      Exception('OpenAI transcription failed: ${_nestedErrorMessage(event)}'),
    );
  }

  String _requiredString(
    Map<String, dynamic> event,
    String key, {
    bool allowEmpty = false,
  }) {
    final value = event[key];
    if (value is! String || (!allowEmpty && value.isEmpty)) {
      throw FormatException('OpenAI Realtime event has invalid "$key": $event');
    }
    return value;
  }

  String _serverErrorMessage(Map<String, dynamic> event) =>
      'OpenAI Realtime error: ${_nestedErrorMessage(event)}';

  String _nestedErrorMessage(Map<String, dynamic> event) {
    final error = event['error'];
    if (error is Map<String, dynamic>) {
      final message = error['message'];
      final code = error['code'];
      if (message is String && code is String && code.isNotEmpty) {
        return '$code: $message';
      }
      if (message is String && message.isNotEmpty) return message;
      return error.toString();
    }
    return (event['message'] ?? error ?? 'No details').toString();
  }

  void _finishSuccess(_RealtimeState state, String transcript) {
    if (state.terminal) return;
    state.terminal = true;
    state.controller.add(transcript);
    unawaited(state.controller.close());
    state.cleanup();
  }

  void _fail(_RealtimeState state, Object error, [StackTrace? stackTrace]) {
    if (state.terminal) return;
    state.terminal = true;
    if (!state.cancelled) {
      state.controller.addError(error, stackTrace);
      unawaited(state.controller.close());
    }
    state.cleanup();
  }
}
