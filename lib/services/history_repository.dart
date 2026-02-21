import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:open_vibrance/models/history_entry.dart';

class HistoryRepository {
  static const int maxEntries = 500;
  static const String _historyFileName = 'transcription_history.json';
  static const String _recordingsDir = 'recordings';

  List<HistoryEntry>? _cache;

  Future<String> _getBasePath() async {
    final dir = await getApplicationSupportDirectory();
    return dir.path;
  }

  Future<String> _getRecordingsPath() async {
    final base = await _getBasePath();
    final dir = Directory(p.join(base, _recordingsDir));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  Future<String> generateRecordingPath() async {
    final recordingsDir = await _getRecordingsPath();
    final now = DateTime.now();
    final stamp = '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}'
        '_${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}'
        '_${now.millisecond.toString().padLeft(3, '0')}';
    return p.join(recordingsDir, 'recording_$stamp.wav');
  }

  String idFromPath(String path) => p.basenameWithoutExtension(path);

  Future<File> _getHistoryFile() async {
    final base = await _getBasePath();
    return File(p.join(base, _historyFileName));
  }

  Future<List<HistoryEntry>> loadEntries() async {
    if (_cache != null) return _cache!;
    final file = await _getHistoryFile();
    if (!await file.exists()) {
      _cache = [];
      return _cache!;
    }
    final jsonStr = await file.readAsString();
    final List<dynamic> jsonList = jsonDecode(jsonStr);
    _cache = jsonList.map((e) => HistoryEntry.fromJson(e)).toList();
    return _cache!;
  }

  Future<void> _saveEntries(List<HistoryEntry> entries) async {
    _cache = entries;
    final file = await _getHistoryFile();
    final jsonStr = jsonEncode(entries.map((e) => e.toJson()).toList());
    await file.writeAsString(jsonStr);
  }

  Future<void> addEntry(HistoryEntry entry) async {
    final entries = await loadEntries();
    entries.insert(0, entry);
    await _saveEntries(entries);
  }

  Future<void> cleanup() async {
    final entries = await loadEntries();
    if (entries.length <= maxEntries) return;

    final kept = entries.sublist(0, maxEntries);
    final removed = entries.sublist(maxEntries);

    final keptPaths = kept.map((e) => e.audioFilePath).toSet();

    for (final entry in removed) {
      if (!keptPaths.contains(entry.audioFilePath)) {
        final file = File(entry.audioFilePath);
        if (await file.exists()) {
          await file.delete();
        }
      }
    }

    await _saveEntries(kept);
  }
}
