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

class ElevenLabsRealtimeTranscriptionProvider
    implements TranscriptionProvider, StreamingTranscriptionProvider {
  final String _apiKey;

  ElevenLabsRealtimeTranscriptionProvider(this._apiKey);

  // ---------------------------------------------------------------------------
  // WAV parser — chunk-based, handles extended WAV formats
  // ---------------------------------------------------------------------------

  _WavInfo _parseWav(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);

    // Validate RIFF + WAVE header
    if (bytes.length < 12 ||
        String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
      throw Exception('Invalid WAV file: missing RIFF/WAVE header');
    }

    int? channels;
    int? sampleRate;
    int? bitsPerSample;
    Uint8List? pcmBytes;

    // Iterate RIFF chunks starting after the 12-byte header
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

      // Move to next chunk (chunks are word-aligned)
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

  // ---------------------------------------------------------------------------
  // Stereo → mono downmix (average L+R)
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // PCM chunking (~200ms)
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // transcribe() — WebSocket flow
  // ---------------------------------------------------------------------------

  @override
  Future<String> transcribe(Uint8List audioBytes) async {
    // 1. Parse WAV
    final wavInfo = _parseWav(audioBytes);
    dprint(
      'WAV: ${wavInfo.channels}ch, ${wavInfo.sampleRate}Hz, '
      '${wavInfo.bitsPerSample}-bit, ${wavInfo.pcmBytes.length} PCM bytes',
    );

    // 2. Stereo → mono if needed
    final monoData = wavInfo.channels == 2
        ? _stereoToMono(wavInfo.pcmBytes)
        : wavInfo.pcmBytes;

    // 3. Compute bytes per second AFTER mono conversion
    final monoBytesPerSecond = wavInfo.sampleRate * 2; // 1ch * 16-bit

    // 4. Connect WebSocket
    final url = 'wss://api.elevenlabs.io/v1/speech-to-text/realtime'
        '?model_id=scribe_v2_realtime'
        '&audio_format=pcm_${wavInfo.sampleRate}'
        '&commit_strategy=manual';

    final ws = await WebSocket.connect(
      url,
      headers: {'xi-api-key': _apiKey},
    );

    final completer = Completer<String>();
    final transcript = StringBuffer();

    // Duration-scaled safety timeout
    final audioSeconds = monoData.length / monoBytesPerSecond;
    final timeoutSeconds = 10 + (audioSeconds / 30).ceil() * 2;
    Timer? inactivityTimer;
    Timer? safetyTimer;

    void complete(String result) {
      inactivityTimer?.cancel();
      safetyTimer?.cancel();
      if (!completer.isCompleted) {
        completer.complete(result);
      }
    }

    void completeError(Object error) {
      inactivityTimer?.cancel();
      safetyTimer?.cancel();
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }

    void resetInactivityTimer() {
      inactivityTimer?.cancel();
      inactivityTimer = Timer(const Duration(seconds: 2), () {
        complete(transcript.toString().trim());
        ws.close();
      });
    }

    // Safety net timeout
    safetyTimer = Timer(Duration(seconds: timeoutSeconds), () {
      complete(transcript.toString().trim());
      ws.close();
    });

    // 5. Listen for messages
    ws.listen(
      (raw) {
        final msg = jsonDecode(raw as String) as Map<String, dynamic>;
        final type = msg['message_type'] as String?;

        switch (type) {
          case 'session_started':
            dprint('Realtime STT session started: ${msg['session_id']}');

            // 6. Send all audio chunks
            for (final chunk
                in _chunkPcm(monoData, monoBytesPerSecond)) {
              ws.add(jsonEncode({
                'message_type': 'input_audio_chunk',
                'audio_base_64': base64Encode(chunk),
                'commit': false,
                'sample_rate': wavInfo.sampleRate,
              }));
            }

            // 7. Send final commit (empty audio, commit: true)
            ws.add(jsonEncode({
              'message_type': 'input_audio_chunk',
              'audio_base_64': '',
              'commit': true,
              'sample_rate': wavInfo.sampleRate,
            }));

            // 8. Start inactivity timer after sending final commit
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

          // Error types
          case 'auth_error':
            completeError(Exception('Invalid ElevenLabs API key'));
            ws.close();
          case 'quota_exceeded':
            completeError(Exception(
              'ElevenLabs quota exceeded — check your plan',
            ));
            ws.close();
          case 'rate_limited':
            completeError(Exception('Rate limited — try again later'));
            ws.close();
          case 'session_time_limit_exceeded':
            completeError(Exception(
              'Recording too long for realtime — use Scribe v2 batch',
            ));
            ws.close();
          case 'chunk_size_exceeded':
            completeError(Exception('Audio chunk too large'));
            ws.close();
          case 'insufficient_audio_activity':
            completeError(Exception('No speech detected in audio'));
            ws.close();
          case 'transcriber_error':
            completeError(Exception(
              'Transcription error: ${msg['message']}',
            ));
            ws.close();
          case 'input_error':
            completeError(Exception('Input error: ${msg['message']}'));
            ws.close();
          case 'queue_overflow':
            completeError(Exception(
              'Server overloaded — try again later',
            ));
            ws.close();

          default:
            if (type != null &&
                type != 'committed_transcript_with_timestamps') {
              dprint('Unknown realtime STT message: $type');
            }
        }
      },
      onError: (Object error) {
        completeError(Exception('WebSocket error: $error'));
      },
      onDone: () {
        // If WS closes before we completed, return what we have
        complete(transcript.toString().trim());
      },
    );

    return completer.future;
  }

  // ---------------------------------------------------------------------------
  // transcribeStream() — true real-time streaming
  // ---------------------------------------------------------------------------

  @override
  Stream<String> transcribeStream(
    Stream<Uint8List> pcmStream, {
    required int sampleRate,
  }) {
    final committed = StringBuffer();
    String latestPartial = '';
    bool sessionStarted = false;
    bool finalCommitSent = false;
    final pendingChunks = <Uint8List>[];
    Timer? inactivityTimer;

    late final WebSocket ws;
    late final StreamSubscription<Uint8List> pcmSub;
    late final StreamController<String> controller;

    void cleanup() {
      inactivityTimer?.cancel();
      try { ws.close(); } catch (_) {}
    }

    void startInactivityTimer() {
      inactivityTimer?.cancel();
      inactivityTimer = Timer(const Duration(seconds: 2), () {
        if (!controller.isClosed) controller.close();
        cleanup();
      });
    }

    controller = StreamController<String>(
      onCancel: () {
        pcmSub.cancel();
        cleanup();
      },
    );

    () async {
      try {
        // 1. Connect WebSocket
        final url = 'wss://api.elevenlabs.io/v1/speech-to-text/realtime'
            '?model_id=scribe_v2_realtime'
            '&audio_format=pcm_$sampleRate'
            '&commit_strategy=manual';

        ws = await WebSocket.connect(url, headers: {'xi-api-key': _apiKey});

        // 2. Listen for incoming WS messages
        ws.listen((raw) {
          final msg = jsonDecode(raw as String) as Map<String, dynamic>;
          final type = msg['message_type'] as String?;

          switch (type) {
            case 'session_started':
              dprint('Realtime STT session started: ${msg['session_id']}');
              sessionStarted = true;
              for (final chunk in pendingChunks) {
                _sendChunk(ws, chunk, sampleRate);
              }
              pendingChunks.clear();

            case 'partial_transcript':
              latestPartial = msg['text'] as String? ?? '';
              final aggregated = committed.isEmpty
                  ? latestPartial
                  : '${committed.toString().trim()} $latestPartial';
              if (aggregated.trim().isNotEmpty) {
                controller.add(aggregated.trim());
              }

            case 'committed_transcript':
              final text = msg['text'] as String? ?? '';
              if (text.isNotEmpty) {
                if (committed.isNotEmpty) committed.write(' ');
                committed.write(text);
              }
              latestPartial = '';
              if (committed.isNotEmpty) {
                controller.add(committed.toString().trim());
              }
              if (finalCommitSent) {
                // Final commit response received — close immediately
                if (!controller.isClosed) controller.close();
                cleanup();
              } else {
                startInactivityTimer();
              }

            // Error handling
            case 'auth_error':
            case 'quota_exceeded':
            case 'rate_limited':
            case 'session_time_limit_exceeded':
            case 'chunk_size_exceeded':
            case 'insufficient_audio_activity':
            case 'transcriber_error':
            case 'input_error':
            case 'queue_overflow':
              controller.addError(
                Exception(_streamErrorMessage(type!, msg)),
              );
              cleanup();
              if (!controller.isClosed) controller.close();

            default:
              if (type != null &&
                  type != 'committed_transcript_with_timestamps') {
                dprint('Unknown realtime STT message: $type');
              }
          }
        }, onError: (e) {
          if (!controller.isClosed) {
            controller.addError(Exception('WebSocket error: $e'));
            controller.close();
          }
        }, onDone: () {
          if (!controller.isClosed) controller.close();
        });

        // 3. Forward PCM chunks from microphone → WebSocket as they arrive
        pcmSub = pcmStream.listen(
          (chunk) {
            if (sessionStarted) {
              _sendChunk(ws, chunk, sampleRate);
            } else {
              pendingChunks.add(chunk);
            }
          },
          onError: (e) {
            dprint('PCM stream error: $e');
          },
          onDone: () {
            // 4. pcmStream ended (recording stopped) → send final commit
            finalCommitSent = true;
            try {
              ws.add(jsonEncode({
                'message_type': 'input_audio_chunk',
                'audio_base_64': '',
                'commit': true,
                'sample_rate': sampleRate,
              }));
            } catch (_) {}
            // Safety fallback — if no committed_transcript arrives
            // within 5s after final commit, close the stream
            inactivityTimer?.cancel();
            inactivityTimer = Timer(const Duration(seconds: 5), () {
              if (!controller.isClosed) controller.close();
              cleanup();
            });
          },
        );
      } catch (e) {
        if (!controller.isClosed) {
          controller.addError(e);
          controller.close();
        }
      }
    }();

    return controller.stream;
  }

  void _sendChunk(WebSocket ws, Uint8List chunk, int sampleRate) {
    ws.add(jsonEncode({
      'message_type': 'input_audio_chunk',
      'audio_base_64': base64Encode(chunk),
      'commit': false,
      'sample_rate': sampleRate,
    }));
  }

  String _streamErrorMessage(String type, Map<String, dynamic> msg) {
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
}
