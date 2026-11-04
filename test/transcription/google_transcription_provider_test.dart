import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:open_vibrance/services/storage_service.dart';
import 'package:open_vibrance/transcription/google_transcription_provider.dart';
import 'package:open_vibrance/transcription/types.dart';

void main() {
  test('sends WAV to Gemini with minimal reasoning via shared key', () async {
    late http.Request sent;
    final provider = GoogleTranscriptionProvider(
      storageService: _FakeStorage({
        // No Google-specific key: falls back to the shared OpenRouter key.
        StorageKey.openRouterApiKey.key: ' or-key ',
        StorageKey.googleModel.key: GoogleModel.gemini35FlashLite.modelId,
      }),
      client: MockClient((request) async {
        sent = request;
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'choices': [
                {
                  'finish_reason': 'stop',
                  'message': {'content': '  Привет, это e2e тест.\n'},
                },
              ],
            }),
          ),
          200,
        );
      }),
    );

    final text = await provider.transcribe(Uint8List.fromList([1, 2, 3]));

    expect(text, 'Привет, это e2e тест.');
    expect(
      sent.url.toString(),
      'https://openrouter.ai/api/v1/chat/completions',
    );
    expect(sent.headers['Authorization'], 'Bearer or-key');
    final body = jsonDecode(sent.body) as Map<String, dynamic>;
    expect(body['model'], 'google/gemini-3.5-flash-lite');
    expect(body['reasoning'], {'effort': 'minimal', 'exclude': true});
    expect(body['provider'], {'sort': 'latency'});
    expect(body['temperature'], 0);
    final audio = (body['messages'][1]['content'] as List).last;
    expect(audio['input_audio'], {'data': 'AQID', 'format': 'wav'});
  });

  test('uses low reasoning effort for Gemini 4 Argon', () {
    final body = GoogleTranscriptionProvider.buildRequestBody(
      GoogleModel.gemini4Argon,
      Uint8List.fromList([1, 2, 3]),
    );
    expect(body['model'], 'google/gemini-4-argon');
    expect(body['reasoning'], {'effort': 'low', 'exclude': true});
  });

  test('fails clearly when no OpenRouter key is stored', () async {
    final provider = GoogleTranscriptionProvider(
      storageService: _FakeStorage({}),
      client: MockClient((_) async => fail('must not send without a key')),
    );
    await expectLater(
      provider.transcribe(Uint8List(0)),
      throwsA(predicate((e) => '$e'.contains('OpenRouter API key'))),
    );
  });
}

final class _FakeStorage implements SecureStorageService {
  _FakeStorage(this.values);
  final Map<String, String> values;

  @override
  Future<String?> readValue(String key) async => values[key];

  @override
  Future<void> saveValue(String key, String value) async => values[key] = value;
}
