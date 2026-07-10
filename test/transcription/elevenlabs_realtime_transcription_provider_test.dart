import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_vibrance/transcription/elevenlabs_realtime_transcription_provider.dart';

void main() {
  group('ElevenLabsRealtimeTranscriptionProvider', () {
    test('serializes periodic commits and uses batch final authority', () {
      fakeAsync((async) {
        final socket = _FakeWebSocket();
        final provider = _provider(
          socket,
          periodicCommitInterval: const Duration(milliseconds: 1),
        );
        final pcm = StreamController<Uint8List>(sync: true);
        final result = _listen(provider, pcm.stream);

        async.flushMicrotasks();
        socket.serverSend(_sessionStarted());

        pcm.add(Uint8List(32));
        expect(socket.sent, hasLength(2));
        expect(socket.sent[0]['commit'], isFalse);
        expect(socket.sent[1]['commit'], isTrue);

        // PCM captured behind an outstanding commit stays local until its ACK.
        pcm.add(Uint8List(8));
        expect(socket.sent, hasLength(2));

        socket.serverSend(_committed('first'));
        async.flushMicrotasks();
        expect(result.done, isFalse);
        expect(socket.sent, hasLength(3));
        expect(socket.sent[2]['commit'], isFalse);

        unawaited(pcm.close());
        async.flushMicrotasks();
        // A multi-commit protocol has no response correlation id. Realtime
        // stays useful during recording, but key-up deliberately returns an
        // error so DotWindow uses the complete saved WAV through Scribe v2.
        expect(socket.sent, hasLength(3));
        expect(result.errors.single, isA<StateError>());
        expect(result.done, isTrue);
        expect(result.values, ['first']);
        expect(socket.clientCloseCalls, 1);
      });
    });

    test('an uncorrelated auto-commit never closes an active PCM stream', () {
      fakeAsync((async) {
        final socket = _FakeWebSocket();
        final provider = _provider(socket);
        final pcm = StreamController<Uint8List>(sync: true);
        final result = _listen(provider, pcm.stream);

        async.flushMicrotasks();
        socket.serverSend(_sessionStarted());
        pcm.add(Uint8List(4));

        socket.serverSend(_committed('automatic segment'));
        async.flushMicrotasks();

        expect(result.done, isFalse);
        expect(result.errors, isEmpty);
        expect(socket.clientCloseCalls, 0);

        pcm.add(Uint8List(4));
        expect(
          socket.sent.where((message) => message['commit'] == false),
          hasLength(2),
        );

        // Correlation is now uncertain, so ending the input requests the batch
        // fallback through a typed stream error instead of pasting a partial.
        unawaited(pcm.close());
        async.flushMicrotasks();
        expect(result.done, isTrue);
        expect(result.errors.single, isA<StateError>());
      });
    });

    test(
      'flushes PCM before commit when input ends before session_started',
      () {
        fakeAsync((async) {
          final socket = _FakeWebSocket();
          final provider = _provider(socket);
          final pcm = StreamController<Uint8List>(sync: true);
          final result = _listen(provider, pcm.stream);

          async.flushMicrotasks();
          pcm.add(Uint8List.fromList([1, 2, 3, 4]));
          unawaited(pcm.close());
          async.flushMicrotasks();
          expect(socket.sent, isEmpty);

          socket.serverSend(_sessionStarted());
          async.flushMicrotasks();

          expect(socket.sent, hasLength(2));
          expect(socket.sent[0]['commit'], isFalse);
          expect(socket.sent[0]['audio_base_64'], base64Encode([1, 2, 3, 4]));
          expect(socket.sent[1]['commit'], isTrue);

          socket.serverSend(_committed('complete'));
          async.flushMicrotasks();
          expect(result.errors, isEmpty);
          expect(result.done, isTrue);
          expect(result.values.last, 'complete');
        });
      },
    );

    test('final commit timeout is an error, never a clean partial success', () {
      fakeAsync((async) {
        final socket = _FakeWebSocket();
        final provider = _provider(
          socket,
          finalCommitTimeout: const Duration(seconds: 5),
        );
        final pcm = StreamController<Uint8List>(sync: true);
        final result = _listen(provider, pcm.stream);

        async.flushMicrotasks();
        socket.serverSend(_sessionStarted());
        pcm.add(Uint8List(4));
        unawaited(pcm.close());
        async.flushMicrotasks();

        expect(socket.sent.last['commit'], isTrue);
        async.elapse(const Duration(milliseconds: 4999));
        expect(result.done, isFalse);

        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();
        expect(result.done, isTrue);
        expect(result.errors.single, isA<TimeoutException>());
      });
    });

    test('premature WebSocket close is surfaced as an error', () {
      fakeAsync((async) {
        final socket = _FakeWebSocket();
        final provider = _provider(socket);
        final pcm = StreamController<Uint8List>(sync: true);
        final result = _listen(provider, pcm.stream);

        async.flushMicrotasks();
        socket.serverSend(_sessionStarted());
        pcm.add(Uint8List(4));
        final sentBeforeClose = socket.sent.length;

        socket.serverClose();
        async.flushMicrotasks();

        expect(result.done, isTrue);
        expect(result.errors.single, isA<Exception>());
        pcm.add(Uint8List(4));
        expect(socket.sent, hasLength(sentBeforeClose));
      });
    });

    test('an empty committed result clears the last provisional partial', () {
      fakeAsync((async) {
        final socket = _FakeWebSocket();
        final provider = _provider(socket);
        final pcm = StreamController<Uint8List>(sync: true);
        final result = _listen(provider, pcm.stream);

        async.flushMicrotasks();
        socket.serverSend(_sessionStarted());
        pcm.add(Uint8List(4));
        socket.serverSend(_partial('provisional'));
        async.flushMicrotasks();
        expect(result.values.last, 'provisional');

        unawaited(pcm.close());
        async.flushMicrotasks();
        socket.serverSend(_committed(''));
        async.flushMicrotasks();

        expect(result.errors, isEmpty);
        expect(result.done, isTrue);
        expect(result.values.last, isEmpty);
      });
    });

    test('periodic commit timeout is a terminal error', () {
      fakeAsync((async) {
        final socket = _FakeWebSocket();
        final provider = _provider(
          socket,
          periodicCommitInterval: const Duration(milliseconds: 1),
          periodicCommitTimeout: const Duration(seconds: 5),
        );
        final pcm = StreamController<Uint8List>(sync: true);
        final result = _listen(provider, pcm.stream);

        async.flushMicrotasks();
        socket.serverSend(_sessionStarted());
        pcm.add(Uint8List(32));
        expect(socket.sent.last['commit'], isTrue);

        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        expect(result.done, isTrue);
        expect(result.errors.single, isA<TimeoutException>());
      });
    });

    test(
      'a delayed prior ACK cannot turn a multi-commit session into success',
      () {
        fakeAsync((async) {
          final socket = _FakeWebSocket();
          final provider = _provider(
            socket,
            periodicCommitInterval: const Duration(milliseconds: 1),
          );
          final pcm = StreamController<Uint8List>(sync: true);
          final result = _listen(provider, pcm.stream);

          async.flushMicrotasks();
          socket.serverSend(_sessionStarted());
          pcm.add(Uint8List(32));
          pcm.add(Uint8List(32));
          unawaited(pcm.close());

          socket.serverSend(_committed('first segment'));
          async.flushMicrotasks();
          expect(
            socket.sent.where((message) => message['commit'] == true),
            hasLength(2),
          );

          // Whether this is ACK #2 or a delayed duplicate of ACK #1 is
          // unknowable without a protocol id. It may update the live preview,
          // but must never authorize final success.
          socket.serverSend(_committed('ambiguous segment'));
          async.flushMicrotasks();

          expect(result.done, isTrue);
          expect(result.errors.single, isA<StateError>());
        });
      },
    );

    test('session_started timeout is a terminal error', () {
      fakeAsync((async) {
        final socket = _FakeWebSocket();
        final provider = _provider(
          socket,
          sessionStartedTimeout: const Duration(seconds: 5),
        );
        final pcm = StreamController<Uint8List>(sync: true);
        final result = _listen(provider, pcm.stream);

        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();

        expect(result.done, isTrue);
        expect(result.errors.single, isA<TimeoutException>());
      });
    });

    test('queue overflow is an error while the server is unavailable', () {
      fakeAsync((async) {
        final socket = _FakeWebSocket();
        final provider = _provider(
          socket,
          maxQueuedAudio: const Duration(milliseconds: 1),
        );
        final pcm = StreamController<Uint8List>(sync: true);
        final result = _listen(provider, pcm.stream);

        async.flushMicrotasks();
        pcm.add(Uint8List(33));
        async.flushMicrotasks();

        expect(result.done, isTrue);
        expect(result.errors.single, isA<TimeoutException>());
      });
    });

    test(
      'server error during finalization cannot return a partial success',
      () {
        fakeAsync((async) {
          final socket = _FakeWebSocket();
          final provider = _provider(socket);
          final pcm = StreamController<Uint8List>(sync: true);
          final result = _listen(provider, pcm.stream);

          async.flushMicrotasks();
          socket.serverSend(_sessionStarted());
          pcm.add(Uint8List(4));
          unawaited(pcm.close());
          async.flushMicrotasks();
          socket.serverSend({
            'message_type': 'transcriber_error',
            'error': 'test failure',
          });
          async.flushMicrotasks();

          expect(result.done, isTrue);
          expect(result.errors.single, isA<Exception>());
          expect(result.values, isEmpty);
        });
      },
    );

    test('a WebSocket that connects after timeout is closed', () {
      fakeAsync((async) {
        final socket = _FakeWebSocket();
        final connectCompleter = Completer<WebSocket>();
        final provider = ElevenLabsRealtimeTranscriptionProvider(
          'test-key',
          connectWebSocket: (_, {headers}) => connectCompleter.future,
          connectTimeout: const Duration(seconds: 5),
          sessionStartedTimeout: const Duration(hours: 1),
        );
        final pcm = StreamController<Uint8List>(sync: true);
        final result = _listen(provider, pcm.stream);

        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        expect(result.done, isTrue);
        expect(result.errors.single, isA<TimeoutException>());

        connectCompleter.complete(socket);
        async.flushMicrotasks();
        expect(socket.clientCloseCalls, 1);
      });
    });

    test('a synchronous PCM listen failure closes the output stream', () {
      fakeAsync((async) {
        final socket = _FakeWebSocket();
        final provider = _provider(socket);
        final pcm = StreamController<Uint8List>(sync: true);
        pcm.stream.listen((_) {});

        final result = _listen(provider, pcm.stream);
        async.flushMicrotasks();

        expect(result.done, isTrue);
        expect(result.errors, hasLength(1));
      });
    });
  });
}

