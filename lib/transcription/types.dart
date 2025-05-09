enum StorageKey {
  transcriptionProvider('transcription_provider'),
  elevenLabsApiKey('elevenlabs_api_key'),
  elevenLabsModel('elevenlabs_model'),
  openAiApiKey('openai_api_key'),
  openAiModel('openai_model'),
  openAiPrompt('openai_prompt'),
  customJSCode('custom_js_code');

  final String key;
  const StorageKey(this.key);
}

enum TranscriptionProviderKey {
  elevenlabs('elevenlabs_provider'),
  openai('openai_provider'),
  custom('custom_provider');

  final String key;
  const TranscriptionProviderKey(this.key);
}

extension TranscriptionProviderKeyExtension on TranscriptionProviderKey {
  String get displayName {
    switch (this) {
      case TranscriptionProviderKey.elevenlabs:
        return 'ElevenLabs';
      case TranscriptionProviderKey.openai:
        return 'OpenAI';
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
