import 'package:flutter/material.dart';
import 'package:open_vibrance/services/storage_service.dart';
import 'package:open_vibrance/transcription/types.dart';
import 'package:open_vibrance/theme/app_colors.dart';
import 'package:open_vibrance/transcription/eleven_labs_transcription_provider.dart';

const double dotSize = 20;

class SettingsBox extends StatefulWidget {
  const SettingsBox({super.key, required this.expandedWindowSize});

  final Size expandedWindowSize;

  @override
  State<SettingsBox> createState() => _SettingsBoxState();
}

class _SettingsBoxState extends State<SettingsBox> {
  final TextEditingController _apiKeyController = TextEditingController();
  TranscriptionProviderKey _selectedProvider =
      TranscriptionProviderKey.elevenlabs;
  ElevenLabsModel _selectedModel = ElevenLabsModel.scribeV1;

  @override
  void initState() {
    super.initState();

    _loadProvider();
    _loadApiKey();
    _loadElevenLabsModel();
  }

  Future<void> _loadApiKey() async {
    await _loadElevenLabsApiKey();
  }

  Future<void> _loadElevenLabsApiKey() async {
    final key = await SecureStorageService().readValue(
      StorageKey.elevenLabsApiKey.key,
    );
    if (key != null) {
      _apiKeyController.text = key;
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
      _selectedModel = ElevenLabsModelExtension.fromKey(modelId);
    });
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  void _onElevenLabsApiKeyChanged(String value) {
    SecureStorageService().saveValue(StorageKey.elevenLabsApiKey.key, value);
  }

  void _onTranscriptionProviderChanged(TranscriptionProviderKey? provider) {
    if (provider == null) return;
    SecureStorageService().saveValue(
      StorageKey.transcriptionProvider.key,
      provider.key,
    );
    setState(() {
      _selectedProvider = provider;
    });
  }

  void _onElevenLabsModelChanged(ElevenLabsModel? model) {
    if (model == null) return;
    SecureStorageService().saveValue(
      StorageKey.elevenLabsModel.key,
      model.modelId,
    );
    setState(() {
      _selectedModel = model;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: dotSize * 2,
      left: dotSize * 2.5,
      child: _buildSettingsContainer(
        child: Padding(
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
      case TranscriptionProviderKey.whisper:
        return _whisperSettings();
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
          'Uses Scribe model from ElevenLabs (subscription required).',
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
          'Select the model to use for transcription.',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        DropdownButton<ElevenLabsModel>(
          value: _selectedModel,
          dropdownColor: AppColors.gray700,
          items: modelItems.toList(),
          onChanged: _onElevenLabsModelChanged,
        ),
      ],
    );
  }

  Widget _whisperSettings() {
    return Text(
      'Whisper settings will go here',
      style: TextStyle(color: Colors.white),
    );
  }

  Widget _customSettings() {
    return Text(
      'Custom provider settings will go here',
      style: TextStyle(color: Colors.white),
    );
  }
}
