import 'package:flutter/material.dart';
import 'package:open_vibrance/services/storage_service.dart';
import 'package:open_vibrance/transcription/types.dart';
import 'package:open_vibrance/theme/app_colors.dart';
import 'package:open_vibrance/transcription/elevenlabs_transcription_provider.dart';
import 'package:open_vibrance/transcription/openai_transcription_provider.dart';

const double dotSize = 20;

class SettingsBox extends StatefulWidget {
  const SettingsBox({super.key, required this.expandedWindowSize});

  final Size expandedWindowSize;

  @override
  State<SettingsBox> createState() => _SettingsBoxState();
}

class _SettingsBoxState extends State<SettingsBox> {
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _openAiApiKeyController = TextEditingController();
  final TextEditingController _openAiPromptController = TextEditingController();
  final TextEditingController _customJSCodeController = TextEditingController();
  TranscriptionProviderKey _selectedProvider =
      TranscriptionProviderKey.elevenlabs;
  ElevenLabsModel _selectedElevenLabsModel = ElevenLabsModel.scribeV1;
  OpenAIModel _selectedOpenAiModel = OpenAIModel.gpt4oMiniTranscribe;

  @override
  void initState() {
    super.initState();

    _loadProvider();
    _loadApiKeys();

    _loadElevenLabsModel();
    _loadOpenAiModel();
    _loadOpenAiPrompt();
    _loadCustomJSCode();
  }

  Future<void> _loadApiKeys() async {
    await _loadElevenLabsApiKey();
    await _loadOpenAiApiKey();
  }

  Future<void> _loadElevenLabsApiKey() async {
    final key = await SecureStorageService().readValue(
      StorageKey.elevenLabsApiKey.key,
    );
    if (key != null) {
      _apiKeyController.text = key;
    }
  }

  Future<void> _loadOpenAiApiKey() async {
    final key = await SecureStorageService().readValue(
      StorageKey.openAiApiKey.key,
    );
    if (key != null) {
      _openAiApiKeyController.text = key;
    }
  }

  Future<void> _loadProvider() async {
    final key = await SecureStorageService().readValue(
      StorageKey.transcriptionProvider.key,
    );
    setState(() {
      _selectedProvider = TranscriptionProviderKeyExtension.fromKey(key);
    });
  }

  Future<void> _loadElevenLabsModel() async {
    final modelId = await SecureStorageService().readValue(
      StorageKey.elevenLabsModel.key,
    );
    setState(() {
      _selectedElevenLabsModel = ElevenLabsModelExtension.fromKey(modelId);
    });
  }

  Future<void> _loadOpenAiModel() async {
    final modelKey = await SecureStorageService().readValue(
      StorageKey.openAiModel.key,
    );
    setState(() {
      _selectedOpenAiModel = OpenAIModelExtension.fromKey(modelKey);
    });
  }

  Future<void> _loadOpenAiPrompt() async {
    final prompt = await SecureStorageService().readValue(
      StorageKey.openAiPrompt.key,
    );
    if (prompt != null) {
      _openAiPromptController.text = prompt;
    }
  }

