import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_vibrance/services/audio_service.dart';
import 'package:record/record.dart';

void main() {
  group('AudioService streaming drain', () {
    test(
      'waits for raw onDone and keeps a tail emitted after stop returns',
      () async {
        final recorder = _DelayedTailRecorder(Uint8List.fromList([3, 4]));
        final service = AudioService(recorder: recorder);
        final directory = await Directory.systemTemp.createTemp(
          'open_vibrance_audio_test_',
        );
        final path = '${directory.path}${Platform.pathSeparator}recording.wav';
        addTearDown(() async {
          service.dispose();
          await directory.delete(recursive: true);
        });

        final stream = await service.startStreaming();
        final received = <int>[];
        final downstreamDone = Completer<void>();
        stream.listen(
          (chunk) => received.addAll(chunk),
          onDone: downstreamDone.complete,
        );
        recorder.add(Uint8List.fromList([1, 2]));

        var stopCompleted = false;
        final stopFuture = service.stopStreaming(path);
        unawaited(stopFuture.then((_) => stopCompleted = true));
        await recorder.stopCalled.future;
        await Future<void>.delayed(Duration.zero);
        expect(stopCompleted, isFalse);

        recorder.releaseTail();
        expect(await stopFuture, path);
        await downstreamDone.future;

        expect(received, [1, 2, 3, 4]);
        final wav = await File(path).readAsBytes();
        expect(wav.sublist(44), [1, 2, 3, 4]);
      },
    );

    test(
      'does not hang when the forwarded PCM stream has no listener',
      () async {
        final recorder = _DelayedTailRecorder(Uint8List.fromList([7, 8]));
        final service = AudioService(recorder: recorder);
        final directory = await Directory.systemTemp.createTemp(
          'open_vibrance_audio_test_',
        );
        final path = '${directory.path}${Platform.pathSeparator}recording.wav';
        addTearDown(() async {
          service.dispose();
          await directory.delete(recursive: true);
        });

        await service.startStreaming();
        final stopFuture = service.stopStreaming(path);
        await recorder.stopCalled.future;
        recorder.releaseTail();

        await stopFuture.timeout(const Duration(seconds: 1));
        final wav = await File(path).readAsBytes();
        expect(wav.sublist(44), [7, 8]);
      },
    );
  });
}

final class _DelayedTailRecorder extends AudioRecorder {
  _DelayedTailRecorder(this.tail);

  final Uint8List tail;
  final StreamController<Uint8List> _raw = StreamController<Uint8List>(
    sync: true,
  );
  final Completer<void> _release = Completer<void>();
  final Completer<void> stopCalled = Completer<void>();

  void add(Uint8List chunk) => _raw.add(chunk);

  void releaseTail() {
    if (!_release.isCompleted) _release.complete();
  }

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async =>
      _raw.stream;

  @override
  Stream<Amplitude> onAmplitudeChanged(Duration interval) =>
      const Stream<Amplitude>.empty();

  @override
  Future<String?> stop() async {
    if (!stopCalled.isCompleted) stopCalled.complete();
    unawaited(_emitTailAfterRelease());
    return null;
  }

  Future<void> _emitTailAfterRelease() async {
    await _release.future;
    if (!_raw.isClosed) {
      _raw.add(tail);
      await _raw.close();
    }
  }

  @override
  Future<void> dispose() async {}
}
