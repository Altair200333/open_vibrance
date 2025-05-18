import 'package:flutter/material.dart';
import 'package:open_vibrance/services/storage_service.dart';
import 'package:open_vibrance/transcription/types.dart';
import 'package:open_vibrance/theme/app_colors.dart';
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
          onChanged: _handleProviderChange,
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
