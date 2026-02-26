import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:open_vibrance/transcription/streaming_transcription_provider.dart';
import 'package:open_vibrance/transcription/transcription_provider.dart';
import 'package:open_vibrance/utils/common.dart';

class _WavInfo {
  final int channels;
  final int sampleRate;
  final int bitsPerSample;
  final Uint8List pcmBytes;

  const _WavInfo({
    required this.channels,
    required this.sampleRate,
    required this.bitsPerSample,
    required this.pcmBytes,
  });
}

const _supportedSampleRates = {8000, 16000, 22050, 24000, 44100, 48000};

const _errorTypes = {
  'auth_error', 'quota_exceeded', 'rate_limited',
  'session_time_limit_exceeded', 'chunk_size_exceeded',
  'insufficient_audio_activity', 'transcriber_error',
  'input_error', 'queue_overflow',
};

/// Mutable state for a single streaming transcription session.
class _StreamingState {
  _StreamingState({required this.sampleRate});

  final int sampleRate;
  final StringBuffer committed = StringBuffer();
  String latestPartial = '';
  bool sessionStarted = false;
  bool finalCommitSent = false;
  bool isCancelled = false;
  final List<Uint8List> pendingChunks = [];
  Timer? inactivityTimer;
  WebSocket? ws;
  StreamSubscription<Uint8List>? pcmSub;
  late final StreamController<String> controller;

  void cleanup() {
    inactivityTimer?.cancel();
    pcmSub?.cancel();
    try {
      ws?.close();
    } catch (_) {}
  }
}

