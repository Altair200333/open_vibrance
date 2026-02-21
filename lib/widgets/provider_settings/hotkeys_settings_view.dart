import 'package:flutter/material.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
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
    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Record hotkey:',
            style: TextStyle(
              color: AppColors.zinc400,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 16),
          Row(
            children: [
              DropdownButtonHideUnderline(
                child: DropdownButton2<HotKeyModifier>(
                  value: selectedModifier,
                  onChanged: (modifier) {
                    if (modifier != null) {
                      setState(() => selectedModifier = modifier);
                      _saveAndNotify();
                    }
                  },
                  items: modifierLabels.entries.map(
                    (entry) => DropdownMenuItem<HotKeyModifier>(
                      value: entry.key,
                      child: Text(
                        entry.value,
                        style: TextStyle(color: AppColors.zinc300, fontSize: 14),
                      ),
                    ),
                  ).toList(),
                  buttonStyleData: ButtonStyleData(
                    height: 40,
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppColors.zinc800,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.zinc700),
                    ),
                  ),
                  dropdownStyleData: DropdownStyleData(
                    decoration: BoxDecoration(
                      color: AppColors.zinc800,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.zinc700),
                    ),
                    elevation: 0,
                  ),
                  iconStyleData: IconStyleData(
                    icon: Icon(Icons.keyboard_arrow_down_rounded),
                    iconSize: 20,
                    iconEnabledColor: AppColors.zinc400,
                  ),
                  menuItemStyleData: MenuItemStyleData(
                    height: 40,
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    overlayColor: WidgetStatePropertyAll(AppColors.zinc700),
                  ),
                ),
              ),
              SizedBox(width: 12),
              Icon(Icons.add, color: AppColors.zinc500, size: 14),
              SizedBox(width: 12),
              DropdownButtonHideUnderline(
                child: DropdownButton2<PhysicalKeyboardKey>(
                  value: selectedKey,
                  onChanged: (key) {
                    if (key != null) {
                      setState(() => selectedKey = key);
                      _saveAndNotify();
                    }
                  },
                  items: basicKeyOptions.map(
                    (key) => DropdownMenuItem<PhysicalKeyboardKey>(
                      value: key,
                      child: Text(
                        key.keyLabel,
                        style: TextStyle(color: AppColors.zinc300, fontSize: 14),
                      ),
                    ),
                  ).toList(),
                  buttonStyleData: ButtonStyleData(
                    height: 40,
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppColors.zinc800,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.zinc700),
                    ),
                  ),
                  dropdownStyleData: DropdownStyleData(
                    maxHeight: 300,
                    decoration: BoxDecoration(
                      color: AppColors.zinc800,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.zinc700),
                    ),
                    elevation: 0,
                  ),
                  iconStyleData: IconStyleData(
                    icon: Icon(Icons.keyboard_arrow_down_rounded),
                    iconSize: 20,
                    iconEnabledColor: AppColors.zinc400,
                  ),
                  menuItemStyleData: MenuItemStyleData(
                    height: 40,
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    overlayColor: WidgetStatePropertyAll(AppColors.zinc700),
                  ),
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
                  color: AppColors.zinc400,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(width: 8),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.zinc800,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.zinc700),
                ),
                child: Text(
                  _getHotkeyCombination(),
                  style: TextStyle(color: AppColors.zinc300, fontSize: 13),
                ),
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
