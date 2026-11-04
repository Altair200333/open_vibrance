import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:open_vibrance/services/composite_transcription_merger.dart';
import 'package:open_vibrance/services/openrouter_chat.dart';
import 'package:open_vibrance/services/storage_service.dart';
import 'package:open_vibrance/transcription/composite_config.dart';
import 'package:open_vibrance/transcription/elevenlabs_realtime_transcription_provider.dart';
import 'package:open_vibrance/transcription/elevenlabs_transcription_provider.dart';
import 'package:open_vibrance/transcription/google_transcription_provider.dart';
import 'package:open_vibrance/transcription/openai_realtime_transcription_provider.dart';
import 'package:open_vibrance/transcription/openai_transcription_provider.dart';
import 'package:open_vibrance/transcription/streaming_transcription_provider.dart';
import 'package:open_vibrance/transcription/transcription_provider.dart';
import 'package:open_vibrance/transcription/types.dart';
import 'package:open_vibrance/utils/common.dart';
import 'package:open_vibrance/utils/pcm_resampler.dart';

typedef CompositeMerge = Future<String> Function(List<CompositeHypothesis>);

/// Builds per-slot providers from the keys of the individual providers.
class CompositeSlotFactory {
  final SecureStorageService _storage;
  CompositeSlotFactory(this._storage);

  /// File transcription. Realtime models map to their batch equivalent
  /// inside the providers (gpt-live-transcribe -> gpt-transcribe,
  /// scribe_v2_realtime -> scribe_v2), so a saved WAV always works.
  TranscriptionProvider batch(CompositeSlot slot) {
    return switch (slot.provider) {
      TranscriptionProviderKey.openai => OpenAITranscriptionProvider(
        modelOverride: OpenAIModelExtension.fromKey(slot.modelId),
        storageService: _storage,
      ),
      TranscriptionProviderKey.elevenlabs => ElevenLabsTranscriptionProvider(
        modelOverride: ElevenLabsModelExtension.fromKey(slot.modelId),
        storageService: _storage,
      ),
      _ => GoogleTranscriptionProvider(
        modelOverride: GoogleModelExtension.fromKey(slot.modelId),
        storageService: _storage,
      ),
    };
  }

  /// Live provider, or null for file-only models. A realtime slot without a
  /// key also returns null: it then fails on the file path like any batch
  /// slot, without blocking the other slots from recording.
  Future<StreamingTranscriptionProvider?> streaming(CompositeSlot slot) async {
    if (!slot.isRealtime) return null;
    final apiKey =
        (await _storage.readValue(slot.apiKeyStorageKey.key))?.trim();
    if (apiKey == null || apiKey.isEmpty) {
      dprint('[Composite] ${slot.label}: no API key, live mode skipped');
      return null;
    }
    if (slot.provider == TranscriptionProviderKey.elevenlabs) {
      return ElevenLabsRealtimeTranscriptionProvider(apiKey);
    }
    return OpenAIRealtimeTranscriptionProvider(
      apiKey: apiKey,
      prompt: await _storage.readValue(StorageKey.openAiPrompt.key),
    );
  }

  Future<CompositeMerge> merger(CompositeConfig config) async {
    final merger = CompositeTranscriptionMerger(
      apiKey: await readOpenRouterApiKey(_storage),
      model: config.mergerModel,
    );
    return merger.merge;
  }
}

/// Runs one slot and turns its failure into `null`, so a single broken slot
/// (missing key, network, timeout) never fails the whole dictation.
Future<String?> _guardSlot(
  CompositeSlot slot,
  int index,
  Future<String> Function() run,
) async {
  final watch = Stopwatch()..start();
  try {
    final text = await run();
    dprint(
      '[Composite] slot ${index + 1} ${slot.label}: '
      '${watch.elapsedMilliseconds} ms: $text',
    );
    return text;
  } catch (e) {
    dprint('[Composite] slot ${index + 1} ${slot.label} failed: $e');
    return null;
  }
}

/// Merges the successful slots in slot order. Throws only if every slot
/// failed — that is a real error the user must see.
Future<String> _mergeResults(
  List<CompositeSlot> slots,
  List<String?> results,
  CompositeMerge merge,
) async {
  if (results.every((r) => r == null)) {
    throw Exception('All Composite slots failed');
  }
  final watch = Stopwatch()..start();
  final merged = await merge([
    for (var i = 0; i < slots.length; i++)
      if (results[i] != null)
        CompositeHypothesis(label: slots[i].label, text: results[i]!),
  ]);
  dprint('[Composite] merged in ${watch.elapsedMilliseconds} ms: $merged');
  return merged;
}

/// File-only Composite: every slot transcribes the WAV in parallel. Used when
/// no slot is live and for re-transcription from history.
class CompositeTranscriptionProvider implements TranscriptionProvider {
  final SecureStorageService _storage;
  CompositeTranscriptionProvider({SecureStorageService? storageService})
    : _storage = storageService ?? SecureStorageService();

