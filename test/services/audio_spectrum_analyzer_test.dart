import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_vibrance/services/audio_spectrum_analyzer.dart';

void main() {
  test('silence produces a stable zero spectrum', () {
    final analyzer = AudioSpectrumAnalyzer();
    final frames = <AudioSpectrumFrame>[];

    analyzer.addPcm16(Uint8List(4096), frames.add);

    expect(frames, isNotEmpty);
    expect(frames.last.hasSpectrum, isTrue);
    expect(frames.last.level, 0);
    expect(frames.last.flux, 0);
    expect(frames.last.bands, everyElement(0));
  });

  test('a 1 kHz sine activates its logarithmic frequency band', () {
    final analyzer = AudioSpectrumAnalyzer();
    final frames = <AudioSpectrumFrame>[];

    analyzer.addPcm16(
      _sinePcm(frequency: 1000, amplitude: 0.65, sampleCount: 8192),
      frames.add,
    );

    final bands = frames.last.bands;
    final strongestBand = bands.indexOf(bands.reduce(math.max));
    final expectedBand =
        (math.log(1000 / AudioSpectrumAnalyzer.minFrequency) /
                math.log(
                  AudioSpectrumAnalyzer.maxFrequency /
                      AudioSpectrumAnalyzer.minFrequency,
                ) *
                AudioSpectrumAnalyzer.bandCount)
            .floor();

    expect(strongestBand, inInclusiveRange(expectedBand - 1, expectedBand + 1));
    expect(bands[strongestBand], greaterThan(0.75));
    expect(frames.last.level, greaterThan(0.7));
  });

  test('arbitrary odd chunk boundaries preserve the same spectrum', () {
    final pcm = _sinePcm(frequency: 2400, amplitude: 0.55, sampleCount: 8192);
    final wholeAnalyzer = AudioSpectrumAnalyzer();
    final splitAnalyzer = AudioSpectrumAnalyzer();
    final wholeFrames = <AudioSpectrumFrame>[];
    final splitFrames = <AudioSpectrumFrame>[];

    wholeAnalyzer.addPcm16(pcm, wholeFrames.add);

    const splitSizes = [1, 17, 4, 63, 255, 2, 511, 9, 1023];
    var offset = 0;
    var splitIndex = 0;
    while (offset < pcm.length) {
      final end = math.min(
        pcm.length,
        offset + splitSizes[splitIndex % splitSizes.length],
      );
      splitAnalyzer.addPcm16(
        Uint8List.sublistView(pcm, offset, end),
        splitFrames.add,
      );
      offset = end;
      splitIndex++;
    }

    expect(splitFrames.length, wholeFrames.length);
    expect(splitFrames.last.level, closeTo(wholeFrames.last.level, 1e-9));
    for (var band = 0; band < AudioSpectrumFrame.bandCount; band++) {
      expect(
        splitFrames.last.bands[band],
        closeTo(wholeFrames.last.bands[band], 1e-9),
      );
    }
  });

  test('reset discards a trailing byte and all visual state', () {
    final analyzer = AudioSpectrumAnalyzer();
    final afterReset = <AudioSpectrumFrame>[];
    final fresh = <AudioSpectrumFrame>[];

    analyzer.addPcm16(Uint8List.fromList([0x7f]), (_) {});
    analyzer.reset();
    final pcm = _sinePcm(frequency: 400, amplitude: 0.4, sampleCount: 4096);
    analyzer.addPcm16(pcm, afterReset.add);
    AudioSpectrumAnalyzer().addPcm16(pcm, fresh.add);

    expect(afterReset.length, fresh.length);
    expect(afterReset.last.level, closeTo(fresh.last.level, 1e-9));
    expect(afterReset.last.sequence, fresh.last.sequence);
  });

  test('published spectrum bands are immutable', () {
    final analyzer = AudioSpectrumAnalyzer();
    final frames = <AudioSpectrumFrame>[];
    analyzer.addPcm16(
      _sinePcm(frequency: 800, amplitude: 0.5, sampleCount: 2048),
      frames.add,
    );

    expect(() => frames.last.bands[0] = 1, throwsUnsupportedError);
  });

  test('published frames expose their exact source sample endpoint', () {
    final frames = <AudioSpectrumFrame>[];
    AudioSpectrumAnalyzer().addPcm16(Uint8List(8192), frames.add);

    for (final frame in frames) {
      expect(
        frame.endSampleExclusive,
        AudioSpectrumAnalyzer.frameSize +
            (2 * frame.sequence - 1) * AudioSpectrumAnalyzer.hopSize,
      );
    }
  });

  test('voice onset decays to exact visual silence', () {
    final analyzer = AudioSpectrumAnalyzer();
    final frames = <AudioSpectrumFrame>[];

    analyzer.addPcm16(
      _sinePcm(frequency: 700, amplitude: 0.7, sampleCount: 4096),
      frames.add,
    );
    expect(frames.any((frame) => frame.flux > 0), isTrue);

    analyzer.addPcm16(Uint8List(32000), frames.add);

    expect(frames.last.flux, 0);
    expect(frames.last.level, 0);
    expect(frames.last.bands, everyElement(0));
  });
}

Uint8List _sinePcm({
  required double frequency,
  required double amplitude,
  required int sampleCount,
  int sampleRate = 16000,
}) {
  final bytes = Uint8List(sampleCount * 2);
  final data = ByteData.sublistView(bytes);
  for (var sample = 0; sample < sampleCount; sample++) {
    final value =
        (math.sin(2 * math.pi * frequency * sample / sampleRate) *
                amplitude *
                32767)
            .round();
    data.setInt16(sample * 2, value, Endian.little);
  }
  return bytes;
}
