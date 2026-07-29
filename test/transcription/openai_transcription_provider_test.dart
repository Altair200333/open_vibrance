import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:open_vibrance/services/storage_service.dart';
import 'package:open_vibrance/transcription/openai_transcription_provider.dart';
import 'package:open_vibrance/transcription/types.dart';

void main() {
  group('OpenAIModel', () {
    test('round-trips the new model IDs', () {
      expect(
        OpenAIModelExtension.fromKey('gpt-transcribe'),
        OpenAIModel.gptTranscribe,
      );
      expect(
        OpenAIModelExtension.fromKey('gpt-live-transcribe'),
        OpenAIModel.gptLiveTranscribe,
      );
      expect(OpenAIModel.gptTranscribe.displayName, 'GPT Transcribe');
      expect(OpenAIModel.gptLiveTranscribe.displayName, 'GPT Live Transcribe');
    });

    test('maps only the live model to a file-compatible equivalent', () {
      expect(
        OpenAIModel.gptLiveTranscribe.batchEquivalent,
        OpenAIModel.gptTranscribe,
      );
      expect(
        OpenAIModel.gpt4oTranscribe.batchEquivalent,
        OpenAIModel.gpt4oTranscribe,
      );
    });

    test('keeps the existing default for unknown stored values', () {
      expect(
        OpenAIModelExtension.fromKey('unknown'),
        OpenAIModel.gpt4oMiniTranscribe,
      );
    });
  });

  group('OpenAITranscriptionProvider', () {
    test('sends gpt-transcribe with the shared key and prompt', () async {
      final storage = _FakeStorage({
        StorageKey.openAiApiKey.key: 'test-key',
        StorageKey.openAiModel.key: OpenAIModel.gptTranscribe.modelId,
        StorageKey.openAiPrompt.key: 'Product names: Open Vibrance',
      });
      http.MultipartRequest? captured;
      final provider = OpenAITranscriptionProvider(
        storageService: storage,
        requestSender: (request) async {
          captured = request as http.MultipartRequest;
          return _jsonResponse(<String, dynamic>{'text': 'hello'});
        },
      );

      final result = await provider.transcribe(
        Uint8List.fromList(<int>[1, 2, 3]),
      );

      expect(result, 'hello');
      expect(
        captured!.url,
        Uri.parse('https://api.openai.com/v1/audio/transcriptions'),
      );
      expect(captured!.headers['Authorization'], 'Bearer test-key');
      expect(captured!.fields['model'], 'gpt-transcribe');
      expect(captured!.fields['prompt'], 'Product names: Open Vibrance');
      expect(captured!.files.single.filename, 'audio.wav');
    });

    test('never sends the live model to the file endpoint', () async {
      final storage = _FakeStorage({
        StorageKey.openAiApiKey.key: 'test-key',
        StorageKey.openAiModel.key: OpenAIModel.gptLiveTranscribe.modelId,
      });
      String? requestedModel;
      final provider = OpenAITranscriptionProvider(
        storageService: storage,
        requestSender: (request) async {
          requestedModel = (request as http.MultipartRequest).fields['model'];
          return _jsonResponse(<String, dynamic>{'text': 'fallback'});
        },
      );

      expect(await provider.transcribe(Uint8List(2)), 'fallback');
      expect(requestedModel, OpenAIModel.gptTranscribe.modelId);
    });

    test('model override wins over the stored selection', () async {
      final storage = _FakeStorage({
        StorageKey.openAiApiKey.key: 'test-key',
        StorageKey.openAiModel.key: OpenAIModel.whisper1.modelId,
      });
      String? requestedModel;
      final provider = OpenAITranscriptionProvider(
        modelOverride: OpenAIModel.gptTranscribe,
        storageService: storage,
        requestSender: (request) async {
          requestedModel = (request as http.MultipartRequest).fields['model'];
          return _jsonResponse(<String, dynamic>{'text': 'override'});
        },
      );

      await provider.transcribe(Uint8List(2));

      expect(requestedModel, OpenAIModel.gptTranscribe.modelId);
    });

    test('rejects an empty API key before sending', () async {
      var sent = false;
      final provider = OpenAITranscriptionProvider(
        storageService: _FakeStorage({
          StorageKey.openAiApiKey.key: '   ',
          StorageKey.openAiModel.key: OpenAIModel.gptTranscribe.modelId,
        }),
        requestSender: (request) async {
          sent = true;
          return _jsonResponse(<String, dynamic>{'text': 'unused'});
        },
      );

      await expectLater(
        provider.transcribe(Uint8List(2)),
        throwsA(isA<Exception>()),
      );
      expect(sent, isFalse);
    });

    test('bounds the complete batch request with a deadline', () async {
      final pending = Completer<http.StreamedResponse>();
      addTearDown(() {
        if (!pending.isCompleted) {
          pending.complete(_jsonResponse(<String, dynamic>{'text': 'late'}));
        }
      });
      final provider = OpenAITranscriptionProvider(
        storageService: _FakeStorage({
          StorageKey.openAiApiKey.key: 'test-key',
          StorageKey.openAiModel.key: OpenAIModel.gptTranscribe.modelId,
        }),
        requestSender: (_) => pending.future,
        requestTimeout: const Duration(milliseconds: 5),
      );

      await expectLater(
        provider.transcribe(Uint8List(2)),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('rejects files above the documented 25 MB limit', () async {
      var sent = false;
      final provider = OpenAITranscriptionProvider(
        storageService: _FakeStorage(<String, String>{}),
        requestSender: (_) async {
          sent = true;
          return _jsonResponse(<String, dynamic>{'text': 'unused'});
        },
      );

      await expectLater(
        provider.transcribe(
          Uint8List(OpenAITranscriptionProvider.maxAudioFileBytes + 1),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(sent, isFalse);
    });
  });
}

http.StreamedResponse _jsonResponse(Map<String, dynamic> body) {
  return http.StreamedResponse(
    Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
    200,
  );
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
