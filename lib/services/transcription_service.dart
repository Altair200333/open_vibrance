import 'dart:io';
import 'package:open_vibrance/transcription/transcription_provider.dart';
import 'package:open_vibrance/transcription/eleven_labs_transcription_provider.dart';
import 'package:open_vibrance/services/storage_service.dart';
import 'package:clipboard/clipboard.dart';
import 'package:open_vibrance/utils/clipboard.dart';
import 'package:open_vibrance/utils/common.dart';

class TranscriptionService {
  final SecureStorageService _storageService;

  TranscriptionService([SecureStorageService? storage])
    : _storageService = storage ?? SecureStorageService();

  Future<String> _getSelectedProvider() async {
    final providerKey = await _storageService.readValue(
      'transcription_provider',
    );

    return providerKey ?? 'elevenlabs';
  }

  Future<TranscriptionProvider> _getProvider() async {
    final providerKey = await _getSelectedProvider();

    switch (providerKey) {
      case 'elevenlabs':
        return ElevenLabsTranscriptionProvider();
      default:
        throw Exception('Unknown transcription provider: $providerKey');
    }
  }

  Future<void> transcribeFileAndPaste(String path) async {
    final provider = await _getProvider();
    final bytes = await File(path).readAsBytes();
    final transcription = await provider.transcribe(bytes);

    dprint('Transcription: $transcription');
    await FlutterClipboard.copy(transcription);
    await Future.delayed(const Duration(milliseconds: 100));
    await pasteContent();
  }
}
