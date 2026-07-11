import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_vibrance/services/audio_service.dart';
import 'package:open_vibrance/services/audio_spectrum_analyzer.dart';
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

    test(
      'spectrum observer preserves PCM chunk boundaries, order, and tail',
      () async {
        final tail = Uint8List.fromList([9, 10]);
        final recorder = _DelayedTailRecorder(tail);
        final service = AudioService(recorder: recorder);
        final directory = await Directory.systemTemp.createTemp(
          'open_vibrance_audio_test_',
        );
        final path = '${directory.path}${Platform.pathSeparator}recording.wav';
        addTearDown(() async {
          service.dispose();
          await directory.delete(recursive: true);
        });

        final first = Uint8List(4096);
        final second = Uint8List.fromList([1, 2, 3, 4]);
        final received = <Uint8List>[];
        final downstreamDone = Completer<void>();
        final stream = await service.startStreaming();
        stream.listen(
          (chunk) => received.add(Uint8List.fromList(chunk)),
          onDone: downstreamDone.complete,
        );

        recorder.add(first);
        recorder.add(second);
        expect(service.spectrumFrame.hasSpectrum, isTrue);

        final stopFuture = service.stopStreaming(path);
        await recorder.stopCalled.future;
        recorder.releaseTail();
        await stopFuture;
        await downstreamDone.future;

        expect(received, hasLength(3));
        expect(received[0], orderedEquals(first));
        expect(received[1], orderedEquals(second));
        expect(received[2], orderedEquals(tail));
        final wav = await File(path).readAsBytes();
        expect(wav.sublist(44), orderedEquals([...first, ...second, ...tail]));
        expect(service.spectrumFrame.hasSpectrum, isFalse);
      },
    );

    test('spectrum failure falls back without touching PCM or WAV', () async {
      final tail = Uint8List.fromList([7, 8]);
      final recorder = _DelayedTailRecorder(tail);
      final service = AudioService(
        recorder: recorder,
        spectrumAnalyzerFactory: (_) => _ThrowingSpectrumAnalyzer(),
      );
      final directory = await Directory.systemTemp.createTemp(
        'open_vibrance_audio_test_',
      );
      final path = '${directory.path}${Platform.pathSeparator}recording.wav';
      addTearDown(() async {
        service.dispose();
        await directory.delete(recursive: true);
      });

      final first = Uint8List.fromList([1, 2, 3, 4]);
      final received = <int>[];
      final downstreamDone = Completer<void>();
      final stream = await service.startStreaming();
      stream.listen(
        (chunk) => received.addAll(chunk),
        onDone: downstreamDone.complete,
      );

      recorder.add(first);
      recorder.addAmplitude(-18);
      expect(service.spectrumFrame.hasSpectrum, isFalse);
      expect(service.amplitude, -18);

      final stopFuture = service.stopStreaming(path);
      await recorder.stopCalled.future;
      recorder.releaseTail();
      await stopFuture;
      await downstreamDone.future;

      expect(received, [...first, ...tail]);
      final wav = await File(path).readAsBytes();
      expect(wav.sublist(44), [...first, ...tail]);
    });

    test('buffers PCM that arrives before the downstream listener', () async {
      final tail = Uint8List.fromList([5, 6]);
      final recorder = _DelayedTailRecorder(tail);
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
      final early = Uint8List.fromList([1, 2]);
      final late = Uint8List.fromList([3, 4]);
      recorder.add(early);

      final received = <int>[];
      final downstreamDone = Completer<void>();
      stream.listen(
        (chunk) => received.addAll(chunk),
        onDone: downstreamDone.complete,
      );
      recorder.add(late);

      final stopFuture = service.stopStreaming(path);
      await recorder.stopCalled.future;
      recorder.releaseTail();
      await stopFuture;
      await downstreamDone.future;

      expect(received, [...early, ...late, ...tail]);
    });

    test(
      'samples amplitude responsively and clears stale level on stop',
      () async {
        final recorder = _DelayedTailRecorder(Uint8List(0));
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
        expect(service.amplitude, AudioService.silenceDb);
        expect(
          recorder.amplitudeInterval,
          AudioService.amplitudeUpdateInterval,
        );

        recorder.addAmplitude(-12);
        expect(service.amplitude, -12);

        final stopFuture = service.stopStreaming(path);
        await recorder.stopCalled.future;
        recorder.releaseTail();
        await stopFuture;

        expect(service.amplitude, AudioService.silenceDb);
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
  final StreamController<Amplitude> _amplitudes =
      StreamController<Amplitude>.broadcast(sync: true);
  final Completer<void> _release = Completer<void>();
  final Completer<void> stopCalled = Completer<void>();
  Duration? amplitudeInterval;

  void add(Uint8List chunk) => _raw.add(chunk);

  void addAmplitude(double current) {
    _amplitudes.add(Amplitude(current: current, max: current));
  }

  void releaseTail() {
    if (!_release.isCompleted) _release.complete();
  }

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async =>
      _raw.stream;

  @override
  Stream<Amplitude> onAmplitudeChanged(Duration interval) {
    amplitudeInterval = interval;
    return _amplitudes.stream;
  }

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
  Future<void> dispose() async {
    if (!_amplitudes.isClosed) await _amplitudes.close();
    if (!_raw.isClosed) await _raw.close();
  }
}

final class _ThrowingSpectrumAnalyzer extends AudioSpectrumAnalyzer {
  @override
  void addPcm16(Uint8List chunk, SpectrumFrameCallback onFrame) {
    throw StateError('Synthetic spectrum failure');
  }
}
