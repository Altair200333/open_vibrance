import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:open_vibrance/services/openrouter_transcription_filter.dart';

void main() {
  group('OpenRouterTranscriptionFilter', () {
    test('sends the privacy-safe structured request and parses text', () async {
      late http.Request capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'finish_reason': 'stop',
                'message': {
                  'content': jsonEncode({'text': 'Это готовый текст.'}),
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final filter = OpenRouterTranscriptionFilter(
        apiKey: 'secret-key',
        client: client,
      );

      final result = await filter.filter('Э-э, это это готовый текст.');

      expect(result, 'Это готовый текст.');
      expect(
        capturedRequest.url,
        Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
      );
      expect(capturedRequest.headers['Authorization'], 'Bearer secret-key');

      final body = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
      expect(body['model'], OpenRouterTranscriptionFilter.modelId);
      expect(body['temperature'], 0);
      expect(body['max_tokens'], 256);
      expect(body['reasoning'], {'enabled': false, 'exclude': true});
      expect(body['provider'], {
        'require_parameters': true,
        'sort': 'latency',
        'data_collection': 'deny',
        'zdr': true,
      });
      expect(body['response_format'], {
        'type': 'json_schema',
        'json_schema': {
          'name': 'clean_transcription',
          'strict': true,
          'schema': {
            'type': 'object',
            'properties': {
              'text': {
                'type': 'string',
                'description': 'The cleaned transcript only',
                'minLength': 1,
              },
            },
            'required': ['text'],
            'additionalProperties': false,
          },
        },
      });

      final messages = body['messages'] as List<dynamic>;
      expect(
        (messages.last as Map<String, dynamic>)['content'],
        'Э-э, это это готовый текст.',
      );
    });

    test('does not call OpenRouter for an empty transcript', () async {
      var requestCount = 0;
      final client = MockClient((_) async {
        requestCount++;
        return http.Response('{}', 200);
      });
      final filter = OpenRouterTranscriptionFilter(
        apiKey: 'secret-key',
        client: client,
      );

      expect(await filter.filter('  \n'), '  \n');
      expect(requestCount, 0);
    });

    test(
      'sizes and caps the output token budget from the transcript',
      () async {
        final tokenBudgets = <int>[];
        final client = MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          tokenBudgets.add(body['max_tokens'] as int);
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'finish_reason': 'stop',
                  'message': {
                    'content': jsonEncode({'text': 'Clean text'}),
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        });
        final filter = OpenRouterTranscriptionFilter(
          apiKey: 'secret-key',
          client: client,
        );

        await filter.filter(List.filled(200, 'a').join());
        await filter.filter(List.filled(40000, 'a').join());

        expect(tokenBudgets, [528, 65536]);
      },
    );

    test('rejects non-success responses without exposing response data', () {
      final client = MockClient(
        (_) async => http.Response('sensitive response', 401),
      );
      final filter = OpenRouterTranscriptionFilter(
        apiKey: 'secret-key',
        client: client,
      );

      expect(
        () => filter.filter('Original text'),
        throwsA(
          isA<Exception>()
              .having((error) => error.toString(), 'message', contains('401'))
              .having(
                (error) => error.toString(),
                'redaction',
                isNot(contains('sensitive response')),
              ),
        ),
      );
    });

    test('rejects malformed structured output', () {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'choices': [
              {
                'finish_reason': 'stop',
                'message': {'content': '{"wrong":"field"}'},
              },
            ],
          }),
          200,
        ),
      );
      final filter = OpenRouterTranscriptionFilter(
        apiKey: 'secret-key',
        client: client,
      );

      expect(
        () => filter.filter('Original text'),
        throwsA(isA<FormatException>()),
      );
    });

    test('enforces a finite request timeout', () {
      final neverCompletes = Completer<http.Response>();
      final client = MockClient((_) => neverCompletes.future);
      final filter = OpenRouterTranscriptionFilter(
        apiKey: 'secret-key',
        client: client,
        requestTimeout: const Duration(milliseconds: 10),
      );

      expect(
        () => filter.filter('Original text'),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}
