import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'package:open_vibrance/services/storage_service.dart';
import 'package:open_vibrance/transcription/transcription_provider.dart';
import 'package:open_vibrance/transcription/types.dart';
import 'package:open_vibrance/utils/common.dart';
import 'package:open_vibrance/utils/python.dart';

class CustomTranscriptionProvider implements TranscriptionProvider {
  CustomTranscriptionProvider();

  Future<String> _getBase64Audio(Uint8List audioBytes) async {
    return base64Encode(audioBytes);
  }

  @override
  Future<String> transcribe(Uint8List audioBytes) async {
    final pyScript = await SecureStorageService().readValue(
      StorageKey.customPythonScript.key,
    );

    if (pyScript == null) {
      throw Exception('Custom Python script not found');
    }

    final base64Audio = await _getBase64Audio(audioBytes);
    var py = await findPython();
    if (py == null) {
      throw Exception('Python not found');
    }
    dprint("detected python: $py");

    var script = "base64_audio = '$base64Audio'\n\n$pyScript";
    var result = await runPythonScript(py, script);

    dprint("python execution result: $result");
    return result.trim();
  }
}
