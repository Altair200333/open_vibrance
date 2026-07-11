import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:open_vibrance/services/audio_spectrum_analyzer.dart';
import 'package:open_vibrance/services/recording_membrane.dart';

void main() {
  group('RecordingMembraneMapper', () {
    test('flat and near-flat spectra never amplify into visible folds', () {
      final mapper = RecordingMembraneMapper();
      for (var frame = 0; frame < 300; frame++) {
        final target = mapper.map(
          level: 0.72,
          bands: List<double>.generate(
            AudioSpectrumFrame.bandCount,
            (band) => 0.5 + (band.isEven ? 1e-7 : -1e-7),
          ),
          flux: 0,
        );
        for (final coefficient in target.coefficients) {
          expect(coefficient.isFinite, isTrue);
        }
        expect(_range(_radii(target)), lessThan(0.05));
      }
    });

    test('reset and fresh instances replay exactly', () {
      final inputs = <({double level, double flux, List<double> bands})>[];
      var state = 0x12345678;
      for (var frame = 0; frame < 240; frame++) {
        double next() {
          state = (1664525 * state + 1013904223) & 0xffffffff;
          return state / 0xffffffff;
        }

        inputs.add((
          level: 0.2 + 0.8 * next(),
          flux: next(),
          bands: List<double>.generate(
            AudioSpectrumFrame.bandCount,
            (_) => next(),
          ),
        ));
      }

      List<RecordingMembraneTarget> run(RecordingMembraneMapper mapper) => [
        for (final input in inputs)
          mapper.map(level: input.level, bands: input.bands, flux: input.flux),
      ];

      final mapper = RecordingMembraneMapper();
      final first = run(mapper);
      final fresh = run(RecordingMembraneMapper());
      mapper.reset();
      final reset = run(mapper);
      for (var frame = 0; frame < inputs.length; frame++) {
        expect(first[frame].coefficients, fresh[frame].coefficients);
        expect(first[frame].coefficients, reset[frame].coefficients);
        expect(first[frame].novelty, fresh[frame].novelty);
        expect(first[frame].colorPhase, fresh[frame].colorPhase);
      }
    });

    test('phonetic pulses create strong folds around diverse sectors', () {
      final mapper = RecordingMembraneMapper();
      const voice = [
        0.70,
        0.95,
        0.85,
        0.55,
        0.40,
        0.30,
        0.25,
        0.20,
        0.15,
        0.10,
        0.08,
        0.05,
      ];
      for (var frame = 0; frame < 90; frame++) {
        mapper.map(level: 0.78, bands: voice, flux: 0.08);
      }

      final sectors = <int>{};
      var responsivePulses = 0;
      var strongPulses = 0;
      for (var hotBand = 0; hotBand < AudioSpectrumFrame.bandCount; hotBand++) {
        for (var recovery = 0; recovery < 4; recovery++) {
          mapper.map(level: 0.78, bands: voice, flux: 0.05);
        }
        final before = mapper.map(level: 0.78, bands: voice, flux: 0.05);
        final pulseBands = List<double>.generate(
          AudioSpectrumFrame.bandCount,
          (band) => 0.04 + 0.18 * voice[band],
        )..[hotBand] = 1;
        final pulse = mapper.map(level: 0.82, bands: pulseBands, flux: 0.9);
        final beforeRadii = _radii(before);
        final pulseRadii = _radii(pulse);
        if (_maxDifference(beforeRadii, pulseRadii) >= 0.35) {
          responsivePulses++;
        }
        if (_range(pulseRadii) >= 1.5) strongPulses++;
        final peak = pulseRadii.indexOf(pulseRadii.reduce(math.max));
        sectors.add(peak * 12 ~/ pulseRadii.length);
      }

      expect(responsivePulses, greaterThanOrEqualTo(10));
      expect(strongPulses, greaterThanOrEqualTo(10));
      expect(sectors.length, greaterThanOrEqualTo(7));
    });

    test('adversarial streams stay finite and inside contour headroom', () {
      final mapper = RecordingMembraneMapper();
      var state = 0x5eed1234;
      double next() {
        state = (1103515245 * state + 12345) & 0x7fffffff;
        return state / 0x7fffffff;
      }

      for (var frame = 0; frame < 720; frame++) {
        final bands = switch (frame % 5) {
          0 => List<double>.filled(AudioSpectrumFrame.bandCount, 0),
          1 => List<double>.filled(AudioSpectrumFrame.bandCount, 1),
          2 => List<double>.generate(
            AudioSpectrumFrame.bandCount,
            (band) => band.isEven ? 1 : 0,
          ),
          3 => List<double>.generate(
            AudioSpectrumFrame.bandCount,
            (band) => band == frame % AudioSpectrumFrame.bandCount ? 1 : 0,
          ),
          _ => List<double>.generate(
            AudioSpectrumFrame.bandCount,
            (_) => next(),
          ),
        };
        final target = mapper.map(level: next(), bands: bands, flux: next());
        expect(target.coefficients, hasLength(11));
        for (final coefficient in target.coefficients) {
          expect(coefficient.isFinite, isTrue);
        }
        expect(target.actualReach.isFinite, isTrue);
        for (final radius in _radii(target)) {
          expect(
            radius,
            inInclusiveRange(
              RecordingMembraneModel.minCenterRadius - 1e-9,
              RecordingMembraneModel.maxCenterRadius + 1e-9,
            ),
          );
        }
      }
    });

    test('silence targets an exact circle and spring fully settles', () {
      final mapper = RecordingMembraneMapper();
      RecordingMembraneTarget? active;
      for (var frame = 0; frame < 60; frame++) {
        active = mapper.map(
          level: 0.8,
          bands: List<double>.generate(
            AudioSpectrumFrame.bandCount,
            (band) => band == frame % AudioSpectrumFrame.bandCount ? 1 : 0.05,
          ),
          flux: 0.6,
        );
      }
      final dynamics = RecordingMembraneDynamics(active!.coefficients);
      final silence = mapper.map(
        level: 0,
        bands: List<double>.filled(AudioSpectrumFrame.bandCount, 0),
        flux: 0,
        spectrumMix: 0,
      );
      expect(silence.coefficients.first, 6);
      expect(silence.coefficients.skip(1), everyElement(0));
      dynamics.retarget(silence.coefficients);
      for (var frame = 0; frame < 180 && !dynamics.isAtRest; frame++) {
        dynamics.advance(1 / 60);
      }
      expect(dynamics.isAtRest, isTrue);
      expect(dynamics.snapshot, silence.coefficients);
      expect(dynamics.velocity, everyElement(0));
    });
  });
}

List<double> _radii(RecordingMembraneTarget target) =>
    RecordingMembraneModel.radiiFromCoefficients(target.coefficients);

double _range(List<double> values) =>
    values.reduce(math.max) - values.reduce(math.min);

double _maxDifference(List<double> first, List<double> second) {
  var maximum = 0.0;
  for (var index = 0; index < first.length; index++) {
    maximum = math.max(maximum, (first[index] - second[index]).abs());
  }
  return maximum;
}
