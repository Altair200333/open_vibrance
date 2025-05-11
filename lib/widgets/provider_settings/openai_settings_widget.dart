import 'package:flutter/material.dart';
import 'package:open_vibrance/services/storage_service.dart';
import 'package:open_vibrance/transcription/openai_transcription_provider.dart';
import 'package:open_vibrance/theme/app_colors.dart';
import 'package:open_vibrance/transcription/types.dart';

class OpenAiSettingsWidget extends StatefulWidget {
  const OpenAiSettingsWidget({super.key});

  @override
  State<OpenAiSettingsWidget> createState() => _OpenAiSettingsWidgetState();
}

class _OpenAiSettingsWidgetState extends State<OpenAiSettingsWidget> {
  final TextEditingController _openAiApiKeyController = TextEditingController();
  final TextEditingController _openAiPromptController = TextEditingController();
  OpenAIModel _selectedOpenAiModel = OpenAIModel.gpt4oMiniTranscribe;

  @override
  void initState() {
    super.initState();
    _loadOpenAiApiKey();
    _loadOpenAiModel();
    _loadOpenAiPrompt();
  }

  Future<void> _loadOpenAiApiKey() async {
    final key = await SecureStorageService().readValue(
      StorageKey.openAiApiKey.key,
    );
    if (key != null && mounted) {
      setState(() {
        _openAiApiKeyController.text = key;
      });
    }
  }

  Future<void> _loadOpenAiModel() async {
    final modelKey = await SecureStorageService().readValue(
      StorageKey.openAiModel.key,
    );
    if (mounted) {
      setState(() {
        _selectedOpenAiModel = OpenAIModelExtension.fromKey(modelKey);
      });
    }
  }

  Future<void> _loadOpenAiPrompt() async {
    final prompt = await SecureStorageService().readValue(
      StorageKey.openAiPrompt.key,
    );
    if (prompt != null && mounted) {
      setState(() {
        _openAiPromptController.text = prompt;
      });
    }
  }

  @override
  void dispose() {
    _openAiApiKeyController.dispose();
    _openAiPromptController.dispose();
    super.dispose();
  }

  void _onOpenAiApiKeyChanged(String value) {
    SecureStorageService().saveValue(StorageKey.openAiApiKey.key, value);
  }

  void _onOpenAiModelChanged(OpenAIModel? model) {
    if (model == null) {
      return;
    }
    SecureStorageService().saveValue(StorageKey.openAiModel.key, model.modelId);
    if (mounted) {
      setState(() {
        _selectedOpenAiModel = model;
      });
    }
  }

  void _onOpenAiPromptChanged(String value) {
    SecureStorageService().saveValue(StorageKey.openAiPrompt.key, value);
  }

  @override
  Widget build(BuildContext context) {
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
}
