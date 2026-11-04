import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:open_vibrance/services/openrouter_chat.dart';
import 'package:open_vibrance/services/storage_service.dart';
import 'package:open_vibrance/transcription/transcription_provider.dart';
import 'package:open_vibrance/transcription/types.dart';
import 'package:open_vibrance/utils/common.dart';

enum GoogleModel {
  gemini35Flash('google/gemini-3.5-flash'),
  gemini35FlashLite('google/gemini-3.5-flash-lite'),
  gemini4Argon('google/gemini-4-argon');

  final String modelId;
  const GoogleModel(this.modelId);
}

extension GoogleModelExtension on GoogleModel {
  String get displayName {
    switch (this) {
      case GoogleModel.gemini35Flash:
        return 'Gemini 3.5 Flash';
      case GoogleModel.gemini35FlashLite:
        return 'Gemini 3.5 Flash Lite';
      case GoogleModel.gemini4Argon:
        return 'Gemini 4 Argon';
    }
  }

  /// OpenRouter rejects `reasoning.enabled: false` for Gemini models with HTTP
  /// 400 ("Reasoning is mandatory"); Gemini 3.5 supports `minimal`, while
  /// Gemini 4 Argon's lowest legal mode is `low`.
  String get reasoningEffort {
    switch (this) {
      case GoogleModel.gemini35Flash:
      case GoogleModel.gemini35FlashLite:
        return 'minimal';
      case GoogleModel.gemini4Argon:
        return 'low';
    }
  }

  static GoogleModel fromKey(String? key) {
    return GoogleModel.values.firstWhere(
      (e) => e.modelId == key,
      orElse: () => GoogleModel.gemini35Flash,
    );
  }
}

/// Gemini audio transcription of a saved WAV file through OpenRouter.
class GoogleTranscriptionProvider implements TranscriptionProvider {
  static const systemPrompt = '''
You are a verbatim speech-to-text engine.
Transcribe the attached audio exactly as spoken, in the speaker's own language.
The speech is usually Russian mixed with English IT, AI and business terms (CI, e2e, PR, prod, Claude, Opus, Ozon, Wildberries and so on): write English terms in Latin script as they are commonly written, and Russian words in Cyrillic.
Never translate. Never replace a Russian word with an English one (for example, "одновременно" must stay "одновременно", not "simultaneously"), and never translate English terms into Russian.
Keep profanity, slang and explicit vocabulary exactly as spoken, without censoring or masking.
Do not summarize, answer, comment or add anything. Add natural punctuation.
Return ONLY the transcript text. If there is no speech, return an empty string.
''';

  GoogleTranscriptionProvider({
    GoogleModel? modelOverride,
    SecureStorageService? storageService,
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 60),
  }) : _modelOverride = modelOverride,
       _storageService = storageService ?? SecureStorageService(),
       _client = client;

  final GoogleModel? _modelOverride;
  final SecureStorageService _storageService;
  final http.Client? _client;
  final Duration requestTimeout;

  /// OpenRouter rejects `reasoning.enabled: false` for Gemini 3.5 with HTTP
  /// 400 ("Reasoning is mandatory"); minimal effort is the fastest legal mode.
  static Map<String, dynamic> buildRequestBody(
    GoogleModel model,
    Uint8List audioBytes,
  ) {
    return {
      'model': model.modelId,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'Transcribe this audio verbatim.'},
            {
              'type': 'input_audio',
              'input_audio': {
                'data': base64Encode(audioBytes),
                'format': 'wav',
              },
            },
          ],
        },
      ],
      'temperature': 0,
      'reasoning': {'effort': model.reasoningEffort, 'exclude': true},
      'provider': {'sort': 'latency'},
    };
  }

  @override
  Future<String> transcribe(Uint8List audioBytes) async {
    final apiKey = await readOpenRouterApiKey(
      _storageService,
      preferred: StorageKey.googleApiKey,
    );
    if (apiKey == null) {
      throw Exception('OpenRouter API key for Google not found');
    }
    final model =
        _modelOverride ??
        GoogleModelExtension.fromKey(
          await _storageService.readValue(StorageKey.googleModel.key),
        );
    dprint('Running transcription with model: ${model.modelId}');

    return postOpenRouterChat(
      apiKey: apiKey,
      body: buildRequestBody(model, audioBytes),
      timeout: requestTimeout,
      client: _client,
    );
  }
}
