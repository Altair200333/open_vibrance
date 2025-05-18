import 'package:open_vibrance/services/storage_service.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:flutter/services.dart';
import 'package:open_vibrance/transcription/types.dart';
import 'package:open_vibrance/widgets/provider_settings/hotkey_constants.dart';

class HotkeyCombo {
  final HotKeyModifier modifier;
  final List<PhysicalKeyboardKey> keys;

  HotkeyCombo({required this.modifier, required this.keys});

  static const String _separator = ' + ';

  String serialize() {
    final modLabel = modifierLabels[modifier] ?? '';
    final keyLabels = keys.map((k) => k.keyLabel).join(_separator);
    return '$modLabel$_separator$keyLabels';
  }

  @override
  String toString() => serialize();

  static HotkeyCombo deserialize(String serialized) {
    final parts = serialized.split(_separator);
    final modifier = _parseModifier(parts.first);
    final keys = _parseKeys(parts.skip(1));
    return HotkeyCombo(modifier: modifier, keys: keys);
  }

  static HotKeyModifier _parseModifier(String modLabel) {
    return modifierLabels.entries
        .firstWhere(
          (e) => e.value.toLowerCase() == modLabel.toLowerCase(),
          orElse:
              () => MapEntry(
                HotKeyModifier.alt,
                modifierLabels[HotKeyModifier.alt]!,
              ),
        )
        .key;
  }

  static List<PhysicalKeyboardKey> _parseKeys(Iterable<String> keyLabels) {
    return keyLabels.map((label) {
      return basicKeyOptions.firstWhere(
        (k) => (k.keyLabel ?? '').toLowerCase() == label.toLowerCase(),
        orElse: () => basicKeyOptions.first,
      );
    }).toList();
  }
}

class HotkeyRepository {
  final SecureStorageService _storageService;

  HotkeyRepository([SecureStorageService? storage])
    : _storageService = storage ?? SecureStorageService();

  Future<HotkeyCombo?> readHotkey() async {
    final stored = await _storageService.readValue(
      StorageKey.recordingHotkey.key,
    );
    if (stored == null) {
      return null;
    }
    return HotkeyCombo.deserialize(stored);
  }

  Future<void> saveHotkey(HotkeyCombo combo) async {
    final serialized = combo.serialize();
    await _storageService.saveValue(StorageKey.recordingHotkey.key, serialized);
  }
}
