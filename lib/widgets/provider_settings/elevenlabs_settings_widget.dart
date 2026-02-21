import 'package:flutter/material.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:open_vibrance/services/storage_service.dart';
import 'package:open_vibrance/transcription/elevenlabs_transcription_provider.dart';
import 'package:open_vibrance/theme/app_colors.dart';
import 'package:open_vibrance/theme/app_styles.dart';
import 'package:open_vibrance/widgets/constants.dart';
import 'package:open_vibrance/transcription/types.dart';

class ElevenLabsSettingsWidget extends StatefulWidget {
  const ElevenLabsSettingsWidget({super.key});

  @override
  State<ElevenLabsSettingsWidget> createState() =>
      _ElevenLabsSettingsWidgetState();
}

class _ElevenLabsSettingsWidgetState extends State<ElevenLabsSettingsWidget> {
  final TextEditingController _apiKeyController = TextEditingController();
  ElevenLabsModel _selectedElevenLabsModel = ElevenLabsModel.scribeV1;

  @override
  void initState() {
    super.initState();
    _loadElevenLabsApiKey();
    _loadElevenLabsModel();
  }

  Future<void> _loadElevenLabsApiKey() async {
    final key = await SecureStorageService().readValue(
      StorageKey.elevenLabsApiKey.key,
    );
    if (key != null && mounted) {
      setState(() {
        _apiKeyController.text = key;
      });
    }
  }

  Future<void> _loadElevenLabsModel() async {
    final modelId = await SecureStorageService().readValue(
      StorageKey.elevenLabsModel.key,
    );
    if (mounted) {
      setState(() {
        _selectedElevenLabsModel = ElevenLabsModelExtension.fromKey(modelId);
      });
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  void _onElevenLabsApiKeyChanged(String value) {
    SecureStorageService().saveValue(StorageKey.elevenLabsApiKey.key, value);
  }

  void _onElevenLabsModelChanged(ElevenLabsModel? model) {
    if (model == null) {
      return;
    }
    SecureStorageService().saveValue(
      StorageKey.elevenLabsModel.key,
      model.modelId,
    );
    if (mounted) {
      setState(() {
        _selectedElevenLabsModel = model;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ElevenLabs API key',
          style: TextStyle(color: AppColors.textSecondary, fontSize: kFontSizeMd, fontWeight: FontWeight.w500),
        ),
        SizedBox(height: 8),
        Text(
          'Uses Scribe model from ElevenLabs (subscription required)',
          style: TextStyle(color: AppColors.textHint, fontSize: kFontSizeSm),
        ),
        SizedBox(height: 8),
        TextField(
          controller: _apiKeyController,
          decoration: InputDecoration(hintText: 'Enter your API key'),
          style: TextStyle(color: AppColors.textPrimary),
          onChanged: _onElevenLabsApiKeyChanged,
        ),
        SizedBox(height: 32),
        Text(
          'ElevenLabs Model',
          style: TextStyle(color: AppColors.textSecondary, fontSize: kFontSizeMd, fontWeight: FontWeight.w500),
        ),
        SizedBox(height: 8),
        Text(
          'Select the model to use for transcription',
          style: TextStyle(color: AppColors.textHint, fontSize: kFontSizeSm),
        ),
        SizedBox(height: 8),
        DropdownButtonHideUnderline(
          child: DropdownButton2<ElevenLabsModel>(
            value: _selectedElevenLabsModel,
            onChanged: _onElevenLabsModelChanged,
            items: ElevenLabsModel.values.map(
              (model) => DropdownMenuItem<ElevenLabsModel>(
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
      ],
    );
  }
}
