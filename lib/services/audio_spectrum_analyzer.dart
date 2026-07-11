import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

typedef SpectrumFrameCallback = void Function(AudioSpectrumFrame frame);

/// Immutable, normalized visual state produced by [AudioSpectrumAnalyzer].
///
/// An empty [bands] list means that a real spectrum is unavailable and the UI
/// should use its scalar amplitude fallback.
final class AudioSpectrumFrame {
  static const int bandCount = 12;

  AudioSpectrumFrame({
    required Iterable<double> bands,
    required double level,
    required double flux,
    required double activityDb,
    required this.sequence,
    this.endSampleExclusive = 0,
  }) : assert(
         bands.isEmpty || bands.length == bandCount,
         'A spectrum frame must contain exactly $bandCount bands.',
       ),
       bands = List<double>.unmodifiable(bands.map(_unitValue)),
       level = _unitValue(level),
       flux = _unitValue(flux),
       activityDb = activityDb.isFinite ? activityDb : -160.0;

  static final unavailable = AudioSpectrumFrame(
    bands: const [],
    level: 0,
    flux: 0,
    activityDb: -160,
    sequence: 0,
  );

  final List<double> bands;
  final double level;
  final double flux;
  final double activityDb;
  final int sequence;
  final int endSampleExclusive;

  bool get hasSpectrum => bands.length == bandCount;

  static double _unitValue(double value) {
    if (!value.isFinite) return 0;
    return value.clamp(0.0, 1.0).toDouble();
  }
}

/// Synchronously observes PCM16-LE mono chunks and emits smoothed FFT frames.
///
/// The input bytes are never mutated. Callers should keep this analyzer outside
/// audio delivery/finalization barriers and treat failures as visual-only.
class AudioSpectrumAnalyzer {
  AudioSpectrumAnalyzer({this.sampleRate = 16000})
    : _window = Window.hanning(frameSize) {
    _windowPowerScale =
        4 / math.pow(_window.fold<double>(0, (sum, value) => sum + value), 2);
    _configureBands();
    _createStft();
  }

  static const int frameSize = 512;
  static const int hopSize = 256;
  static const int bandCount = AudioSpectrumFrame.bandCount;
  static const double minFrequency = 80;
  static const double maxFrequency = 7600;

  static const double _silenceGateDb = -62;
  static const double _bandFloorDb = -78;
  static const double _bandCeilingDb = -18;
  static const double _responseExponent = 0.68;
  static const double _activityExponent = 0.58;
  static const double _fluxFloor = 0.025;
  static const double _fluxRange = 0.18;

  final int sampleRate;
  final Float64List _window;
  final List<int> _bandStartBins = List<int>.filled(bandCount, 0);
  final List<int> _bandEndBins = List<int>.filled(bandCount, 0);
  final Float64List _bandTargets = Float64List(bandCount);
  final Float64List _previousTargets = Float64List(bandCount);
  final Float64List _displayBands = Float64List(bandCount);

  late STFT _stft;
  late final double _windowPowerScale;
  int? _trailingByte;
  int _processedFrames = 0;
  int _sequence = 0;
  double _displayLevel = 0;
  double _displayFlux = 0;

  void addPcm16(Uint8List chunk, SpectrumFrameCallback onFrame) {
    if (chunk.isEmpty) return;

    final hasTrailingByte = _trailingByte != null;
    final samples = Float64List(
      (chunk.length + (hasTrailingByte ? 1 : 0)) ~/ 2,
    );
    var sourceIndex = 0;
    var sampleIndex = 0;

    if (hasTrailingByte) {
      final raw = _trailingByte! | (chunk[sourceIndex++] << 8);
      samples[sampleIndex++] = _signedPcm16(raw) / 32768.0;
      _trailingByte = null;
    }

    while (sourceIndex + 1 < chunk.length) {
      final raw = chunk[sourceIndex] | (chunk[sourceIndex + 1] << 8);
      samples[sampleIndex++] = _signedPcm16(raw) / 32768.0;
      sourceIndex += 2;
    }

    if (sourceIndex < chunk.length) {
      _trailingByte = chunk[sourceIndex];
    }

    if (samples.isEmpty) return;
    _stft.stream(
      samples,
      (Float64x2List bins) => _processBins(bins, onFrame),
      hopSize,
    );
  }

