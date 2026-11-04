import 'package:flutter/material.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:open_vibrance/services/composite_transcription_merger.dart';
import 'package:open_vibrance/services/openrouter_chat.dart';
import 'package:open_vibrance/services/storage_service.dart';
import 'package:open_vibrance/theme/app_color_theme.dart';
import 'package:open_vibrance/theme/app_styles.dart';
import 'package:open_vibrance/transcription/composite_config.dart';
import 'package:open_vibrance/transcription/types.dart';
import 'package:open_vibrance/widgets/constants.dart';
import 'package:open_vibrance/widgets/hoverable_icon.dart';
import 'package:open_vibrance/widgets/provider_settings/secret_api_key_field.dart';

class CompositeSettingsWidget extends StatefulWidget {
  const CompositeSettingsWidget({super.key});

  @override
  State<CompositeSettingsWidget> createState() =>
      _CompositeSettingsWidgetState();
}

class _CompositeSettingsWidgetState extends State<CompositeSettingsWidget> {
  final TextEditingController _openRouterApiKeyController =
      TextEditingController();
  List<CompositeSlot> _slots = CompositeConfig.defaultSlots;
  MergerModel _mergerModel = MergerModel.deepseekV41Flash;
  Set<TranscriptionProviderKey> _providersWithKey = {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final storage = SecureStorageService();
    final config = await CompositeConfig.load(storage);
    final openRouterKey = await readOpenRouterApiKey(storage);
    final withKey = <TranscriptionProviderKey>{
      if (openRouterKey != null) TranscriptionProviderKey.google,
    };
    for (final provider in [
      TranscriptionProviderKey.openai,
      TranscriptionProviderKey.elevenlabs,
    ]) {
      final key = await storage.readValue(
        CompositeSlot.defaultFor(provider).apiKeyStorageKey.key,
      );
      if (key != null && key.trim().isNotEmpty) withKey.add(provider);
    }
    if (mounted) {
      setState(() {
        _slots = config.slots;
        _mergerModel = config.mergerModel;
        _providersWithKey = withKey;
        _openRouterApiKeyController.text = openRouterKey ?? '';
        _loaded = true;
      });
    }
  }

  @override
  void dispose() {
    _openRouterApiKeyController.dispose();
    super.dispose();
  }

  void _updateSlots(List<CompositeSlot> slots) {
    setState(() => _slots = slots);
    SecureStorageService().saveValue(
      StorageKey.compositeSlots.key,
      CompositeConfig.encodeSlots(slots),
    );
  }

  void _replaceSlot(int index, CompositeSlot slot) {
    _updateSlots([..._slots]..[index] = slot);
  }

  void _onMergerModelChanged(MergerModel? model) {
    if (model == null) return;
    setState(() => _mergerModel = model);
    SecureStorageService().saveValue(
      StorageKey.compositeMergerModel.key,
      model.modelId,
    );
  }

  void _onOpenRouterApiKeyChanged(String value) {
    setState(() {
      if (value.trim().isEmpty) {
        _providersWithKey.remove(TranscriptionProviderKey.google);
      } else {
        _providersWithKey.add(TranscriptionProviderKey.google);
      }
    });
    saveOpenRouterApiKey(SecureStorageService(), value);
  }

  Widget _dropdown<T>({
    required T value,
    required List<(T, String)> items,
    required ValueChanged<T?> onChanged,
  }) {
    final colors = context.colors;
    return DropdownButtonHideUnderline(
      child: DropdownButton2<T>(
        isExpanded: true,
        value: value,
        onChanged: onChanged,
        items: [
          for (final (itemValue, label) in items)
            DropdownMenuItem<T>(
              value: itemValue,
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: kFontSizeLg,
                ),
              ),
            ),
        ],
        buttonStyleData: AppStyles.dropdownButton(colors),
        dropdownStyleData: AppStyles.dropdownMenu(colors),
        iconStyleData: AppStyles.dropdownIcon(colors),
        menuItemStyleData: AppStyles.dropdownMenuItem(colors),
      ),
    );
  }

  Widget _buildSlot(int index) {
    final colors = context.colors;
    final slot = _slots[index];
    final hasKey = _providersWithKey.contains(slot.provider);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 52,
                child: Text(
                  'Slot ${index + 1}',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: kFontSizeSm,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: _dropdown<TranscriptionProviderKey>(
                  value: slot.provider,
                  items: [
                    for (final p in CompositeSlot.providers) (p, p.displayName),
                  ],
                  onChanged: (provider) {
                    if (provider == null || provider == slot.provider) return;
                    _replaceSlot(index, CompositeSlot.defaultFor(provider));
                  },
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: _dropdown<String>(
                  value: slot.modelId,
                  items: CompositeSlot.modelsFor(slot.provider),
                  onChanged: (modelId) {
                    if (modelId == null) return;
                    _replaceSlot(index, CompositeSlot(slot.provider, modelId));
                  },
                ),
              ),
              SizedBox(
                width: 36,
                child:
                    _slots.length > 1
                        ? HoverableIcon(
                          iconData: LucideIcons.x,
                          tooltip: 'Remove slot',
                          size: 18,
                          hoverColor: colors.errorText,
                          onTap:
                              () => _updateSlots([..._slots]..removeAt(index)),
                        )
                        : null,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 52, top: 4),
            child: Text(
              !hasKey
                  ? slot.provider == TranscriptionProviderKey.google
                      ? 'Enter the OpenRouter API key below'
                      : 'Configure API key in ${slot.provider.displayName} '
                          'settings'
                  : slot.isRealtime
                  ? 'Streams live while you record'
                  : 'Transcribes the saved recording',
              style: TextStyle(
                color: hasKey ? colors.textHint : colors.errorText,
                fontSize: kFontSizeXs,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (!_loaded) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Transcription Providers',
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: kFontSizeMd,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Every slot transcribes the same recording; the results are merged '
          'into one text. Slots use the keys and prompt of their providers.',
          style: TextStyle(color: colors.textHint, fontSize: kFontSizeSm),
        ),
        SizedBox(height: 12),
        for (var i = 0; i < _slots.length; i++) _buildSlot(i),
        if (_slots.length < CompositeConfig.maxSlots)
          TextButton.icon(
            onPressed:
                () => _updateSlots([
                  ..._slots,
                  CompositeSlot.defaultFor(TranscriptionProviderKey.google),
                ]),
            icon: Icon(LucideIcons.plus, size: 16, color: colors.accent),
            label: Text(
              'Add Provider',
              style: TextStyle(color: colors.accent, fontSize: kFontSizeMd),
            ),
          ),
        SizedBox(height: 24),
        Text(
          'Merger Model',
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: kFontSizeMd,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Fuses the slot transcripts and removes filler sounds',
          style: TextStyle(color: colors.textHint, fontSize: kFontSizeSm),
        ),
        SizedBox(height: 8),
        _dropdown<MergerModel>(
          value: _mergerModel,
          items: [for (final m in MergerModel.values) (m, m.displayName)],
          onChanged: _onMergerModelChanged,
        ),
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
          'Used by the merger and by Google slots. Without it, the first '
          'successful slot is used as is.',
          style: TextStyle(color: colors.textHint, fontSize: kFontSizeSm),
        ),
        SizedBox(height: 8),
        SecretApiKeyField(
          controller: _openRouterApiKeyController,
          hintText: 'Enter your OpenRouter API key',
          onChanged: _onOpenRouterApiKeyChanged,
        ),
      ],
    );
  }
}
