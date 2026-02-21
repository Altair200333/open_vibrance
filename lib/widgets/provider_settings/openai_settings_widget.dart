import 'package:flutter/material.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:open_vibrance/services/storage_service.dart';
import 'package:open_vibrance/transcription/openai_transcription_provider.dart';
import 'package:open_vibrance/theme/app_colors.dart';
import 'package:open_vibrance/theme/app_styles.dart';
import 'package:open_vibrance/widgets/constants.dart';
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'OpenAI API key',
          style: TextStyle(color: AppColors.textSecondary, fontSize: kFontSizeMd, fontWeight: FontWeight.w500),
        ),
        SizedBox(height: 8),
        TextField(
          controller: _openAiApiKeyController,
          decoration: InputDecoration(hintText: 'Enter your API key'),
          style: TextStyle(color: AppColors.textPrimary),
          onChanged: _onOpenAiApiKeyChanged,
        ),
        SizedBox(height: 32),
        Text(
          'OpenAI Model',
          style: TextStyle(color: AppColors.textSecondary, fontSize: kFontSizeMd, fontWeight: FontWeight.w500),
        ),
        SizedBox(height: 8),
        Text(
          'Select the model to use for transcription',
          style: TextStyle(color: AppColors.textHint, fontSize: kFontSizeSm),
        ),
        SizedBox(height: 8),
        DropdownButtonHideUnderline(
          child: DropdownButton2<OpenAIModel>(
            value: _selectedOpenAiModel,
            onChanged: _onOpenAiModelChanged,
            items: OpenAIModel.values.map(
              (model) => DropdownMenuItem<OpenAIModel>(
                value: model,
                child: Text(
                  model.displayName,
                  style: TextStyle(color: AppColors.textPrimary, fontSize: kFontSizeLg),
                ),
              ),
            ).toList(),
            buttonStyleData: AppStyles.dropdownButton,
            dropdownStyleData: AppStyles.dropdownMenu,
            iconStyleData: AppStyles.dropdownIcon,
            menuItemStyleData: AppStyles.dropdownMenuItem,
          ),
        ),
        SizedBox(height: 32),
        Text(
          'OpenAI Prompt',
          style: TextStyle(color: AppColors.textSecondary, fontSize: kFontSizeMd, fontWeight: FontWeight.w500),
        ),
        SizedBox(height: 8),
        Text(
          'Prompt to guide the transcription',
          style: TextStyle(color: AppColors.textHint, fontSize: kFontSizeSm),
        ),
        SizedBox(height: 8),
        TextField(
          controller: _openAiPromptController,
          decoration: InputDecoration(hintText: 'Enter prompt'),
          style: TextStyle(color: AppColors.textPrimary),
          onChanged: _onOpenAiPromptChanged,
          minLines: 3,
          maxLines: 5,
          keyboardType: TextInputType.multiline,
        ),
      ],
    );
  }
}
