import 'package:flutter/material.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:open_vibrance/services/storage_service.dart';
import 'package:open_vibrance/transcription/types.dart';
import 'package:open_vibrance/theme/app_colors.dart';
import 'package:open_vibrance/theme/app_styles.dart';
import 'package:open_vibrance/widgets/constants.dart';
import 'package:open_vibrance/widgets/provider_settings/elevenlabs_settings_widget.dart';
import 'package:open_vibrance/widgets/provider_settings/openai_settings_widget.dart';
import 'package:open_vibrance/widgets/provider_settings/custom_settings_widget.dart';

class TranscriptionProviderConfigurationView extends StatefulWidget {
  const TranscriptionProviderConfigurationView({super.key});

  @override
  State<TranscriptionProviderConfigurationView> createState() =>
      _TranscriptionProviderConfigurationViewState();
}

class _TranscriptionProviderConfigurationViewState
    extends State<TranscriptionProviderConfigurationView> {
  TranscriptionProviderKey _selectedProvider =
      TranscriptionProviderKey.elevenlabs;

  @override
  void initState() {
    super.initState();
    _loadProvider();
  }

  Future<void> _loadProvider() async {
    final key = await SecureStorageService().readValue(
      StorageKey.transcriptionProvider.key,
    );
    if (mounted) {
      setState(() {
        _selectedProvider = TranscriptionProviderKeyExtension.fromKey(key);
      });
    }
  }

  void _handleProviderChange(TranscriptionProviderKey? provider) {
    if (provider == null) {
      return;
    }
    SecureStorageService().saveValue(
      StorageKey.transcriptionProvider.key,
      provider.key,
    );
    if (mounted) {
      setState(() {
        _selectedProvider = provider;
      });
    }
  }

  Widget _buildProviderSelector(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Transcription Provider',
          style: TextStyle(color: AppColors.textSecondary, fontSize: kFontSizeMd, fontWeight: FontWeight.w500),
        ),
        SizedBox(height: 8),
        DropdownButtonHideUnderline(
          child: DropdownButton2<TranscriptionProviderKey>(
            value: _selectedProvider,
            onChanged: _handleProviderChange,
            items: TranscriptionProviderKey.values.map(
              (provider) => DropdownMenuItem<TranscriptionProviderKey>(
                value: provider,
                child: Text(
                  provider.displayName,
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

  Widget _buildProviderSettings(BuildContext context) {
    switch (_selectedProvider) {
      case TranscriptionProviderKey.elevenlabs:
        return const ElevenLabsSettingsWidget();
      case TranscriptionProviderKey.openai:
        return const OpenAiSettingsWidget();
      case TranscriptionProviderKey.custom:
        return const CustomSettingsWidget();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildProviderSelector(context),
        SizedBox(height: 16),
        _buildProviderSettings(context),
      ],
    );
  }
}
