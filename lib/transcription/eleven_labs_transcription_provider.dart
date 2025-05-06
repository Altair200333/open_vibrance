import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:open_vibrance/transcription/transcription_provider.dart';
import 'package:open_vibrance/transcription/types.dart';
import 'package:open_vibrance/utils/storage_service.dart';

enum ElevenLabsModel {
  scribeV1('scribe_v1'),
  scribeV1Experimental('scribe_v1_experimental');

  final String modelId;
  const ElevenLabsModel(this.modelId);
}

/// Implementation of [TranscriptionService] using ElevenLabs Speech-to-Text API.
class ElevenLabsTranscriptionProvider implements TranscriptionProvider {
  final ElevenLabsModel model = ElevenLabsModel.scribeV1Experimental;

  ElevenLabsTranscriptionProvider();

  @override
  Future<String> transcribe(Uint8List audioBytes) async {
    final apiKey = await SecureStorageService().readValue(
      ApiKey.elevenLabs.key,
    );

    if (apiKey == null) {
      throw Exception('ElevenLabs API key not found');
    }

    final uri = Uri.parse('https://api.elevenlabs.io/v1/speech-to-text');

    var file = http.MultipartFile.fromBytes(
      'file',
      audioBytes,
      filename: 'audio.wav',
      contentType: MediaType('audio', 'wav'),
    );

    final request =
        http.MultipartRequest('POST', uri)
          ..headers['xi-api-key'] = apiKey
          ..fields['model_id'] = model.modelId
          ..fields['num_speakers'] = '1'
          ..fields['tag_audio_events'] = 'false'
          ..fields['timestamps_granularity'] = 'none'
          ..files.add(file);

    final response = await request.send();
    final responseBody = await response.stream.bytesToString();

    if (response.statusCode != 200) {
      throw Exception(
        'ElevenLabs API Error: ${response.statusCode} - $responseBody',
      );
    }

    final Map<String, dynamic> jsonResponse = jsonDecode(responseBody);

    final dynamic textValue = jsonResponse['text'];

    // sanity validation
    if (textValue == null || textValue is! String) {
      throw Exception('"text" is missing or not a string: $jsonResponse');
    }

    final String transcription = textValue.toString();
    return transcription;
  }
}
