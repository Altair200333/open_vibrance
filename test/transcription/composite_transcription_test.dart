import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_vibrance/services/composite_transcription_merger.dart';
import 'package:open_vibrance/services/storage_service.dart';
import 'package:open_vibrance/services/transcription_service.dart';
import 'package:open_vibrance/transcription/composite_config.dart';
import 'package:open_vibrance/transcription/composite_transcription_provider.dart';
import 'package:open_vibrance/transcription/streaming_transcription_provider.dart';
import 'package:open_vibrance/transcription/transcription_provider.dart';
import 'package:open_vibrance/transcription/types.dart';
import 'package:open_vibrance/utils/pcm_resampler.dart';

Uint8List _pcm(List<int> samples) {
  final data = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(i * 2, samples[i], Endian.little);
  }
  return data.buffer.asUint8List();
}

void main() {
  test('resampler gives the same audio for any chunking', () {
    final input = _pcm([for (var i = 0; i < 2400; i++) (i * 7) % 3000 - 1500]);
    final whole = Pcm16Resampler(fromRate: 24000, toRate: 16000).convert(input);
    final chunked = Pcm16Resampler(fromRate: 24000, toRate: 16000);
    final pieces = BytesBuilder();
    // Odd chunk sizes split samples across chunks on purpose.
    for (var i = 0; i < input.length; i += 333) {
      pieces.add(
        chunked.convert(input.sublist(i, (i + 333).clamp(0, input.length))),
      );
    }
    expect(pieces.toBytes(), whole);
    expect(whole.length ~/ 2, closeTo(1600, 1));

    final ramp = Pcm16Resampler(
      fromRate: 16000,
      toRate: 24000,
    ).convert(_pcm([0, 300, 600]));
    expect(ByteData.sublistView(ramp).getInt16(2, Endian.little), 200);
  });

  test('hybrid run: live slots, file slots, failures and fallback', () async {
    final wav = File('${Directory.systemTemp.path}/composite_test.wav')
      ..writeAsBytesSync([9, 9]);
    addTearDown(() => wav.deleteSync());

    final openAiLive = _FakeStreamer(24000, finalText: 'live 24k');
    final elevenLive = _FakeStreamer(16000, fail: true);
    const slots = [
      CompositeSlot(TranscriptionProviderKey.openai, 'gpt-live-transcribe'),
      CompositeSlot(TranscriptionProviderKey.elevenlabs, 'scribe_v2_realtime'),
      CompositeSlot(TranscriptionProviderKey.google, 'google/gemini-3.5-flash'),
      CompositeSlot(TranscriptionProviderKey.openai, 'gpt-transcribe'),
    ];
    late List<CompositeHypothesis> merged;
    final run = CompositeLiveRun(
      slots: slots,
      streamers: [openAiLive, elevenLive, null, null],
      batchFor:
          (slot) => _FakeBatch(switch (slot.modelId) {
            'scribe_v2_realtime' => 'eleven from file',
            'google/gemini-3.5-flash' => 'gemini from file',
            _ => null, // gpt-transcribe slot "has no key"
          }),
      merge: (hypotheses) async {
        merged = hypotheses;
        return 'merged';
      },
    );
    expect(run.recordingSampleRate, 24000);

    final mic = StreamController<Uint8List>();
    run.attach(mic.stream);
    mic.add(_pcm(List.filled(2400, 100)));
    await mic.close();

    expect(await run.finish(wav.path), 'merged');
    expect(openAiLive.received, 4800);
    expect(elevenLive.received, closeTo(3200, 2)); // resampled to 16 kHz
    expect(
      [for (final h in merged) '${h.label}: ${h.text}'],
      [
        'OpenAI GPT Live Transcribe: live 24k',
        'ElevenLabs Scribe v2 Realtime: eleven from file',
        'Google Gemini 3.5 Flash: gemini from file',
      ],
    );
  });

  test(
    'every slot failing is an error; batch-only config records to file',
    () async {
      final run = CompositeLiveRun(
        slots: const [
          CompositeSlot(TranscriptionProviderKey.openai, 'gpt-live-transcribe'),
        ],
        streamers: [_FakeStreamer(24000, fail: true)],
        batchFor: (_) => _FakeBatch(null),
        merge: (_) async => fail('nothing to merge'),
      );
      final mic = StreamController<Uint8List>();
      run.attach(mic.stream);
      await mic.close();
      await expectLater(run.finish('missing.wav'), throwsException);

      // A live slot without its key does not force live recording.
      final service = TranscriptionService(
        storageService: _FakeStorage({
          StorageKey.transcriptionProvider.key:
              TranscriptionProviderKey.composite.key,
        }),
      );
      expect(await service.getCompositeLiveRun(), isNull);
    },
  );

  test('slot config decoding drops junk and caps at four slots', () {
    expect(
      CompositeConfig.decodeSlots('not json'),
      CompositeConfig.defaultSlots,
    );
    final five = CompositeConfig.encodeSlots(
      List.filled(5, CompositeSlot.defaultFor(TranscriptionProviderKey.google)),
    );
    expect(CompositeConfig.decodeSlots(five), hasLength(4));
    expect(
      CompositeConfig.decodeSlots(
        '[{"provider":"custom_provider","model":"x"},'
        '{"provider":"openai_provider","model":"gpt-transcribe"}]',
      ),
      const [CompositeSlot(TranscriptionProviderKey.openai, 'gpt-transcribe')],
    );
  });
}

final class _FakeStreamer implements StreamingTranscriptionProvider {
  _FakeStreamer(
    this.requiredSampleRate, {
    this.finalText = '',
    this.fail = false,
  });

  @override
  final int requiredSampleRate;
  final String finalText;
  final bool fail;
  int received = 0;

  @override
  TranscriptionProviderKey get providerKey => TranscriptionProviderKey.openai;

  @override
  Stream<String> transcribeStream(
    Stream<Uint8List> pcmStream, {
    required int sampleRate,
  }) async* {
    expect(sampleRate, requiredSampleRate);
    await for (final chunk in pcmStream) {
      received += chunk.length;
    }
    if (fail) throw Exception('socket closed');
    yield finalText;
  }
}

final class _FakeBatch implements TranscriptionProvider {
  _FakeBatch(this.text);
  final String? text;

  @override
  Future<String> transcribe(Uint8List audioBytes) async =>
      text ?? (throw Exception('API key not found'));
}

final class _FakeStorage implements SecureStorageService {
  _FakeStorage(this.values);
  final Map<String, String> values;

  @override
  Future<String?> readValue(String key) async => values[key];

  @override
  Future<void> saveValue(String key, String value) async => values[key] = value;
}
