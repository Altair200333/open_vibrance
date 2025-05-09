import 'dart:typed_data';
import 'package:open_vibrance/services/storage_service.dart';
import 'package:open_vibrance/transcription/transcription_provider.dart';
import 'package:open_vibrance/transcription/types.dart';

class CustomTranscriptionProvider implements TranscriptionProvider {
  CustomTranscriptionProvider();

  @override
  Future<String> transcribe(Uint8List audioBytes) async {
    final jsCode = await SecureStorageService().readValue(
      StorageKey.customJSCode.key,
    );

    if (jsCode == null) {
      throw Exception('Custom JS code not found');
    }

    return "Test";
  }
}
