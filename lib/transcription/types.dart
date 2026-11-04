enum StorageKey {
  transcriptionProvider('transcription_provider'),
  elevenLabsApiKey('elevenlabs_api_key'),
  elevenLabsModel('elevenlabs_model'),
  elevenLabsRealtimeFilteringEnabled('elevenlabs_realtime_filtering_enabled'),
  openRouterApiKey('openrouter_api_key'),
  openAiApiKey('openai_api_key'),
  openAiModel('openai_model'),
  openAiPrompt('openai_prompt'),
  googleApiKey('google_api_key'),
  googleModel('google_model'),
  compositeSlots('composite_slots'),
  compositeMergerModel('composite_merger_model'),
  customPythonScript('custom_python_script'),
  recordingHotkey('recording_hotkey');

  final String key;
  const StorageKey(this.key);
}

enum TranscriptionProviderKey {
  elevenlabs('elevenlabs_provider'),
  openai('openai_provider'),
  google('google_provider'),
  composite('composite_provider'),
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
      case TranscriptionProviderKey.google:
        return 'Google';
      case TranscriptionProviderKey.composite:
        return 'Composite';
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
