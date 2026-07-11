import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_vibrance/services/openrouter_transcription_filter.dart';
import 'package:open_vibrance/services/storage_service.dart';
import 'package:open_vibrance/services/transcription_service.dart';
import 'package:open_vibrance/transcription/types.dart';

void main() {
  group('TranscriptionService realtime filtering', () {
    test(
      'returns the original text without constructing a filter when disabled',
      () async {
        final storage = _FakeStorage();
        var factoryCalls = 0;
        final service = TranscriptionService(
          storageService: storage,
          transcriptionFilterFactory: (_) {
            factoryCalls++;
            return _CallbackFilter((text) async => 'unexpected');
          },
        );
        const original = '  Э-э, исходный текст.  ';

        expect(await service.filterRealtimeTranscription(original), original);
        expect(factoryCalls, 0);
      },
    );

    test(
      'uses the saved key and returns the filtered text when enabled',
      () async {
        final storage = _FakeStorage({
          StorageKey.elevenLabsRealtimeFilteringEnabled.key: 'true',
          StorageKey.openRouterApiKey.key: '  openrouter-key  ',
        });
        String? receivedKey;
        String? receivedText;
        final service = TranscriptionService(
          storageService: storage,
          transcriptionFilterFactory: (apiKey) {
            receivedKey = apiKey;
            return _CallbackFilter((text) async {
              receivedText = text;
              return 'Готовый текст.';
            });
          },
        );

        final result = await service.filterRealtimeTranscription(
          'Э-э, готовый готовый текст.',
        );

        expect(result, 'Готовый текст.');
        expect(receivedKey, 'openrouter-key');
        expect(receivedText, 'Э-э, готовый готовый текст.');
      },
    );

    test('fails open when the enabled setting has no API key', () async {
      final storage = _FakeStorage({
        StorageKey.elevenLabsRealtimeFilteringEnabled.key: 'true',
        StorageKey.openRouterApiKey.key: '   ',
      });
      var factoryCalls = 0;
      final service = TranscriptionService(
        storageService: storage,
        transcriptionFilterFactory: (_) {
          factoryCalls++;
          return _CallbackFilter((text) async => 'unexpected');
        },
      );
      const original = 'Original text';

      expect(await service.filterRealtimeTranscription(original), original);
      expect(factoryCalls, 0);
    });

    test('fails open on filter errors and timeouts', () async {
      final storage = _enabledStorage();
      final errors = <Object>[
        Exception('network failed'),
        TimeoutException('request timed out'),
      ];

      for (final error in errors) {
        final service = TranscriptionService(
          storageService: storage,
          transcriptionFilterFactory:
              (_) => _CallbackFilter((_) async => throw error),
        );
        const original = '  Original text  ';

        expect(await service.filterRealtimeTranscription(original), original);
      }
    });

    test('fails open on empty model output', () async {
      final service = TranscriptionService(
        storageService: _enabledStorage(),
        transcriptionFilterFactory: (_) => _CallbackFilter((_) async => '  '),
      );
      const original = 'Original text';

      expect(await service.filterRealtimeTranscription(original), original);
    });

    test('fails open when secure storage cannot be read', () async {
      final storage = _FakeStorage()..readError = Exception('storage failed');
      var factoryCalls = 0;
      final service = TranscriptionService(
        storageService: storage,
        transcriptionFilterFactory: (_) {
          factoryCalls++;
          return _CallbackFilter((text) async => 'unexpected');
        },
      );
      const original = 'Original text';

      expect(await service.filterRealtimeTranscription(original), original);
      expect(factoryCalls, 0);
    });
  });
}

_FakeStorage _enabledStorage() => _FakeStorage({
  StorageKey.elevenLabsRealtimeFilteringEnabled.key: 'true',
  StorageKey.openRouterApiKey.key: 'openrouter-key',
});

class _CallbackFilter implements TranscriptionFilter {
  final Future<String> Function(String text) _callback;

  _CallbackFilter(this._callback);

  @override
  Future<String> filter(String transcription) => _callback(transcription);
}

class _FakeStorage implements SecureStorageService {
  final Map<String, String> values;
  Object? readError;

  _FakeStorage([Map<String, String>? values])
    : values = Map<String, String>.from(values ?? const {});

  @override
  Future<String?> readValue(String key) async {
    if (readError case final error?) {
      throw error;
    }
    return values[key];
  }

  @override
  Future<void> saveValue(String key, String value) async {
    values[key] = value;
  }
}