class ElevenLabsRealtimeTranscriptionProvider
    implements TranscriptionProvider, StreamingTranscriptionProvider {
  final String _apiKey;

  ElevenLabsRealtimeTranscriptionProvider(this._apiKey);

  _WavInfo _parseWav(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);

    if (bytes.length < 12 ||
        String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
      throw Exception('Invalid WAV file: missing RIFF/WAVE header');
    }

    int? channels;
    int? sampleRate;
    int? bitsPerSample;
    Uint8List? pcmBytes;

    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = data.getUint32(offset + 4, Endian.little);
      final chunkDataStart = offset + 8;

      if (chunkId == 'fmt ' && chunkSize >= 16) {
        final audioFormat = data.getUint16(chunkDataStart, Endian.little);
        if (audioFormat != 1) {
          throw Exception(
            'Unsupported WAV format: only PCM (format=1) is supported, '
            'got format=$audioFormat',
          );
        }
        channels = data.getUint16(chunkDataStart + 2, Endian.little);
        sampleRate = data.getUint32(chunkDataStart + 4, Endian.little);
        bitsPerSample = data.getUint16(chunkDataStart + 14, Endian.little);
      } else if (chunkId == 'data') {
        final end = min(chunkDataStart + chunkSize, bytes.length);
        pcmBytes = Uint8List.sublistView(bytes, chunkDataStart, end);
      }

      // Chunks are word-aligned
      offset = chunkDataStart + chunkSize;
      if (chunkSize.isOdd) offset++;
    }

    if (channels == null || sampleRate == null || bitsPerSample == null) {
      throw Exception('Invalid WAV file: missing fmt chunk');
    }
    if (pcmBytes == null) {
      throw Exception('Invalid WAV file: missing data chunk');
    }
    if (bitsPerSample != 16) {
      throw Exception(
        'Unsupported bit depth: $bitsPerSample-bit. '
        'Realtime API requires 16-bit PCM',
      );
    }
    if (!_supportedSampleRates.contains(sampleRate)) {
      throw Exception(
        'Unsupported sample rate: ${sampleRate}Hz. '
        'Realtime API supports: ${_supportedSampleRates.join(', ')}',
      );
    }

    return _WavInfo(
      channels: channels,
      sampleRate: sampleRate,
      bitsPerSample: bitsPerSample,
      pcmBytes: pcmBytes,
    );
  }

  Uint8List _stereoToMono(Uint8List stereoData) {
    final stereo = ByteData.sublistView(stereoData);
    final monoLength = stereoData.length ~/ 2;
    final mono = Uint8List(monoLength);
    final monoView = ByteData.sublistView(mono);

    // Each stereo frame = 4 bytes (2x int16)
    for (var i = 0; i < stereoData.length - 3; i += 4) {
      final left = stereo.getInt16(i, Endian.little);
      final right = stereo.getInt16(i + 2, Endian.little);
      final mixed = ((left + right) ~/ 2).clamp(-32768, 32767);
      monoView.setInt16(i ~/ 2, mixed, Endian.little);
    }

    return mono;
  }

  Iterable<Uint8List> _chunkPcm(
    Uint8List pcm,
    int bytesPerSecond, {
    int chunkMs = 200,
  }) sync* {
    final chunkSize = bytesPerSecond * chunkMs ~/ 1000;
    for (var offset = 0; offset < pcm.length; offset += chunkSize) {
      yield Uint8List.sublistView(
        pcm,
        offset,
        min(offset + chunkSize, pcm.length),
      );
    }
  }

  String _buildWsUrl(int sampleRate) =>
      'wss://api.elevenlabs.io/v1/speech-to-text/realtime'
      '?model_id=scribe_v2_realtime'
      '&audio_format=pcm_$sampleRate'
      '&commit_strategy=manual';

  void _sendChunk(WebSocket ws, Uint8List chunk, int sampleRate) {
    ws.add(jsonEncode({
      'message_type': 'input_audio_chunk',
      'audio_base_64': base64Encode(chunk),
      'commit': false,
      'sample_rate': sampleRate,
    }));
  }

  void _sendCommit(WebSocket ws, int sampleRate) {
    ws.add(jsonEncode({
      'message_type': 'input_audio_chunk',
      'audio_base_64': '',
      'commit': true,
      'sample_rate': sampleRate,
    }));
  }

  String _errorMessage(String type, Map<String, dynamic> msg) {
    return switch (type) {
      'auth_error' => 'Invalid ElevenLabs API key',
      'quota_exceeded' => 'ElevenLabs quota exceeded — check your plan',
      'rate_limited' => 'Rate limited — try again later',
      'session_time_limit_exceeded' =>
        'Recording too long for realtime — use Scribe v2 batch',
      'chunk_size_exceeded' => 'Audio chunk too large',
      'insufficient_audio_activity' => 'No speech detected in audio',
      'transcriber_error' => 'Transcription error: ${msg['message']}',
      'input_error' => 'Input error: ${msg['message']}',
      'queue_overflow' => 'Server overloaded — try again later',
      _ => 'ElevenLabs realtime error: $type - ${msg['message']}',
    };
  }

  @override
  Future<String> transcribe(Uint8List audioBytes) async {
    final wavInfo = _parseWav(audioBytes);
    dprint(
      'WAV: ${wavInfo.channels}ch, ${wavInfo.sampleRate}Hz, '
      '${wavInfo.bitsPerSample}-bit, ${wavInfo.pcmBytes.length} PCM bytes',
    );

    final monoData = wavInfo.channels == 2
        ? _stereoToMono(wavInfo.pcmBytes)
        : wavInfo.pcmBytes;

    // 1ch * 16-bit AFTER mono conversion
    final monoBytesPerSecond = wavInfo.sampleRate * 2;

    final ws = await WebSocket.connect(
      _buildWsUrl(wavInfo.sampleRate),
      headers: {'xi-api-key': _apiKey},
    );

    final completer = Completer<String>();
    final transcript = StringBuffer();

    final audioSeconds = monoData.length / monoBytesPerSecond;
    final timeoutSeconds = 10 + (audioSeconds / 30).ceil() * 2;
    Timer? inactivityTimer;
    Timer? safetyTimer;

    void complete(String result) {
      inactivityTimer?.cancel();
      safetyTimer?.cancel();
      if (!completer.isCompleted) completer.complete(result);
    }

    void completeError(Object error) {
      inactivityTimer?.cancel();
      safetyTimer?.cancel();
      if (!completer.isCompleted) completer.completeError(error);
    }

    void resetInactivityTimer() {
      inactivityTimer?.cancel();
      inactivityTimer = Timer(const Duration(seconds: 2), () {
        complete(transcript.toString().trim());
        ws.close();
      });
    }

    safetyTimer = Timer(Duration(seconds: timeoutSeconds), () {
      complete(transcript.toString().trim());
      ws.close();
    });

    ws.listen(
      (raw) {
        final msg = jsonDecode(raw as String) as Map<String, dynamic>;
        final type = msg['message_type'] as String?;

        switch (type) {
          case 'session_started':
            dprint('Realtime STT session started: ${msg['session_id']}');
            for (final chunk in _chunkPcm(monoData, monoBytesPerSecond)) {
              _sendChunk(ws, chunk, wavInfo.sampleRate);
            }
            _sendCommit(ws, wavInfo.sampleRate);
            resetInactivityTimer();

          case 'partial_transcript':
            dprint('Partial: ${msg['text']}');

          case 'committed_transcript':
            final text = msg['text'] as String? ?? '';
            dprint('Committed: $text');
            if (text.isNotEmpty) {
              if (transcript.isNotEmpty) transcript.write(' ');
              transcript.write(text);
            }
            resetInactivityTimer();

          default:
            if (type != null && _errorTypes.contains(type)) {
              completeError(Exception(_errorMessage(type, msg)));
              ws.close();
            } else if (type != null &&
                type != 'committed_transcript_with_timestamps') {
              dprint('Unknown realtime STT message: $type');
            }
        }
      },
      onError: (Object error) {
        completeError(Exception('WebSocket error: $error'));
      },
      onDone: () {
        // WS closed before we completed — return what we have
        complete(transcript.toString().trim());
      },
    );

    return completer.future;
  }

  @override
  Stream<String> transcribeStream(
    Stream<Uint8List> pcmStream, {
    required int sampleRate,
  }) {
    final state = _StreamingState(sampleRate: sampleRate);

    state.controller = StreamController<String>(
      onCancel: () {
        state.isCancelled = true;
        state.cleanup();
      },
    );

    _runStreamingSession(state, pcmStream);
    return state.controller.stream;
  }

  Future<void> _runStreamingSession(
    _StreamingState state,
    Stream<Uint8List> pcmStream,
  ) async {
    try {
      final ws = await WebSocket.connect(
        _buildWsUrl(state.sampleRate),
        headers: {'xi-api-key': _apiKey},
      );
      // Consumer cancelled while we were connecting
      if (state.isCancelled) {
        ws.close();
        return;
      }
      state.ws = ws;

      ws.listen((raw) {
        final msg = jsonDecode(raw as String) as Map<String, dynamic>;
        final type = msg['message_type'] as String?;

        switch (type) {
          case 'session_started':
            dprint('Realtime STT session started: ${msg['session_id']}');
            state.sessionStarted = true;
            for (final chunk in state.pendingChunks) {
              _sendChunk(ws, chunk, state.sampleRate);
            }
            state.pendingChunks.clear();

          case 'partial_transcript':
            state.latestPartial = msg['text'] as String? ?? '';
            final aggregated = state.committed.isEmpty
                ? state.latestPartial
                : '${state.committed.toString().trim()} ${state.latestPartial}';
            if (aggregated.trim().isNotEmpty) {
              state.controller.add(aggregated.trim());
            }

          case 'committed_transcript':
            final text = msg['text'] as String? ?? '';
            if (text.isNotEmpty) {
              if (state.committed.isNotEmpty) state.committed.write(' ');
              state.committed.write(text);
            }
            state.latestPartial = '';
            if (state.committed.isNotEmpty) {
              state.controller.add(state.committed.toString().trim());
            }
            if (state.finalCommitSent) {
              if (!state.controller.isClosed) state.controller.close();
              state.cleanup();
            } else {
              _resetInactivityTimer(state, const Duration(seconds: 2));
            }

          default:
            if (type != null && _errorTypes.contains(type)) {
              state.controller.addError(
                Exception(_errorMessage(type, msg)),
              );
              state.cleanup();
              if (!state.controller.isClosed) state.controller.close();
            } else if (type != null &&
                type != 'committed_transcript_with_timestamps') {
              dprint('Unknown realtime STT message: $type');
            }
        }
      }, onError: (e) {
        state.cleanup();
        if (!state.controller.isClosed) {
          state.controller.addError(Exception('WebSocket error: $e'));
          state.controller.close();
        }
      }, onDone: () {
        state.cleanup();
        if (!state.controller.isClosed) state.controller.close();
      });

      state.pcmSub = pcmStream.listen(
        (chunk) {
          if (state.sessionStarted) {
            _sendChunk(ws, chunk, state.sampleRate);
          } else {
            state.pendingChunks.add(chunk);
          }
        },
        onError: (e) => dprint('PCM stream error: $e'),
        onDone: () {
          state.finalCommitSent = true;
          try {
            _sendCommit(ws, state.sampleRate);
          } catch (_) {}
          // Safety fallback if no committed_transcript arrives
          _resetInactivityTimer(state, const Duration(seconds: 5));
        },
      );
    } catch (e) {
      if (!state.controller.isClosed) {
        state.controller.addError(e);
        state.controller.close();
      }
    }
  }

  void _resetInactivityTimer(_StreamingState state, Duration duration) {
    state.inactivityTimer?.cancel();
    state.inactivityTimer = Timer(duration, () {
      if (!state.controller.isClosed) state.controller.close();
      state.cleanup();
    });
  }
}
