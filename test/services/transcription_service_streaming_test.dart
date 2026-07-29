import 'package:flutter_test/flutter_test.dart';
import 'package:open_vibrance/services/storage_service.dart';
import 'package:open_vibrance/services/transcription_service.dart';
import 'package:open_vibrance/transcription/openai_realtime_transcription_provider.dart';
import 'package:open_vibrance/transcription/openai_transcription_provider.dart';
import 'package:open_vibrance/transcription/types.dart';

void main() {
  group('TranscriptionService OpenAI streaming routing', () {
    test('selects GPT Live Transcribe with the shared OpenAI key', () async {
      final service = TranscriptionService(
        storageService: _FakeStorage(<String, String>{
          StorageKey.transcriptionProvider.key:
              TranscriptionProviderKey.openai.key,
          StorageKey.openAiModel.key: OpenAIModel.gptLiveTranscribe.modelId,
          StorageKey.openAiApiKey.key: 'openai-key',
          StorageKey.openAiPrompt.key: 'Vocabulary context',
        }),
      );

      final provider = await service.getStreamingProvider();

      expect(provider, isA<OpenAIRealtimeTranscriptionProvider>());
      expect(provider!.providerKey, TranscriptionProviderKey.openai);
      expect(provider.requiredSampleRate, 24000);
    });

    test('keeps file OpenAI models on the batch path', () async {
      final service = TranscriptionService(
        storageService: _FakeStorage(<String, String>{
          StorageKey.transcriptionProvider.key:
              TranscriptionProviderKey.openai.key,
          StorageKey.openAiModel.key: OpenAIModel.gptTranscribe.modelId,
          StorageKey.openAiApiKey.key: 'openai-key',
        }),
      );

      expect(await service.getStreamingProvider(), isNull);
    });

    test('fails before recording when the shared key is missing', () async {
      final service = TranscriptionService(
        storageService: _FakeStorage(<String, String>{
          StorageKey.transcriptionProvider.key:
              TranscriptionProviderKey.openai.key,
          StorageKey.openAiModel.key: OpenAIModel.gptLiveTranscribe.modelId,
        }),
      );

      await expectLater(
        service.getStreamingProvider(),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('OpenAI API key not found'),
          ),
        ),
      );
    });

    test('does not expose streaming for custom providers', () async {
      final service = TranscriptionService(
        storageService: _FakeStorage(<String, String>{
          StorageKey.transcriptionProvider.key:
              TranscriptionProviderKey.custom.key,
        }),
      );

      expect(await service.getStreamingProvider(), isNull);
    });

    test('does not apply the ElevenLabs filter to OpenAI output', () async {
      var filterCreated = false;
      final service = TranscriptionService(
        storageService: _FakeStorage(<String, String>{
          StorageKey.elevenLabsRealtimeFilteringEnabled.key: 'true',
          StorageKey.openRouterApiKey.key: 'openrouter-key',
        }),
        transcriptionFilterFactory: (_) {
          filterCreated = true;
          throw StateError('OpenAI output must bypass this filter');
        },
      );

      expect(
        await service.filterStreamingTranscription(
          'original',
          TranscriptionProviderKey.openai,
        ),
        'original',
      );
      expect(filterCreated, isFalse);
    });
  });
}

final class _FakeStorage implements SecureStorageService {
  _FakeStorage(this.values);

  final Map<String, String> values;

  @override
  Future<String?> readValue(String key) async => values[key];

  @override
  Future<void> saveValue(String key, String value) async {
    values[key] = value;
  }
}