  void reset() {
    _trailingByte = null;
    _processedFrames = 0;
    _sequence = 0;
    _displayLevel = 0;
    _displayFlux = 0;
    _bandTargets.fillRange(0, bandCount, 0);
    _previousTargets.fillRange(0, bandCount, 0);
    _displayBands.fillRange(0, bandCount, 0);
    _createStft();
  }

  void _createStft() {
    _stft = STFT(frameSize, _window);
  }

  void _configureBands() {
    final frequencyRatio = maxFrequency / minFrequency;
    for (var band = 0; band < bandCount; band++) {
      final low = minFrequency * math.pow(frequencyRatio, band / bandCount);
      final high =
          minFrequency * math.pow(frequencyRatio, (band + 1) / bandCount);
      final start = (low * frameSize / sampleRate).ceil().clamp(
        1,
        frameSize ~/ 2 - 1,
      );
      final end = (high * frameSize / sampleRate).ceil().clamp(
        start + 1,
        frameSize ~/ 2,
      );
      _bandStartBins[band] = start;
      _bandEndBins[band] = end;
    }
  }

  void _processBins(Float64x2List bins, SpectrumFrameCallback onFrame) {
    var activityDb = -160.0;

    for (var band = 0; band < bandCount; band++) {
      var power = 0.0;
      final start = _bandStartBins[band];
      final end = _bandEndBins[band];
      for (var bin = start; bin < end; bin++) {
        final value = bins[bin];
        power += (value.x * value.x + value.y * value.y) * _windowPowerScale;
      }
      power /= end - start;
      final db = 10 * math.log(math.max(power, 1e-18)) / math.ln10;
      if (db > activityDb) activityDb = db;
      _bandTargets[band] = _normalizeBand(db);
    }

    final gateOpen = activityDb >= _silenceGateDb;
    final levelTarget = gateOpen ? _normalizeActivity(activityDb) : 0.0;
    var positiveFlux = 0.0;

    for (var band = 0; band < bandCount; band++) {
      final target = gateOpen ? _bandTargets[band] : 0.0;
      positiveFlux += math.max(0, target - _previousTargets[band]);
      _previousTargets[band] = target;

      final releaseMs = 220 - 80 * band / (bandCount - 1);
      final alpha =
          target > _displayBands[band]
              ? _envelopeAlpha(25)
              : _envelopeAlpha(releaseMs);
      _displayBands[band] += (target - _displayBands[band]) * alpha;
      if (target == 0 && _displayBands[band] < 0.015) {
        _displayBands[band] = 0;
      }
    }

    final levelAlpha =
        levelTarget > _displayLevel ? _envelopeAlpha(25) : _envelopeAlpha(180);
    _displayLevel += (levelTarget - _displayLevel) * levelAlpha;
    if (levelTarget == 0 && _displayLevel < 0.015) _displayLevel = 0;

    final rawFlux = positiveFlux / bandCount;
    final fluxTarget =
        ((rawFlux - _fluxFloor) / _fluxRange).clamp(0.0, 1.0).toDouble();
    if (fluxTarget >= _displayFlux) {
      _displayFlux = fluxTarget;
    } else {
      _displayFlux += (fluxTarget - _displayFlux) * _envelopeAlpha(100);
    }
    if (fluxTarget == 0 && _displayFlux < 0.015) _displayFlux = 0;

    _processedFrames++;
    if (_processedFrames.isOdd) return;

    onFrame(
      AudioSpectrumFrame(
        bands: _displayBands,
        level: _displayLevel,
        flux: _displayFlux,
        activityDb: activityDb,
        sequence: ++_sequence,
        endSampleExclusive: frameSize + (_processedFrames - 1) * hopSize,
      ),
    );
  }

  double _normalizeBand(double db) {
    final normalized =
        ((db - _bandFloorDb) / (_bandCeilingDb - _bandFloorDb))
            .clamp(0.0, 1.0)
            .toDouble();
    return math.pow(normalized, _responseExponent).toDouble();
  }

  double _normalizeActivity(double db) {
    final normalized =
        ((db - _silenceGateDb) / (_bandCeilingDb - _silenceGateDb))
            .clamp(0.0, 1.0)
            .toDouble();
    return math.pow(normalized, _activityExponent).toDouble();
  }

  double _envelopeAlpha(double milliseconds) {
    final secondsPerHop = hopSize / sampleRate;
    return 1 - math.exp(-secondsPerHop / (milliseconds / 1000));
  }

  static int _signedPcm16(int value) {
    return value >= 0x8000 ? value - 0x10000 : value;
  }
}
