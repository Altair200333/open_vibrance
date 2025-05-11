import 'package:flutter/material.dart';
import 'package:open_vibrance/services/storage_service.dart';
import 'package:open_vibrance/transcription/elevenlabs_transcription_provider.dart';
import 'package:open_vibrance/theme/app_colors.dart';
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
}
