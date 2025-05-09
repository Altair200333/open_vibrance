enum StorageKey {
  elevenLabsApiKey('elevenlabs_api_key'),
  elevenLabsModel('elevenlabs_model'),
  transcriptionProvider('transcription_provider');

  final String key;
  const StorageKey(this.key);
}

enum TranscriptionProviderKey {
  elevenlabs('elevenlabs_provider'),
  whisper('whisper_provider'),
  custom('custom_provider');

  final String key;
  const TranscriptionProviderKey(this.key);
}

extension TranscriptionProviderKeyExtension on TranscriptionProviderKey {
  String get displayName {
    switch (this) {
      case TranscriptionProviderKey.elevenlabs:
        return 'ElevenLabs';
      case TranscriptionProviderKey.whisper:
        return 'Whisper';
      case TranscriptionProviderKey.custom:
        return 'Custom';
    }
  }

  static TranscriptionProviderKey fromKey(String? key) {
    return TranscriptionProviderKey.values.firstWhere(
      (e) => e.key == key,
      orElse: () => TranscriptionProviderKey.elevenlabs,
    );
  }
}
