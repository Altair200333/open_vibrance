import 'dart:convert';

import 'package:open_vibrance/services/composite_transcription_merger.dart';
import 'package:open_vibrance/services/storage_service.dart';
import 'package:open_vibrance/transcription/elevenlabs_transcription_provider.dart';
import 'package:open_vibrance/transcription/google_transcription_provider.dart';
import 'package:open_vibrance/transcription/openai_transcription_provider.dart';
import 'package:open_vibrance/transcription/types.dart';
import 'package:open_vibrance/utils/common.dart';

/// One engine inside the Composite provider: a provider plus its model id.
class CompositeSlot {
  /// Providers a slot may use. Custom has no model and no live mode.
  static const providers = [
    TranscriptionProviderKey.openai,
    TranscriptionProviderKey.google,
    TranscriptionProviderKey.elevenlabs,
  ];

  final TranscriptionProviderKey provider;
  final String modelId;

  const CompositeSlot(this.provider, this.modelId);

  /// `(modelId, displayName)` pairs offered for [provider].
  static List<(String, String)> modelsFor(TranscriptionProviderKey provider) {
    return switch (provider) {
      TranscriptionProviderKey.openai => [
        for (final m in OpenAIModel.values) (m.modelId, m.displayName),
      ],
      TranscriptionProviderKey.google => [
        for (final m in GoogleModel.values) (m.modelId, m.displayName),
      ],
      TranscriptionProviderKey.elevenlabs => [
        for (final m in ElevenLabsModel.values) (m.modelId, m.displayName),
      ],
      _ => const [],
    };
  }

  /// Default slot for a freshly picked provider.
  static CompositeSlot defaultFor(TranscriptionProviderKey provider) {
    return switch (provider) {
      TranscriptionProviderKey.openai => CompositeSlot(
        provider,
        OpenAIModel.gptLiveTranscribe.modelId,
      ),
      TranscriptionProviderKey.elevenlabs => CompositeSlot(
        provider,
        ElevenLabsModel.scribeV2Realtime.modelId,
      ),
      _ => CompositeSlot(
        TranscriptionProviderKey.google,
        GoogleModel.gemini35Flash.modelId,
      ),
    };
  }

  /// True when the model consumes live PCM while the hotkey is held.
  bool get isRealtime => switch (provider) {
    TranscriptionProviderKey.openai =>
      OpenAIModelExtension.fromKey(modelId).isRealtime,
    TranscriptionProviderKey.elevenlabs =>
      ElevenLabsModelExtension.fromKey(modelId).isRealtime,
    _ => false,
  };

  String get modelName =>
      modelsFor(
        provider,
      ).firstWhere((m) => m.$1 == modelId, orElse: () => (modelId, modelId)).$2;

  String get label => '${provider.displayName} $modelName';

  /// Storage key whose presence the settings UI checks for this slot.
  StorageKey get apiKeyStorageKey => switch (provider) {
    TranscriptionProviderKey.openai => StorageKey.openAiApiKey,
    TranscriptionProviderKey.elevenlabs => StorageKey.elevenLabsApiKey,
    _ => StorageKey.openRouterApiKey,
  };

  Map<String, String> toJson() => {'provider': provider.key, 'model': modelId};

  /// Returns null for unknown providers or models, so stale data is dropped.
  static CompositeSlot? fromJson(Object? json) {
    if (json is! Map) return null;
    final provider =
        providers.where((p) => p.key == json['provider']).firstOrNull;
    final model = json['model'];
    if (provider == null || model is! String) return null;
    if (!modelsFor(provider).any((m) => m.$1 == model)) return null;
    return CompositeSlot(provider, model);
  }

  @override
  bool operator ==(Object other) =>
      other is CompositeSlot &&
      other.provider == provider &&
      other.modelId == modelId;

  @override
  int get hashCode => Object.hash(provider, modelId);
}

class CompositeConfig {
  static const maxSlots = 4;
  static const defaultSlots = [
    CompositeSlot(TranscriptionProviderKey.openai, 'gpt-live-transcribe'),
    CompositeSlot(TranscriptionProviderKey.google, 'google/gemini-3.5-flash'),
  ];

  final List<CompositeSlot> slots;
  final MergerModel mergerModel;

  const CompositeConfig({
    this.slots = defaultSlots,
    this.mergerModel = MergerModel.deepseekV41Flash,
  });

  static List<CompositeSlot> decodeSlots(String? raw) {
    if (raw == null || raw.isEmpty) return defaultSlots;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return defaultSlots;
      final slots =
          decoded
              .map(CompositeSlot.fromJson)
              .whereType<CompositeSlot>()
              .take(maxSlots)
              .toList();
      return slots.isEmpty ? defaultSlots : slots;
    } catch (e) {
      dprint('Invalid Composite slots in storage (${e.runtimeType})');
      return defaultSlots;
    }
  }

  static String encodeSlots(List<CompositeSlot> slots) =>
      jsonEncode([for (final s in slots) s.toJson()]);

  static Future<CompositeConfig> load(SecureStorageService storage) async {
    final raw = await storage.readValue(StorageKey.compositeSlots.key);
    final merger = await storage.readValue(StorageKey.compositeMergerModel.key);
    return CompositeConfig(
      slots: decodeSlots(raw),
      mergerModel: MergerModelExtension.fromKey(merger),
    );
  }
}