ElevenLabsRealtimeTranscriptionProvider _provider(
  _FakeWebSocket socket, {
  Duration periodicCommitInterval = const Duration(seconds: 20),
  Duration sessionStartedTimeout = const Duration(hours: 1),
  Duration periodicCommitTimeout = const Duration(hours: 1),
  Duration finalCommitTimeout = const Duration(seconds: 30),
  Duration maxQueuedAudio = const Duration(hours: 1),
}) {
  return ElevenLabsRealtimeTranscriptionProvider(
    'test-key',
    connectWebSocket: (_, {headers}) => Future<WebSocket>.value(socket),
    periodicCommitInterval: periodicCommitInterval,
    connectTimeout: const Duration(hours: 1),
    sessionStartedTimeout: sessionStartedTimeout,
    periodicCommitTimeout: periodicCommitTimeout,
    finalCommitTimeout: finalCommitTimeout,
    maxQueuedAudio: maxQueuedAudio,
  );
}

_StreamResult _listen(
  ElevenLabsRealtimeTranscriptionProvider provider,
  Stream<Uint8List> pcm,
) {
  final result = _StreamResult();
  provider
      .transcribeStream(pcm, sampleRate: 16000)
      .listen(
        result.values.add,
        onError: result.errors.add,
        onDone: () => result.done = true,
      );
  return result;
}

Map<String, dynamic> _sessionStarted() => {
  'message_type': 'session_started',
  'session_id': 'test-session',
};

Map<String, dynamic> _partial(String text) => {
  'message_type': 'partial_transcript',
  'text': text,
};

Map<String, dynamic> _committed(String text) => {
  'message_type': 'committed_transcript',
  'text': text,
};

final class _StreamResult {
  final List<String> values = [];
  final List<Object> errors = [];
  bool done = false;
}

final class _FakeWebSocket implements WebSocket {
  final StreamController<dynamic> _inbound = StreamController<dynamic>(
    sync: true,
  );
  final List<Map<String, dynamic>> sent = [];
  int clientCloseCalls = 0;
  int _readyState = WebSocket.open;

  void serverSend(Map<String, dynamic> event) {
    _inbound.add(jsonEncode(event));
  }

  void serverClose() {
    _readyState = WebSocket.closed;
    unawaited(_inbound.close());
  }

  @override
  int get readyState => _readyState;

  @override
  void add(dynamic data) {
    sent.add(jsonDecode(data as String) as Map<String, dynamic>);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    clientCloseCalls++;
    _readyState = WebSocket.closed;
  }

  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _inbound.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
