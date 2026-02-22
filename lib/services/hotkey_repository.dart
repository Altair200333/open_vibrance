import 'package:open_vibrance/services/storage_service.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:flutter/services.dart';
import 'package:open_vibrance/transcription/types.dart';
import 'package:open_vibrance/widgets/provider_settings/hotkey_constants.dart';

class HotkeyCombo {
  final List<HotKeyModifier> modifiers;
  final List<PhysicalKeyboardKey> keys;

  HotkeyCombo({required this.modifiers, required this.keys});

  static const String _separator = ' + ';

  String serialize() {
    final modLabels = modifiers.map((m) => modifierLabels[m] ?? '');
    final keyLabels = keys.map((k) => k.keyLabel);
    return [...modLabels, ...keyLabels].join(_separator);
  }

  @override
  String toString() => serialize();

  static HotkeyCombo deserialize(String serialized) {
    final parts = serialized.split(_separator);
    final modifiers = <HotKeyModifier>[];
    final keyParts = <String>[];

    // Greedily match modifier labels first, rest are key labels
    for (final part in parts) {
      final mod = _tryParseModifier(part);
      if (mod != null && keyParts.isEmpty) {
        modifiers.add(mod);
      } else {
        keyParts.add(part);
      }
    }

    // Fallback: if no modifiers found, default to Alt
    if (modifiers.isEmpty) {
      modifiers.add(HotKeyModifier.alt);
    }

    final keys = _parseKeys(keyParts);
    return HotkeyCombo(modifiers: modifiers, keys: keys);
  }

  static HotKeyModifier? _tryParseModifier(String label) {
    for (final entry in modifierLabels.entries) {
      if (entry.value.toLowerCase() == label.toLowerCase()) {
        return entry.key;
      }
    }
    return null;
  }

  static List<PhysicalKeyboardKey> _parseKeys(Iterable<String> keyLabels) {
    return keyLabels.map((label) {
      return keyLabelToPhysicalKey(label) ?? basicKeyOptions.first;
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
