import 'dart:io';
import 'package:open_vibrance/transcription/composite_config.dart';
import 'package:open_vibrance/transcription/composite_transcription_provider.dart';
import 'package:open_vibrance/transcription/custom_transcription_provider.dart';
import 'package:open_vibrance/transcription/elevenlabs_realtime_transcription_provider.dart';
import 'package:open_vibrance/transcription/google_transcription_provider.dart';
import 'package:open_vibrance/transcription/openai_realtime_transcription_provider.dart';
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
        return OpenAITranscriptionProvider(storageService: _storageService);
      case TranscriptionProviderKey.google:
        return GoogleTranscriptionProvider(storageService: _storageService);
      case TranscriptionProviderKey.composite:
        return CompositeTranscriptionProvider(storageService: _storageService);
      case TranscriptionProviderKey.custom:
        return CustomTranscriptionProvider();
    }
  }

  /// Returns a streaming provider when the selected model supports live audio.
  Future<StreamingTranscriptionProvider?> getStreamingProvider() async {
    final providerKey = await _getSelectedProvider();
    switch (providerKey) {
      case TranscriptionProviderKey.elevenlabs:
        final modelId = await _storageService.readValue(
          StorageKey.elevenLabsModel.key,
        );
        final model = ElevenLabsModelExtension.fromKey(modelId);
        if (!model.isRealtime) return null;

        final apiKey =
            (await _storageService.readValue(
              StorageKey.elevenLabsApiKey.key,
            ))?.trim();
        if (apiKey == null || apiKey.isEmpty) {
          throw Exception('ElevenLabs API key not found');
        }
        return ElevenLabsRealtimeTranscriptionProvider(apiKey);

      case TranscriptionProviderKey.openai:
        final modelId = await _storageService.readValue(
          StorageKey.openAiModel.key,
        );
        final model = OpenAIModelExtension.fromKey(modelId);
        if (!model.isRealtime) return null;

        final apiKey =
            (await _storageService.readValue(
              StorageKey.openAiApiKey.key,
            ))?.trim();
        if (apiKey == null || apiKey.isEmpty) {
          throw Exception('OpenAI API key not found');
        }
        final prompt = await _storageService.readValue(
          StorageKey.openAiPrompt.key,
        );
        return OpenAIRealtimeTranscriptionProvider(
          apiKey: apiKey,
          prompt: prompt,
        );

      case TranscriptionProviderKey.google:
      case TranscriptionProviderKey.composite:
      case TranscriptionProviderKey.custom:
        return null;
    }
  }

  /// Composite with at least one live slot; null means record to a file and
  /// let [transcribeFileAndPaste] run every Composite slot on it.
  Future<CompositeLiveRun?> getCompositeLiveRun() async {
    if (await _getSelectedProvider() != TranscriptionProviderKey.composite) {
      return null;
    }
    final config = await CompositeConfig.load(_storageService);
    final factory = CompositeSlotFactory(_storageService);
    final streamers = [
      for (final slot in config.slots) await factory.streaming(slot),
    ];
    if (streamers.every((s) => s == null)) return null;
    return CompositeLiveRun(
      slots: config.slots,
      streamers: streamers,
      batchFor: factory.batch,
      merge: await factory.merger(config),
    );
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

  /// Correctness fallback for a realtime session whose finality is uncertain.
  Future<String> transcribeFileWithBatchFallback(
    String path,
    TranscriptionProviderKey providerKey,
  ) async {
    final bytes = await File(path).readAsBytes();
    final TranscriptionProvider provider = switch (providerKey) {
      TranscriptionProviderKey.elevenlabs => ElevenLabsTranscriptionProvider(
        modelOverride: ElevenLabsModel.scribeV2,
        storageService: _storageService,
      ),
      TranscriptionProviderKey.openai => OpenAITranscriptionProvider(
        modelOverride: OpenAIModel.gptTranscribe,
        storageService: _storageService,
      ),
      TranscriptionProviderKey.google => GoogleTranscriptionProvider(
        storageService: _storageService,
      ),
      TranscriptionProviderKey.composite => CompositeTranscriptionProvider(
        storageService: _storageService,
      ),
      TranscriptionProviderKey.custom =>
        throw UnsupportedError(
          'Custom provider has no realtime batch fallback',
        ),
    };
    final transcription = await provider.transcribe(bytes);
    dprint('${providerKey.displayName} batch fallback: $transcription');
    return transcription;
  }

  /// Applies post-processing only when it belongs to the streaming provider.
  Future<String> filterStreamingTranscription(
    String transcription,
    TranscriptionProviderKey providerKey,
  ) {
    if (providerKey != TranscriptionProviderKey.elevenlabs) {
      return Future<String>.value(transcription);
    }
    return filterRealtimeTranscription(transcription);
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
