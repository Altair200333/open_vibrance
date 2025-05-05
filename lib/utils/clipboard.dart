import 'dart:io';

import 'package:flutter/services.dart';
import 'package:keypress_simulator/keypress_simulator.dart';

Future<ProcessResult> _run(String cmd, List<String> args) =>
    Process.run(cmd, args, runInShell: false);

Future<bool> _existsLinux(String exe) async =>
    (await Process.run('which', [exe])).exitCode == 0;

_getCtrlKey() {
  if (Platform.isWindows) {
    return ModifierKey.controlModifier;
  }
  return ModifierKey.metaModifier;
}

Future<void> pasteContent() async {
  // keyPressSimulator works on windows and macos, but not on linux
  if (Platform.isWindows || Platform.isMacOS) {
    await keyPressSimulator.simulateKeyDown(PhysicalKeyboardKey.keyV, [
      _getCtrlKey(),
    ]);

    await Future.delayed(Duration(milliseconds: 100));

    await keyPressSimulator.simulateKeyUp(PhysicalKeyboardKey.keyV, [
      _getCtrlKey(),
    ]);

    return;
  }

  // TODO test this
  if (Platform.isLinux) {
    if (await _existsLinux('xdotool')) {
      await _run('xdotool', ['key', '--clearmodifiers', 'ctrl+v']);
      return;
    }
    if (await _existsLinux('wtype')) {
      await _run('wtype', ['-M', 'ctrl', '-k', 'v', '-m', 'ctrl']);
      return;
    }
    if (await _existsLinux('ydotool')) {
      await _run('ydotool', ['key', 'Ctrl+V']);
      return;
    }

    throw UnsupportedError('Need xdotool (X11) or wtype/ydotool (Wayland)');
  }

  throw UnsupportedError('Paste shortcut not implemented for this OS');
}
