import 'package:flutter/material.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:open_vibrance/services/storage_service.dart';
import 'package:open_vibrance/transcription/elevenlabs_transcription_provider.dart';
import 'package:open_vibrance/theme/app_color_theme.dart';
import 'package:open_vibrance/theme/app_styles.dart';
import 'package:open_vibrance/widgets/constants.dart';
import 'package:open_vibrance/transcription/types.dart';
import 'package:open_vibrance/utils/common.dart';

class ElevenLabsSettingsWidget extends StatefulWidget {
  const ElevenLabsSettingsWidget({super.key});

  @override
  State<ElevenLabsSettingsWidget> createState() =>
      _ElevenLabsSettingsWidgetState();
}

class _ElevenLabsSettingsWidgetState extends State<ElevenLabsSettingsWidget> {
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _openRouterApiKeyController =
      TextEditingController();
  ElevenLabsModel _selectedElevenLabsModel = ElevenLabsModel.scribeV1;
  bool _transcriptionFilteringEnabled = false;
  bool _transcriptionFilteringSettingsLoaded = false;
  bool _savingFilteringEnabled = false;
  int _openRouterApiKeyWriteGeneration = 0;
  String? _transcriptionFilteringSettingsError;

  @override
  void initState() {
    super.initState();
    _loadElevenLabsApiKey();
    _loadElevenLabsModel();
    _loadTranscriptionFilteringSettings();
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

  Future<void> _loadTranscriptionFilteringSettings() async {
    try {
      final enabled = await SecureStorageService().readValue(
        StorageKey.elevenLabsRealtimeFilteringEnabled.key,
      );
      final openRouterApiKey = await SecureStorageService().readValue(
        StorageKey.openRouterApiKey.key,
      );
      if (mounted) {
        setState(() {
          _transcriptionFilteringEnabled = enabled == 'true';
          _openRouterApiKeyController.text = openRouterApiKey ?? '';
          _transcriptionFilteringSettingsLoaded = true;
        });
      }
    } catch (e) {
      dprint(
        'Failed to load transcription filtering settings (${e.runtimeType})',
      );
      if (mounted) {
        setState(() {
          _transcriptionFilteringSettingsLoaded = true;
          _transcriptionFilteringSettingsError =
              'Could not load transcription filtering settings.';
        });
      }
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _openRouterApiKeyController.dispose();
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

  Future<void> _onTranscriptionFilteringChanged(bool? enabled) async {
    if (enabled == null || _savingFilteringEnabled) {
      return;
    }
    if (mounted) {
      setState(() {
        _savingFilteringEnabled = true;
        _transcriptionFilteringSettingsError = null;
      });
    }
    try {
      await SecureStorageService().saveValue(
        StorageKey.elevenLabsRealtimeFilteringEnabled.key,
        enabled.toString(),
      );
      if (mounted) {
        setState(() {
          _transcriptionFilteringEnabled = enabled;
          _savingFilteringEnabled = false;
        });
      }
    } catch (e) {
      dprint(
        'Failed to save transcription filtering setting (${e.runtimeType})',
      );
      if (mounted) {
        setState(() {
          _savingFilteringEnabled = false;
          _transcriptionFilteringSettingsError =
              'Could not save transcription filtering settings.';
        });
      }
    }
  }

  void _onOpenRouterApiKeyChanged(String value) {
    final generation = ++_openRouterApiKeyWriteGeneration;
    if (_transcriptionFilteringSettingsError != null && mounted) {
      setState(() => _transcriptionFilteringSettingsError = null);
    }
    _saveOpenRouterApiKey(value, generation);
  }

  Future<void> _saveOpenRouterApiKey(String apiKey, int generation) async {
    try {
      await SecureStorageService().saveValue(
        StorageKey.openRouterApiKey.key,
        apiKey,
      );
      if (mounted && generation == _openRouterApiKeyWriteGeneration) {
        setState(() => _transcriptionFilteringSettingsError = null);
      }
    } catch (e) {
      dprint('Failed to save OpenRouter API key (${e.runtimeType})');
      if (mounted && generation == _openRouterApiKeyWriteGeneration) {
        setState(() {
          _transcriptionFilteringSettingsError =
              'Could not save the OpenRouter API key.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ElevenLabs API key',
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: kFontSizeMd,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Uses Scribe model from ElevenLabs (subscription required)',
          style: TextStyle(color: colors.textHint, fontSize: kFontSizeSm),
        ),
        SizedBox(height: 8),
        TextField(
          controller: _apiKeyController,
          decoration: InputDecoration(hintText: 'Enter your API key'),
          style: TextStyle(color: colors.textPrimary),
          onChanged: _onElevenLabsApiKeyChanged,
        ),
        SizedBox(height: 32),
        Text(
          'ElevenLabs Model',
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
          child: DropdownButton2<ElevenLabsModel>(
            value: _selectedElevenLabsModel,
            onChanged: _onElevenLabsModelChanged,
            items:
                ElevenLabsModel.values
                    .map(
                      (model) => DropdownMenuItem<ElevenLabsModel>(
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
        if (_selectedElevenLabsModel.isRealtime &&
            _transcriptionFilteringSettingsLoaded) ...[
          SizedBox(height: 32),
          CheckboxListTile(
            value: _transcriptionFilteringEnabled,
            onChanged:
                _savingFilteringEnabled
                    ? null
                    : _onTranscriptionFilteringChanged,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: colors.accent,
            dense: true,
            title: Text(
              'Enable Transcription Filtering',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: kFontSizeMd,
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: Text(
              'Remove filler sounds, stutters, and accidental repetitions '
              'with DeepSeek V4 Flash',
              style: TextStyle(color: colors.textHint, fontSize: kFontSizeSm),
            ),
          ),
          if (_transcriptionFilteringSettingsError case final error?) ...[
            SizedBox(height: 8),
            Text(
              error,
              style: TextStyle(color: colors.errorText, fontSize: kFontSizeSm),
            ),
          ],
          if (_transcriptionFilteringEnabled) ...[
            SizedBox(height: 16),
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
              'The final transcript is sent to OpenRouter for cloud '
              'filtering. The key is stored securely on this device.',
              style: TextStyle(color: colors.textHint, fontSize: kFontSizeSm),
            ),
            SizedBox(height: 8),
            TextField(
              controller: _openRouterApiKeyController,
              decoration: InputDecoration(
                hintText: 'Enter your OpenRouter API key',
              ),
              style: TextStyle(color: colors.textPrimary),
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              onChanged: _onOpenRouterApiKeyChanged,
            ),
          ],
        ],
      ],
    );
  }
}
