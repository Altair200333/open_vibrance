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
  gpt4oTranscribe('gpt-4o-transcribe');

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
    }
  }

  static OpenAIModel fromKey(String? key) {
    return OpenAIModel.values.firstWhere(
      (e) => e.modelId == key,
      orElse: () => OpenAIModel.gpt4oMiniTranscribe,
    );
  }
}

class OpenAITranscriptionProvider implements TranscriptionProvider {
  OpenAITranscriptionProvider();

  Future<OpenAIModel> _loadModel() async {
    final modelKey = await SecureStorageService().readValue(
      StorageKey.openAiModel.key,
    );
    return OpenAIModelExtension.fromKey(modelKey);
  }

  @override
  Future<String> transcribe(Uint8List audioBytes) async {
    final apiKey = await SecureStorageService().readValue(
      StorageKey.openAiApiKey.key,
    );
    final model = await _loadModel();
    dprint('Running transcription with model: $model');

    if (apiKey == null) {
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

    final prompt = await SecureStorageService().readValue(
      StorageKey.openAiPrompt.key,
    );
    if (prompt != null && prompt.isNotEmpty) {
      request.fields['prompt'] = prompt;
    }

    final response = await request.send();
    final responseBody = await response.stream.bytesToString();

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
