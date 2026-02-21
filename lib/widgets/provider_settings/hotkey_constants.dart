import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:flutter/services.dart';

const basicKeyOptions = <PhysicalKeyboardKey>[
  PhysicalKeyboardKey.keyA,
  PhysicalKeyboardKey.keyB,
  PhysicalKeyboardKey.keyC,
  PhysicalKeyboardKey.keyD,
  PhysicalKeyboardKey.keyE,
  PhysicalKeyboardKey.keyF,
  PhysicalKeyboardKey.keyG,
  PhysicalKeyboardKey.keyH,
  PhysicalKeyboardKey.keyI,
  PhysicalKeyboardKey.keyJ,
  PhysicalKeyboardKey.keyK,
  PhysicalKeyboardKey.keyL,
  PhysicalKeyboardKey.keyM,
  PhysicalKeyboardKey.keyN,
  PhysicalKeyboardKey.keyO,
  PhysicalKeyboardKey.keyP,
  PhysicalKeyboardKey.keyQ,
  PhysicalKeyboardKey.keyR,
  PhysicalKeyboardKey.keyS,
  PhysicalKeyboardKey.keyT,
  PhysicalKeyboardKey.keyU,
  PhysicalKeyboardKey.keyV,
  PhysicalKeyboardKey.keyW,
  PhysicalKeyboardKey.keyX,
  PhysicalKeyboardKey.keyY,
  PhysicalKeyboardKey.keyZ,
  PhysicalKeyboardKey.digit0,
  PhysicalKeyboardKey.digit1,
  PhysicalKeyboardKey.digit2,
  PhysicalKeyboardKey.digit3,
  PhysicalKeyboardKey.digit4,
  PhysicalKeyboardKey.digit5,
  PhysicalKeyboardKey.digit6,
  PhysicalKeyboardKey.digit7,
  PhysicalKeyboardKey.digit8,
  PhysicalKeyboardKey.digit9,
  PhysicalKeyboardKey.f1,
  PhysicalKeyboardKey.f2,
  PhysicalKeyboardKey.f3,
  PhysicalKeyboardKey.f4,
  PhysicalKeyboardKey.f5,
  PhysicalKeyboardKey.f6,
  PhysicalKeyboardKey.f7,
  PhysicalKeyboardKey.f8,
  PhysicalKeyboardKey.f9,
  PhysicalKeyboardKey.f10,
  PhysicalKeyboardKey.f11,
  PhysicalKeyboardKey.f12,
  PhysicalKeyboardKey.space,
  PhysicalKeyboardKey.enter,
  PhysicalKeyboardKey.tab,
  PhysicalKeyboardKey.backspace,
  PhysicalKeyboardKey.delete,
  PhysicalKeyboardKey.escape,
  PhysicalKeyboardKey.home,
  PhysicalKeyboardKey.end,
  PhysicalKeyboardKey.pageUp,
  PhysicalKeyboardKey.pageDown,
  PhysicalKeyboardKey.arrowUp,
  PhysicalKeyboardKey.arrowDown,
  PhysicalKeyboardKey.arrowLeft,
  PhysicalKeyboardKey.arrowRight,
];

const modifierLabels = <HotKeyModifier, String>{
  HotKeyModifier.alt: 'Alt',
  HotKeyModifier.control: 'Ctrl',
  HotKeyModifier.shift: 'Shift',
  HotKeyModifier.meta: 'Meta',
};

/// Maps physical modifier keys (left/right variants) to HotKeyModifier.
final physicalKeyToModifier = <PhysicalKeyboardKey, HotKeyModifier>{
  PhysicalKeyboardKey.altLeft: HotKeyModifier.alt,
  PhysicalKeyboardKey.altRight: HotKeyModifier.alt,
  PhysicalKeyboardKey.controlLeft: HotKeyModifier.control,
  PhysicalKeyboardKey.controlRight: HotKeyModifier.control,
  PhysicalKeyboardKey.shiftLeft: HotKeyModifier.shift,
  PhysicalKeyboardKey.shiftRight: HotKeyModifier.shift,
  PhysicalKeyboardKey.metaLeft: HotKeyModifier.meta,
  PhysicalKeyboardKey.metaRight: HotKeyModifier.meta,
};

/// Returns true if [key] is a modifier key (Alt, Ctrl, Shift, Meta).
bool isModifierKey(PhysicalKeyboardKey key) {
  return physicalKeyToModifier.containsKey(key);
}

/// Looks up a PhysicalKeyboardKey by its keyLabel string.
PhysicalKeyboardKey? keyLabelToPhysicalKey(String label) {
  final lower = label.toLowerCase();
  for (final key in basicKeyOptions) {
    if ((key.keyLabel).toLowerCase() == lower) {
      return key;
    }
  }
  return null;
}
