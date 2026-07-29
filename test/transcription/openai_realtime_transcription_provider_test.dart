import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_vibrance/transcription/openai_realtime_transcription_provider.dart';
import 'package:open_vibrance/transcription/types.dart';

void main() {
  group('OpenAIRealtimeTranscriptionProvider', () {
    test('configures a manual 24 kHz transcription session', () async {
      final socket = _FakeWebSocket();
      String? connectedUrl;
      Map<String, dynamic>? connectedHeaders;
      final provider = OpenAIRealtimeTranscriptionProvider(
        apiKey: 'test-key',
        prompt: 'Open Vibrance vocabulary',
        connectWebSocket: (url, {headers}) {
          connectedUrl = url;
          connectedHeaders = headers;
          return Future<WebSocket>.value(socket);
        },
      );
      final pcm = StreamController<Uint8List>();
      final subscription = provider
          .transcribeStream(pcm.stream, sampleRate: 24000)
          .listen((_) {});

      await Future<void>.delayed(Duration.zero);

      expect(connectedUrl, OpenAIRealtimeTranscriptionProvider.webSocketUrl);
      final connectedUri = Uri.parse(connectedUrl!);
      expect(connectedUri.queryParameters, <String, String>{
        'intent': 'transcription',
      });
      expect(connectedHeaders, <String, dynamic>{
        'Authorization': 'Bearer test-key',
      });
      expect(provider.providerKey, TranscriptionProviderKey.openai);
      expect(provider.requiredSampleRate, 24000);

      final update = socket.sent.single;
      expect(update['type'], 'session.update');
      final session = update['session'] as Map<String, dynamic>;
      expect(session['type'], 'transcription');
      final audio = session['audio'] as Map<String, dynamic>;
      final input = audio['input'] as Map<String, dynamic>;
      expect(input['format'], <String, dynamic>{
        'type': 'audio/pcm',
        'rate': 24000,
      });
      expect(input['turn_detection'], isNull);
      expect(input['transcription'], <String, dynamic>{
        'model': 'gpt-live-transcribe',
        'delay': 'xhigh',
        'prompt': 'Open Vibrance vocabulary',
      });

      await subscription.cancel();
      await pcm.close();
    });

    test('rejects PCM that is not actually 24 kHz', () async {
      final provider = OpenAIRealtimeTranscriptionProvider(apiKey: 'test-key');

      await expectLater(
        provider.transcribeStream(
          const Stream<Uint8List>.empty(),
          sampleRate: 16000,
        ),
        emitsError(isA<ArgumentError>()),
      );
    });

    test('flushes every queued and tail chunk before the final commit', () {
      fakeAsync((async) {
        final socket = _FakeWebSocket();
        final provider = _provider(socket);
        final pcm = StreamController<Uint8List>(sync: true);
        final result = _listen(provider, pcm.stream);

        async.flushMicrotasks();
        expect(socket.sent.single['type'], 'session.update');

        final head = Uint8List.fromList(<int>[1, 2]);
        final tail = Uint8List.fromList(<int>[3, 4, 5]);
        pcm.add(head);
        expect(socket.sent, hasLength(1));

        socket.serverSend(_sessionUpdated());
        expect(socket.sent, hasLength(2));
        expect(socket.sent[1], _append(head));

        pcm.add(tail);
        unawaited(pcm.close());
        async.flushMicrotasks();

        expect(socket.sent, hasLength(4));
        expect(socket.sent[2], _append(tail));
        expect(socket.sent[3], <String, dynamic>{
          'type': 'input_audio_buffer.commit',
        });

        socket.serverSend(_committed('item-tail'));
        async.flushMicrotasks();
        expect(result.done, isFalse);
        expect(result.errors, isEmpty);

        socket.serverSend(_delta('item-tail', 'Hello'));
        async.flushMicrotasks();
        expect(result.values, <String>['Hello']);
        socket.serverSend(_completed('item-tail', 'Hello world'));
        async.flushMicrotasks();

        expect(result.values, <String>['Hello', 'Hello world']);
        expect(result.errors, isEmpty);
        expect(result.done, isTrue);
        expect(socket.clientCloseCalls, 1);
      });
    });

    test('a matching completed event is the only success barrier', () {
      fakeAsync((async) {
        final socket = _FakeWebSocket();
        final provider = _provider(socket);
        final pcm = StreamController<Uint8List>(sync: true);
        final result = _listen(provider, pcm.stream);

        async.flushMicrotasks();
        socket.serverSend(_sessionUpdated());
        pcm.add(Uint8List.fromList(<int>[1, 2]));
        unawaited(pcm.close());
        async.flushMicrotasks();
        socket.serverSend(_committed('ours'));

        socket.serverSend(_completed('different-item', 'wrong'));
        async.flushMicrotasks();
        expect(result.done, isFalse);
        expect(result.values, isEmpty);

        socket.serverSend(_completed('ours', 'right'));
        async.flushMicrotasks();
        expect(result.values, <String>['right']);
        expect(result.done, isTrue);
      });
    });

    test('the final transcript can authoritatively clear a partial', () {
      fakeAsync((async) {
        final socket = _FakeWebSocket();
        final provider = _provider(socket);
        final pcm = StreamController<Uint8List>(sync: true);
        final result = _listen(provider, pcm.stream);

        async.flushMicrotasks();
        socket.serverSend(_sessionUpdated());
        pcm.add(Uint8List.fromList(<int>[1, 2]));
        unawaited(pcm.close());
        async.flushMicrotasks();
        socket.serverSend(_committed('item'));
        socket.serverSend(_delta('item', 'provisional'));
        socket.serverSend(_completed('item', ''));
        async.flushMicrotasks();

        expect(result.values, <String>['provisional', '']);
        expect(result.done, isTrue);
      });
    });

    test('a transcription failure never returns partial success', () {
      fakeAsync((async) {
        final socket = _FakeWebSocket();
        final provider = _provider(socket);
        final pcm = StreamController<Uint8List>(sync: true);
        final result = _listen(provider, pcm.stream);

        async.flushMicrotasks();
        socket.serverSend(_sessionUpdated());
        pcm.add(Uint8List.fromList(<int>[1, 2]));
        unawaited(pcm.close());
        async.flushMicrotasks();
        socket.serverSend(_committed('item'));
        socket.serverSend(_delta('item', 'partial'));
        socket.serverSend(<String, dynamic>{
          'type': 'conversation.item.input_audio_transcription.failed',
          'item_id': 'item',
          'error': <String, dynamic>{
            'code': 'audio_unintelligible',
            'message': 'Could not transcribe audio',
          },
        });
        async.flushMicrotasks();

        expect(result.values, <String>['partial']);
        expect(result.errors, hasLength(1));
        expect(result.done, isTrue);
      });
    });

    test('times out instead of accepting an unacknowledged commit', () {
      fakeAsync((async) {
        final socket = _FakeWebSocket();
        final provider = _provider(
          socket,
          commitAckTimeout: const Duration(seconds: 5),
        );
        final pcm = StreamController<Uint8List>(sync: true);
        final result = _listen(provider, pcm.stream);

        async.flushMicrotasks();
        socket.serverSend(_sessionUpdated());
        pcm.add(Uint8List.fromList(<int>[1, 2]));
        unawaited(pcm.close());
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 6));
        async.flushMicrotasks();

        expect(result.errors.single, isA<TimeoutException>());
        expect(result.done, isTrue);
      });
    });

    test('times out after commit ACK if no final transcript arrives', () {
      fakeAsync((async) {
        final socket = _FakeWebSocket();
        final provider = _provider(
          socket,
          finalTranscriptTimeout: const Duration(seconds: 5),
        );
        final pcm = StreamController<Uint8List>(sync: true);
        final result = _listen(provider, pcm.stream);

        async.flushMicrotasks();
        socket.serverSend(_sessionUpdated());
        pcm.add(Uint8List.fromList(<int>[1, 2]));
        unawaited(pcm.close());
        async.flushMicrotasks();
        socket.serverSend(_committed('item'));
        async.elapse(const Duration(seconds: 6));
        async.flushMicrotasks();

        expect(result.errors.single, isA<TimeoutException>());
        expect(result.done, isTrue);
      });
    });

    test('fails closed if the socket closes before completion', () {
      fakeAsync((async) {
        final socket = _FakeWebSocket();
        final provider = _provider(socket);
        final pcm = StreamController<Uint8List>(sync: true);
        final result = _listen(provider, pcm.stream);

        async.flushMicrotasks();
        socket.serverSend(_sessionUpdated());
        socket.serverClose();
        async.flushMicrotasks();

        expect(result.errors.single, isA<StateError>());
        expect(result.done, isTrue);
      });
    });

    test('bounds PCM queued before session.updated', () {
      fakeAsync((async) {
        final socket = _FakeWebSocket();
        final provider = _provider(
          socket,
          maxQueuedAudio: const Duration(microseconds: 1),
        );
        final pcm = StreamController<Uint8List>(sync: true);
        final result = _listen(provider, pcm.stream);

        async.flushMicrotasks();
        pcm.add(Uint8List(2));
        async.flushMicrotasks();

        expect(result.errors.single, isA<StateError>());
        expect(result.done, isTrue);
      });
    });
  });
}

