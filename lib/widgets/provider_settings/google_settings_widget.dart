import 'package:flutter/material.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:open_vibrance/services/openrouter_chat.dart';
import 'package:open_vibrance/services/storage_service.dart';
import 'package:open_vibrance/transcription/google_transcription_provider.dart';
import 'package:open_vibrance/theme/app_color_theme.dart';
import 'package:open_vibrance/theme/app_styles.dart';
import 'package:open_vibrance/widgets/constants.dart';
import 'package:open_vibrance/transcription/types.dart';
import 'package:open_vibrance/widgets/provider_settings/secret_api_key_field.dart';

class GoogleSettingsWidget extends StatefulWidget {
  const GoogleSettingsWidget({super.key});

  @override
  State<GoogleSettingsWidget> createState() => _GoogleSettingsWidgetState();
}

class _GoogleSettingsWidgetState extends State<GoogleSettingsWidget> {
  final TextEditingController _apiKeyController = TextEditingController();
  GoogleModel _selectedModel = GoogleModel.gemini35Flash;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final storage = SecureStorageService();
    // Prefill with the shared OpenRouter key so it is never typed twice.
    final key = await readOpenRouterApiKey(
      storage,
      preferred: StorageKey.googleApiKey,
    );
    final modelId = await storage.readValue(StorageKey.googleModel.key);
    if (mounted) {
      setState(() {
        _apiKeyController.text = key ?? '';
        _selectedModel = GoogleModelExtension.fromKey(modelId);
      });
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  void _onApiKeyChanged(String value) {
    saveOpenRouterApiKey(SecureStorageService(), value);
  }

  Future<void> _onModelChanged(GoogleModel? model) async {
    if (model == null) {
      return;
    }
    await SecureStorageService().saveValue(
      StorageKey.googleModel.key,
      model.modelId,
    );
    if (mounted) {
      setState(() {
        _selectedModel = model;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'OpenRouter API key',
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: kFontSizeMd,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Gemini runs through OpenRouter. The same key is shared with '
          'Composite and transcription filtering.',
          style: TextStyle(color: colors.textHint, fontSize: kFontSizeSm),
        ),
        SizedBox(height: 8),
        SecretApiKeyField(
          controller: _apiKeyController,
          hintText: 'Enter your OpenRouter API key',
          onChanged: _onApiKeyChanged,
        ),
        SizedBox(height: 32),
        Text(
          'Google Model',
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: kFontSizeMd,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Select the model to use for transcription',
          style: TextStyle(color: colors.textHint, fontSize: kFontSizeSm),
        ),
        SizedBox(height: 8),
        DropdownButtonHideUnderline(
          child: DropdownButton2<GoogleModel>(
            value: _selectedModel,
            onChanged: _onModelChanged,
            items:
                GoogleModel.values
                    .map(
                      (model) => DropdownMenuItem<GoogleModel>(
                        value: model,
                        child: Text(
                          model.displayName,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: kFontSizeLg,
                          ),
                        ),
                      ),
                    )
                    .toList(),
            buttonStyleData: AppStyles.dropdownButton(colors),
            dropdownStyleData: AppStyles.dropdownMenu(colors),
            iconStyleData: AppStyles.dropdownIcon(colors),
            menuItemStyleData: AppStyles.dropdownMenuItem(colors),
          ),
        ),
      ],
    );
  }
}
