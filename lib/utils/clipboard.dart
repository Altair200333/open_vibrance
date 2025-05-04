import 'dart:io';

/// Paste current clipboard content.
Future<void> pasteContent() async {
  if (Platform.isWindows) {
    await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      '[void][System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms");'
          '[System.Windows.Forms.SendKeys]::SendWait("^v");',
    ]);
  } else if (Platform.isMacOS) {
    await Process.run('osascript', [
      '-e',
      'tell application "System Events" to keystroke "v" using command down',
    ]);
  } else if (Platform.isLinux) {
    await Process.run('xdotool', ['key', 'ctrl+v']);
  } else {
    throw UnsupportedError('Paste shortcut not implemented for this OS');
  }
}
