import 'dart:io';
import 'package:open_vibrance/transcription/custom_transcription_provider.dart';
import 'package:open_vibrance/transcription/openai_transcription_provider.dart';
import 'package:open_vibrance/transcription/transcription_provider.dart';
import 'package:open_vibrance/transcription/elevenlabs_transcription_provider.dart';
import 'package:open_vibrance/services/storage_service.dart';
import 'package:clipboard/clipboard.dart';
import 'package:open_vibrance/utils/clipboard.dart';
import 'package:open_vibrance/utils/common.dart';
import 'package:open_vibrance/transcription/types.dart';

class TranscriptionService {
  final SecureStorageService _storageService;

  TranscriptionService([SecureStorageService? storage])
    : _storageService = storage ?? SecureStorageService();

  Future<TranscriptionProviderKey> _getSelectedProvider() async {
    final storedValue = await _storageService.readValue(
      'transcription_provider',
    );
    if (storedValue == null) {
      return TranscriptionProviderKey.elevenlabs;
    }
    return TranscriptionProviderKey.values.firstWhere(
      (p) => p.key == storedValue,
      orElse: () => TranscriptionProviderKey.elevenlabs,
    );
  }

  Future<TranscriptionProvider> _getProvider() async {
    final providerKey = await _getSelectedProvider();

    switch (providerKey) {
      case TranscriptionProviderKey.elevenlabs:
        return ElevenLabsTranscriptionProvider();
      case TranscriptionProviderKey.openai:
        return OpenAITranscriptionProvider();
      case TranscriptionProviderKey.custom:
        return CustomTranscriptionProvider();
      default:
        throw UnimplementedError('$providerKey provider not implemented');
    }
  }

  Future<void> transcribeFileAndPaste(String path) async {
    final provider = await _getProvider();
    final bytes = await File(path).readAsBytes();
    final transcription = await provider.transcribe(bytes);

    dprint('Transcription: $transcription');

    await FlutterClipboard.copy(transcription);

    // wait for it to settle in clipboard for a sec and call paste event
    await Future.delayed(const Duration(milliseconds: 100));
    await pasteContent();
  }
}