OpenAIRealtimeTranscriptionProvider _provider(
  _FakeWebSocket socket, {
  Duration sessionUpdatedTimeout = const Duration(hours: 1),
  Duration commitAckTimeout = const Duration(hours: 1),
  Duration finalTranscriptTimeout = const Duration(hours: 1),
  Duration maxQueuedAudio = const Duration(hours: 1),
}) {
  return OpenAIRealtimeTranscriptionProvider(
    apiKey: 'test-key',
    connectWebSocket: (_, {headers}) => Future<WebSocket>.value(socket),
    connectTimeout: const Duration(hours: 1),
    sessionUpdatedTimeout: sessionUpdatedTimeout,
    commitAckTimeout: commitAckTimeout,
    finalTranscriptTimeout: finalTranscriptTimeout,
    maxQueuedAudio: maxQueuedAudio,
  );
}

_StreamResult _listen(
  OpenAIRealtimeTranscriptionProvider provider,
  Stream<Uint8List> pcm,
) {
  final result = _StreamResult();
  provider
      .transcribeStream(pcm, sampleRate: 24000)
      .listen(
        result.values.add,
        onError: result.errors.add,
        onDone: () => result.done = true,
      );
  return result;
}

Map<String, dynamic> _sessionUpdated() => <String, dynamic>{
  'type': 'session.updated',
  'session': <String, dynamic>{'type': 'transcription'},
};

Map<String, dynamic> _append(Uint8List bytes) => <String, dynamic>{
  'type': 'input_audio_buffer.append',
  'audio': base64Encode(bytes),
};

Map<String, dynamic> _committed(String itemId) => <String, dynamic>{
  'type': 'input_audio_buffer.committed',
  'item_id': itemId,
};

Map<String, dynamic> _delta(String itemId, String delta) => <String, dynamic>{
  'type': 'conversation.item.input_audio_transcription.delta',
  'item_id': itemId,
  'delta': delta,
};

Map<String, dynamic> _completed(String itemId, String transcript) =>
    <String, dynamic>{
      'type': 'conversation.item.input_audio_transcription.completed',
      'item_id': itemId,
      'transcript': transcript,
    };

final class _StreamResult {
  final List<String> values = <String>[];
  final List<Object> errors = <Object>[];
  bool done = false;
}

final class _FakeWebSocket implements WebSocket {
  final StreamController<dynamic> _inbound = StreamController<dynamic>(
    sync: true,
  );
  final List<Map<String, dynamic>> sent = <Map<String, dynamic>>[];
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
