import 'package:flutter/material.dart';
import 'package:open_vibrance/theme/app_colors.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:open_vibrance/services/hotkey_repository.dart';
import 'package:open_vibrance/widgets/provider_settings/hotkey_constants.dart';

class HotkeysSettingsView extends StatefulWidget {
  final void Function(HotKeyModifier modifier, List<PhysicalKeyboardKey> keys)
  onHotkeyChanged;

  const HotkeysSettingsView({super.key, required this.onHotkeyChanged});

  @override
  State<HotkeysSettingsView> createState() => _HotkeysSettingsViewState();
}

class _HotkeysSettingsViewState extends State<HotkeysSettingsView> {
  HotKeyModifier selectedModifier = HotKeyModifier.alt;
  PhysicalKeyboardKey selectedKey = PhysicalKeyboardKey.keyQ;

  @override
  void initState() {
    super.initState();
    _loadHotkeySettings();
  }

  Future<void> _loadHotkeySettings() async {
    final combo = await HotkeyRepository().readHotkey();
    if (mounted && combo != null) {
      setState(() {
        selectedModifier = combo.modifier;
        if (combo.keys.isNotEmpty) selectedKey = combo.keys.first;
      });
    }
    widget.onHotkeyChanged(selectedModifier, [selectedKey]);
  }

  void _saveAndNotify() {
    final combo = HotkeyCombo(modifier: selectedModifier, keys: [selectedKey]);
    HotkeyRepository().saveHotkey(combo);
    widget.onHotkeyChanged(selectedModifier, [selectedKey]);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.gray700,
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Record hotkey:',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 100,
                child: DropdownButtonFormField<HotKeyModifier>(
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 4),
                  ),
                  dropdownColor: AppColors.gray700,
                  style: TextStyle(color: Colors.white),
                  iconEnabledColor: Colors.white,
                  value: selectedModifier,
                  items:
                      modifierLabels.entries
                          .map(
                            (entry) => DropdownMenuItem<HotKeyModifier>(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                          )
                          .toList(),
                  onChanged: (modifier) {
                    if (modifier != null) {
                      setState(() => selectedModifier = modifier);
                      _saveAndNotify();
                    }
                  },
                ),
              ),
              SizedBox(width: 16),
              Container(
                padding: EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.transparent, width: 2),
                ),
                child: Icon(Icons.add, color: Colors.white, size: 16),
              ),
              SizedBox(width: 16),
              SizedBox(
                width: 100,
                child: DropdownButton<PhysicalKeyboardKey>(
                  dropdownColor: AppColors.gray700,
                  style: TextStyle(color: Colors.white),
                  iconEnabledColor: Colors.white,
                  underline: SizedBox(),
                  value: selectedKey,
                  items:
                      basicKeyOptions
                          .map(
                            (key) => DropdownMenuItem<PhysicalKeyboardKey>(
                              value: key,
                              child: Text(key.keyLabel ?? ''),
                            ),
                          )
                          .toList(),
                  onChanged: (key) {
                    if (key != null) {
                      setState(() => selectedKey = key);
                      _saveAndNotify();
                    }
                  },
                ),
              ),
            ],
          ),
          SizedBox(height: 24),
          Row(
            children: [
              Text(
                'Selected hotkey:',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(width: 8),
              Text(
                _getHotkeyCombination(),
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getHotkeyCombination() {
    return HotkeyCombo(
      modifier: selectedModifier,
      keys: [selectedKey],
    ).toString();
  }
}