  Future<void> _loadCustomJSCode() async {
    final code = await SecureStorageService().readValue(
      StorageKey.customPythonScript.key,
    );
    if (code != null) {
      _customJSCodeController.text = code;
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _openAiApiKeyController.dispose();
    _openAiPromptController.dispose();
    _customJSCodeController.dispose();
    super.dispose();
  }

  void _onElevenLabsApiKeyChanged(String value) {
    SecureStorageService().saveValue(StorageKey.elevenLabsApiKey.key, value);
  }

  void _onOpenAiApiKeyChanged(String value) {
    SecureStorageService().saveValue(StorageKey.openAiApiKey.key, value);
  }

  void _onTranscriptionProviderChanged(TranscriptionProviderKey? provider) {
    if (provider == null) {
      return;
    }
    SecureStorageService().saveValue(
      StorageKey.transcriptionProvider.key,
      provider.key,
    );
    setState(() {
      _selectedProvider = provider;
    });
  }

  void _onElevenLabsModelChanged(ElevenLabsModel? model) {
    if (model == null) {
      return;
    }
    SecureStorageService().saveValue(
      StorageKey.elevenLabsModel.key,
      model.modelId,
    );
    setState(() {
      _selectedElevenLabsModel = model;
    });
  }

  void _onOpenAiModelChanged(OpenAIModel? model) {
    if (model == null) {
      return;
    }
    SecureStorageService().saveValue(StorageKey.openAiModel.key, model.modelId);
    setState(() {
      _selectedOpenAiModel = model;
    });
  }

  void _onOpenAiPromptChanged(String value) {
    SecureStorageService().saveValue(StorageKey.openAiPrompt.key, value);
  }

  void _onCustomJSCodeChanged(String value) {
    SecureStorageService().saveValue(StorageKey.customPythonScript.key, value);
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: dotSize * 2,
      left: dotSize * 2.5,
      child: _buildSettingsContainer(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              SizedBox(height: 16),
              _buildProviderSelector(),
              SizedBox(height: 16),
              _buildProviderSettings(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsContainer({required Widget child}) {
    return Container(
      width: widget.expandedWindowSize.width - dotSize * 3,
      height: widget.expandedWindowSize.height - dotSize * 3,
      decoration: BoxDecoration(
        color: AppColors.gray700,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: child,
    );
  }

  Widget _buildHeader() {
    return Text(
      'Settings',
      style: TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildProviderSelector() {
    var dropdownItems = TranscriptionProviderKey.values.map(
      (provider) => DropdownMenuItem(
        value: provider,
        child: Text(
          provider.displayName,
          style: TextStyle(color: Colors.white),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Transcription Provider',
          style: TextStyle(color: Colors.white),
        ),
        DropdownButton<TranscriptionProviderKey>(
          value: _selectedProvider,
          dropdownColor: AppColors.gray700,
          items: dropdownItems.toList(),
          onChanged: _onTranscriptionProviderChanged,
        ),
      ],
    );
  }

  Widget _buildProviderSettings() {
    switch (_selectedProvider) {
      case TranscriptionProviderKey.elevenlabs:
        return _elevenLabsSettings();
      case TranscriptionProviderKey.openai:
        return _openAiSettings();
      case TranscriptionProviderKey.custom:
        return _customSettings();
    }
  }

  Widget _elevenLabsSettings() {
    var modelItems = ElevenLabsModel.values.map(
      (model) => DropdownMenuItem(
        value: model,
        child: Text(model.displayName, style: TextStyle(color: Colors.white)),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ElevenLabs API key', style: TextStyle(color: Colors.white)),
        SizedBox(height: 8),
        Text(
          'Uses Scribe model from ElevenLabs (subscription required)',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        SizedBox(height: 8),
        TextField(
          controller: _apiKeyController,
          decoration: InputDecoration(
            hintText: 'Enter your API key',
            hintStyle: TextStyle(color: Colors.white54),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.0),
              borderSide: BorderSide(color: Colors.white70),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.0),
              borderSide: BorderSide(color: Colors.white70),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.0),
              borderSide: BorderSide(color: AppColors.blue500, width: 2),
            ),
            contentPadding: EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 8.0,
            ),
          ),
          style: TextStyle(color: Colors.white),
          onChanged: _onElevenLabsApiKeyChanged,
        ),
        SizedBox(height: 32),
        Text('ElevenLabs Model', style: TextStyle(color: Colors.white)),
        SizedBox(height: 8),
        Text(
          'Select the model to use for transcription',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        DropdownButton<ElevenLabsModel>(
          value: _selectedElevenLabsModel,
          dropdownColor: AppColors.gray700,
          items: modelItems.toList(),
          onChanged: _onElevenLabsModelChanged,
        ),
      ],
    );
  }

  Widget _openAiSettings() {
    var modelItems = OpenAIModel.values.map(
      (model) => DropdownMenuItem(
        value: model,
        child: Text(model.displayName, style: TextStyle(color: Colors.white)),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('OpenAI API key', style: TextStyle(color: Colors.white)),
        SizedBox(height: 8),
        TextField(
          controller: _openAiApiKeyController,
          decoration: InputDecoration(
            hintText: 'Enter your API key',
            hintStyle: TextStyle(color: Colors.white54),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.0),
              borderSide: BorderSide(color: Colors.white70),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.0),
              borderSide: BorderSide(color: Colors.white70),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.0),
              borderSide: BorderSide(color: AppColors.blue500, width: 2),
            ),
            contentPadding: EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 8.0,
            ),
          ),
          style: TextStyle(color: Colors.white),
          onChanged: _onOpenAiApiKeyChanged,
        ),
        SizedBox(height: 32),
        Text('OpenAI Model', style: TextStyle(color: Colors.white)),
        SizedBox(height: 8),
        Text(
          'Select the model to use for transcription',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        DropdownButton<OpenAIModel>(
          value: _selectedOpenAiModel,
          dropdownColor: AppColors.gray700,
          items: modelItems.toList(),
          onChanged: _onOpenAiModelChanged,
        ),
        SizedBox(height: 32),
        Text('OpenAI Prompt', style: TextStyle(color: Colors.white)),
        SizedBox(height: 8),
        Text(
          'Prompt to guide the transcription',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        SizedBox(height: 8),
        TextField(
          controller: _openAiPromptController,
          decoration: InputDecoration(
            hintText: 'Enter prompt',
            hintStyle: TextStyle(color: Colors.white54),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.0),
              borderSide: BorderSide(color: Colors.white70),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.0),
              borderSide: BorderSide(color: Colors.white70),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.0),
              borderSide: BorderSide(color: AppColors.blue500, width: 2),
            ),
            contentPadding: EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 8.0,
            ),
          ),
          style: TextStyle(color: Colors.white),
          onChanged: _onOpenAiPromptChanged,
          minLines: 3,
          maxLines: 5,
          keyboardType: TextInputType.multiline,
        ),
      ],
    );
  }

  Widget _customSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Custom JavaScript', style: TextStyle(color: Colors.white)),
        SizedBox(height: 8),
        Text(
          'Enter custom JavaScript code to be executed for transcription.\n\n- It should read audio from global variable `audio` which is a base64 audio.\n- The code should return final transcription as a string.',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        SizedBox(height: 8),
        Text(
          'If unsure what this means, just paste docs from your transcription provider into ChatGPT and ask to write JS snippet accepting base64 audio and returning a string from it',
          style: TextStyle(color: AppColors.blue300, fontSize: 12),
        ),
        SizedBox(height: 16),
        TextField(
          controller: _customJSCodeController,
          decoration: InputDecoration(
            hintText: 'Plain JavaScript code',
            hintStyle: TextStyle(color: Colors.white54),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.0),
              borderSide: BorderSide(color: Colors.white70),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.0),
              borderSide: BorderSide(color: Colors.white70),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.0),
              borderSide: BorderSide(color: AppColors.blue500, width: 2),
            ),
            contentPadding: EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 8.0,
            ),
          ),
          style: TextStyle(color: Colors.white),
          onChanged: _onCustomJSCodeChanged,
          minLines: 5,
          maxLines: 300,
          keyboardType: TextInputType.multiline,
        ),
      ],
    );
  }
}
