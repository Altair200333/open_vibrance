import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:open_vibrance/transcription/transcription_provider.dart';
import 'package:open_vibrance/transcription/types.dart';
import 'package:open_vibrance/services/storage_service.dart';
import 'package:open_vibrance/utils/common.dart';

enum OpenAIModel {
  whisper1('whisper-1'),
  gpt4oMiniTranscribe('gpt-4o-mini-transcribe'),
  gpt4oTranscribe('gpt-4o-transcribe'),
  gptTranscribe('gpt-transcribe'),
  gptLiveTranscribe('gpt-live-transcribe');

  final String modelId;
  const OpenAIModel(this.modelId);
}

extension OpenAIModelExtension on OpenAIModel {
  String get displayName {
    switch (this) {
      case OpenAIModel.whisper1:
        return 'Whisper 1';
      case OpenAIModel.gpt4oMiniTranscribe:
        return 'GPT-4o Mini Transcribe';
      case OpenAIModel.gpt4oTranscribe:
        return 'GPT-4o Transcribe';
      case OpenAIModel.gptTranscribe:
        return 'GPT Transcribe';
      case OpenAIModel.gptLiveTranscribe:
        return 'GPT Live Transcribe';
    }
  }

  bool get isRealtime => this == OpenAIModel.gptLiveTranscribe;

  OpenAIModel get batchEquivalent =>
      isRealtime ? OpenAIModel.gptTranscribe : this;

  static OpenAIModel fromKey(String? key) {
    return OpenAIModel.values.firstWhere(
      (e) => e.modelId == key,
      orElse: () => OpenAIModel.gpt4oMiniTranscribe,
    );
  }
}

typedef OpenAIRequestSender =
    Future<http.StreamedResponse> Function(http.BaseRequest request);

class OpenAITranscriptionProvider implements TranscriptionProvider {
  static const int maxAudioFileBytes = 25 * 1024 * 1024;

  OpenAITranscriptionProvider({
    OpenAIModel? modelOverride,
    SecureStorageService? storageService,
    OpenAIRequestSender? requestSender,
    Duration requestTimeout = const Duration(minutes: 2),
  }) : _modelOverride = modelOverride,
       _storageService = storageService ?? SecureStorageService(),
       _requestSender = requestSender,
       _requestTimeout = requestTimeout,
       assert(requestTimeout.inMicroseconds > 0);

  final OpenAIModel? _modelOverride;
  final SecureStorageService _storageService;
  final OpenAIRequestSender? _requestSender;
  final Duration _requestTimeout;

  Future<OpenAIModel> _loadModel() async {
    final modelKey = await _storageService.readValue(
      StorageKey.openAiModel.key,
    );
    return OpenAIModelExtension.fromKey(modelKey);
  }

  @override
  Future<String> transcribe(Uint8List audioBytes) async {
    if (audioBytes.length > maxAudioFileBytes) {
      throw ArgumentError.value(
        audioBytes.length,
        'audioBytes',
        'OpenAI transcription files must not exceed 25 MB',
      );
    }

    final apiKey =
        (await _storageService.readValue(StorageKey.openAiApiKey.key))?.trim();
    final selectedModel = _modelOverride ?? await _loadModel();
    final model = selectedModel.batchEquivalent;
    dprint('Running transcription with model: ${model.modelId}');

    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('OpenAI API key not found');
    }

    final uri = Uri.parse('https://api.openai.com/v1/audio/transcriptions');

    var file = http.MultipartFile.fromBytes(
      'file',
      audioBytes,
      filename: 'audio.wav',
      contentType: MediaType('audio', 'wav'),
    );

    final request =
        http.MultipartRequest('POST', uri)
          ..headers['Authorization'] = 'Bearer $apiKey'
          ..fields['model'] = model.modelId
          ..files.add(file);

    final prompt = await _storageService.readValue(StorageKey.openAiPrompt.key);
    if (prompt != null && prompt.isNotEmpty) {
      request.fields['prompt'] = prompt;
    }

    final client = _requestSender == null ? http.Client() : null;
    final ({http.StreamedResponse response, String body}) result;
    try {
      result = await (() async {
        final response =
            await (client?.send(request) ?? _requestSender!(request));
        final body = await response.stream.bytesToString();
        return (response: response, body: body);
      })().timeout(_requestTimeout);
    } finally {
      client?.close();
    }
    final response = result.response;
    final responseBody = result.body;

    if (response.statusCode != 200) {
      throw Exception(
        'OpenAI API Error: ${response.statusCode} - $responseBody',
      );
    }

    final Map<String, dynamic> jsonResponse = jsonDecode(responseBody);

    final dynamic textValue = jsonResponse['text'];

    if (textValue == null || textValue is! String) {
      throw Exception('"text" is missing or not a string: $jsonResponse');
    }

    return textValue.toString();
  }
}
