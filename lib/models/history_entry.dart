class HistoryEntry {
  final String id;
  final String audioFilePath;
  final String? transcription;
  final DateTime timestamp;
  final bool success;

  HistoryEntry({
    required this.id,
    required this.audioFilePath,
    this.transcription,
    required this.timestamp,
    required this.success,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'audioFilePath': audioFilePath,
    'transcription': transcription,
    'timestamp': timestamp.toIso8601String(),
    'success': success,
  };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
    id: json['id'] as String,
    audioFilePath: json['audioFilePath'] as String,
    transcription: json['transcription'] as String?,
    timestamp: DateTime.parse(json['timestamp'] as String),
    success: json['success'] as bool,
  );
}
