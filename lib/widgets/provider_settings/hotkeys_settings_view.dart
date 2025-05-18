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
  List<PhysicalKeyboardKey> selectedKeys = [PhysicalKeyboardKey.keyQ];

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
        selectedKeys = combo.keys;
      });
    }
    widget.onHotkeyChanged(selectedModifier, selectedKeys);
  }

  void _saveAndNotify() {
    final combo = HotkeyCombo(modifier: selectedModifier, keys: selectedKeys);
    HotkeyRepository().saveHotkey(combo);
    widget.onHotkeyChanged(selectedModifier, selectedKeys);
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
          Text(
            'Modifier',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 4),
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
          SizedBox(height: 12),
          Text(
            'Keys',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < selectedKeys.length; i++) ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 100,
                      child: DropdownButton<PhysicalKeyboardKey>(
                        dropdownColor: AppColors.gray700,
                        style: TextStyle(color: Colors.white),
                        iconEnabledColor: Colors.white,
                        underline: SizedBox(),
                        value: selectedKeys[i],
                        items:
                            basicKeyOptions
                                .map(
                                  (key) =>
                                      DropdownMenuItem<PhysicalKeyboardKey>(
                                        value: key,
                                        child: Text(key.keyLabel ?? ''),
                                      ),
                                )
                                .toList(),
                        onChanged: (key) {
                          if (key != null) {
                            setState(() => selectedKeys[i] = key);
                            _saveAndNotify();
                          }
                        },
                      ),
                    ),
                    if (selectedKeys.length > 1)
                      IconButton(
                        iconSize: 16,
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints(),
                        icon: Icon(
                          Icons.close,
                          color: Colors.white.withOpacity(0.7),
                        ),
                        onPressed:
                            () => setState(() {
                              selectedKeys.removeAt(i);
                              _saveAndNotify();
                            }),
                      ),
                  ],
                ),
                SizedBox(height: 0),
              ],
              ElevatedButton.icon(
                onPressed:
                    () => setState(() {
                      selectedKeys.add(basicKeyOptions.first);
                      _saveAndNotify();
                    }),
                icon: Icon(Icons.add, size: 16, color: Colors.white),
                label: Text('Add key', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white24,
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size(32, 32),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
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
      keys: selectedKeys,
    ).toString();
  }
}
