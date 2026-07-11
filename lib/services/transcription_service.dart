import 'dart:io';
import 'package:open_vibrance/transcription/custom_transcription_provider.dart';
import 'package:open_vibrance/transcription/elevenlabs_realtime_transcription_provider.dart';
import 'package:open_vibrance/transcription/openai_transcription_provider.dart';
import 'package:open_vibrance/transcription/streaming_transcription_provider.dart';
import 'package:open_vibrance/transcription/transcription_provider.dart';
import 'package:open_vibrance/transcription/elevenlabs_transcription_provider.dart';
import 'package:open_vibrance/services/storage_service.dart';
import 'package:clipboard/clipboard.dart';
import 'package:open_vibrance/utils/clipboard.dart';
import 'package:open_vibrance/utils/common.dart';
import 'package:open_vibrance/transcription/types.dart';
import 'package:open_vibrance/services/openrouter_transcription_filter.dart';

typedef TranscriptionFilterFactory =
    TranscriptionFilter Function(String apiKey);

class TranscriptionService {
  final SecureStorageService _storageService;
  final TranscriptionFilterFactory _transcriptionFilterFactory;

  TranscriptionService({
    SecureStorageService? storageService,
    TranscriptionFilterFactory? transcriptionFilterFactory,
  }) : _storageService = storageService ?? SecureStorageService(),
       _transcriptionFilterFactory =
           transcriptionFilterFactory ??
           ((apiKey) => OpenRouterTranscriptionFilter(apiKey: apiKey));

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
        return ElevenLabsTranscriptionProvider(storageService: _storageService);
      case TranscriptionProviderKey.openai:
        return OpenAITranscriptionProvider();
      case TranscriptionProviderKey.custom:
        return CustomTranscriptionProvider();
    }
  }

  /// Returns a StreamingTranscriptionProvider if the active provider supports streaming.
  /// Returns null for batch-only providers (OpenAI, Custom, non-realtime ElevenLabs).
  Future<StreamingTranscriptionProvider?> getStreamingProvider() async {
    final providerKey = await _getSelectedProvider();
    if (providerKey != TranscriptionProviderKey.elevenlabs) return null;

    // Check if the selected ElevenLabs model is realtime
    final modelId = await _storageService.readValue(
      StorageKey.elevenLabsModel.key,
    );
    final model = ElevenLabsModelExtension.fromKey(modelId);
    if (!model.isRealtime) return null;

    // Load API key
    final apiKey = await _storageService.readValue(
      StorageKey.elevenLabsApiKey.key,
    );
    if (apiKey == null) throw Exception('ElevenLabs API key not found');

    return ElevenLabsRealtimeTranscriptionProvider(apiKey);
  }

  Future<String> transcribeFileAndPaste(
    String path, {
    bool paste = true,
  }) async {
    final provider = await _getProvider();
    final bytes = await File(path).readAsBytes();
    final transcription = await provider.transcribe(bytes);

    dprint('Transcription: $transcription');

    await FlutterClipboard.copy(transcription);

    if (paste) {
      // wait for it to settle in clipboard for a sec and call paste event
      await Future.delayed(const Duration(milliseconds: 100));
      await pasteContent();
    }

    return transcription;
  }

  /// Correctness fallback for a failed realtime ElevenLabs session.
  /// Always uses the batch Scribe v2 endpoint, regardless of the selected model.
  Future<String> transcribeFileWithElevenLabsBatch(String path) async {
    final bytes = await File(path).readAsBytes();
    final transcription = await ElevenLabsTranscriptionProvider(
      modelOverride: ElevenLabsModel.scribeV2,
      storageService: _storageService,
    ).transcribe(bytes);
    dprint('ElevenLabs batch fallback transcription: $transcription');
    return transcription;
  }

  /// Cleans a completed ElevenLabs realtime transcript when the optional
  /// OpenRouter filter is enabled. Filtering is fail-open: recording success
  /// must never depend on a second cloud service.
  Future<String> filterRealtimeTranscription(String transcription) async {
    if (transcription.trim().isEmpty) {
      dprint('[Transcription filter] skipped: transcript is empty');
      return transcription;
    }

    try {
      final enabled = await _storageService.readValue(
        StorageKey.elevenLabsRealtimeFilteringEnabled.key,
      );
      if (enabled != 'true') {
        dprint('[Transcription filter] skipped: disabled');
        return transcription;
      }

      final apiKey =
          (await _storageService.readValue(
            StorageKey.openRouterApiKey.key,
          ))?.trim();
      if (apiKey == null || apiKey.isEmpty) {
        dprint('[Transcription filter] skipped: OpenRouter API key is missing');
        return transcription;
      }

      dprint(
        '[Transcription filter] request started '
        '(model: ${OpenRouterTranscriptionFilter.modelId})',
      );
      final filtered = await _transcriptionFilterFactory(
        apiKey,
      ).filter(transcription);
      if (filtered.trim().isEmpty) {
        dprint('[Transcription filter] empty result; using original text');
        return transcription;
      }
      dprint('[Transcription filter] request succeeded');
      return filtered;
    } catch (e) {
      dprint(
        '[Transcription filter] failed; using original text '
        '(${e.runtimeType})',
      );
      return transcription;
    }
  }
}
