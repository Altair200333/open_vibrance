import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as Path;
import 'package:open_vibrance/utils/common.dart';

List<String> getPythonPathVariants() {
  var candidates = const ['python3', 'python', 'py'];
  if (Platform.isWindows) {
    return [...candidates, ...candidates.map((e) => '$e.exe')];
  }
  return candidates;
}

Future<String?> findPython() async {
  var candidates = getPythonPathVariants();
  for (final cmd in candidates) {
    try {
      final proc = await Process.run(
        cmd,
        ['-V'],
        runInShell: true,
        stdoutEncoding: Utf8Codec(),
        stderrEncoding: Utf8Codec(),
      );

      var isPython = proc.stdout is String && proc.stdout.startsWith('Python');

      if (proc.exitCode == 0 && isPython) {
        return cmd;
      }
    } catch (e) {
      dprint("failed to find python: $e");
    }
  }
  return null;
}

Future<String> runPythonScript(String pythonExe, String script) async {
  final tempDir = Directory.systemTemp;
  var tempPath = Path.join(
    tempDir.path,
    'user_${DateTime.now().millisecondsSinceEpoch}.py',
  );
  final tempFile = File(tempPath);
  await tempFile.create();
  await tempFile.writeAsString(script, flush: true);

  try {
    final result = await Process.run(pythonExe, ['-u', tempFile.path]);

    // handle non-zero exit codes by decoding stderr with replacement
    if (result.exitCode != 0) {
      final stderrBytes = result.stderr as List<int>;
      final stderrOutput = utf8.decode(stderrBytes, allowMalformed: true);
      throw Exception('Python code ${result.exitCode}: $stderrOutput');
    }

    return result.stdout;
  } catch (e) {
    dprint("failed to run python script: $e");
    rethrow;
  } finally {
    await tempFile.delete();
  }
}