  @override
  Future<String> transcribe(Uint8List audioBytes) async {
    final config = await CompositeConfig.load(_storage);
    final factory = CompositeSlotFactory(_storage);
    final slots = config.slots;
    final results = await Future.wait([
      for (var i = 0; i < slots.length; i++)
        _guardSlot(
          slots[i],
          i,
          () => factory.batch(slots[i]).transcribe(audioBytes),
        ),
    ]);
    return _mergeResults(slots, results, await factory.merger(config));
  }
}

class _LiveSlot {
  final StreamingTranscriptionProvider provider;
  final StreamController<Uint8List> input = StreamController<Uint8List>();
  final Completer<void> done = Completer<void>();
  final Pcm16Resampler? resampler;
  StreamSubscription<String>? subscription;
  String lastTranscript = '';
  Object? error;

  _LiveSlot(this.provider, int recordingRate)
    : resampler =
          provider.requiredSampleRate == recordingRate
              ? null
              : Pcm16Resampler(
                fromRate: recordingRate,
                toRate: provider.requiredSampleRate,
              );

  void complete() {
    if (!done.isCompleted) done.complete();
  }
}

/// Composite recording with at least one live slot.
///
/// ```text
/// mic PCM (highest rate any live slot needs)
///   ├─> live slot A (resampled if its rate differs) ─┐
///   └─> live slot B                                  ├─> merge
/// stop -> WAV on disk -> file slots (in parallel) ───┘
/// ```
class CompositeLiveRun {
  final List<CompositeSlot> slots;
  final TranscriptionProvider Function(CompositeSlot) _batchFor;
  final CompositeMerge _merge;
  final List<StreamingTranscriptionProvider?> _streamers;

  /// Same length as [slots]; null where the slot works on the saved file.
  final List<_LiveSlot?> _live;
  final int recordingSampleRate;
  StreamSubscription<Uint8List>? _pcmSubscription;
  bool _disposed = false;

  CompositeLiveRun({
    required this.slots,
    required List<StreamingTranscriptionProvider?> streamers,
    required TranscriptionProvider Function(CompositeSlot) batchFor,
    required CompositeMerge merge,
  }) : assert(streamers.length == slots.length),
       assert(streamers.any((s) => s != null)),
       _batchFor = batchFor,
       _merge = merge,
       _streamers = streamers,
       recordingSampleRate = streamers
           .whereType<StreamingTranscriptionProvider>()
           .map((s) => s.requiredSampleRate)
           .reduce((a, b) => a > b ? a : b),
       _live = [];

  /// Fans the microphone stream out to every live slot. Call once.
  void attach(Stream<Uint8List> pcm) {
    for (final streamer in _streamers) {
      if (streamer == null) {
        _live.add(null);
        continue;
      }
      final live = _LiveSlot(streamer, recordingSampleRate);
      live.subscription = streamer
          .transcribeStream(
            live.input.stream,
            sampleRate: streamer.requiredSampleRate,
          )
          .listen(
            (text) => live.lastTranscript = text,
            onError: (Object e) {
              live.error = e;
              live.complete();
            },
            onDone: live.complete,
          );
      _live.add(live);
    }
    final live = _live.whereType<_LiveSlot>().toList();
    _pcmSubscription = pcm.listen(
      (chunk) {
        for (final slot in live) {
          if (slot.input.isClosed) continue;
          slot.input.add(slot.resampler?.convert(chunk) ?? chunk);
        }
      },
      onError: (Object e, StackTrace st) {
        for (final slot in live) {
          if (!slot.input.isClosed) slot.input.addError(e, st);
        }
      },
      onDone: () {
        for (final slot in live) {
          if (!slot.input.isClosed) slot.input.close();
        }
      },
    );
  }

  /// Call after the recorder stopped and wrote [wavPath]. Live slots finish
  /// their stream (falling back to the file on stream errors) while file slots
  /// run on the WAV at the same time; then everything is merged.
  Future<String> finish(String wavPath) async {
    final wav = File(wavPath).readAsBytes();
    // Avoid an unhandled error if no slot ends up reading the file.
    unawaited(wav.then((_) {}, onError: (_) {}));

    final results = await Future.wait([
      for (var i = 0; i < slots.length; i++)
        _guardSlot(slots[i], i, () async {
          final live = _live[i];
          if (live != null) {
            await live.done.future;
            if (_disposed) return '';
            if (live.error == null) return live.lastTranscript;
            dprint(
              '[Composite] slot ${i + 1} stream failed, '
              'using saved WAV: ${live.error}',
            );
          }
          return _batchFor(slots[i]).transcribe(await wav);
        }),
    ]);
    if (_disposed) return '';
    return _mergeResults(slots, results, _merge);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final live in _live.whereType<_LiveSlot>()) {
      // Complete before cancel: cancel does not trigger onDone.
      live.complete();
    }
    await _pcmSubscription?.cancel();
    for (final live in _live.whereType<_LiveSlot>()) {
      await live.subscription?.cancel();
      if (!live.input.isClosed) unawaited(live.input.close());
    }
  }
}
