import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_vibrance/services/audio_spectrum_analyzer.dart';
import 'package:open_vibrance/widgets/dot_indicator.dart';
import 'package:open_vibrance/widgets/dot_indicator/recording_dot.dart';

void main() {
  group('recordingLevelFromDb', () {
    test('gates silence and clamps loud input', () {
      expect(recordingLevelFromDb(-160), 0);
      expect(recordingLevelFromDb(double.negativeInfinity), 0);
      expect(recordingLevelFromDb(double.nan), 0);
      expect(recordingLevelFromDb(kMinVolumeDb), 0);
      expect(recordingLevelFromDb(kMaxVolumeDb), 1);
      expect(recordingLevelFromDb(0), 1);
      expect(recordingLevelFromDb(double.infinity), 1);
    });

    test('uses a soft knee and a fuller response through the voice range', () {
      final quiet = recordingLevelFromDb(-52);
      final softVoice = recordingLevelFromDb(-40);
      final mediumVoice = recordingLevelFromDb(-31.5);
      final loudVoice = recordingLevelFromDb(-16);

      expect(quiet, greaterThan(0));
      expect(quiet, lessThan(softVoice));
      expect(softVoice, lessThan(mediumVoice));
      expect(mediumVoice, greaterThan(0.5));
      expect(mediumVoice, lessThan(loudVoice));
      expect(loudVoice, lessThan(1));
    });
  });

  group('Fourier membrane geometry', () {
    test('contour is bounded, smooth, finite, and deterministic', () {
      final cases = <({double level, double flux, List<double> bands})>[
        (level: 0, flux: 0, bands: List<double>.filled(12, 0)),
        (level: 1, flux: 1, bands: List<double>.filled(12, 1)),
        (
          level: 0.8,
          flux: 0.6,
          bands: List<double>.generate(12, (index) => index.isEven ? 1 : 0),
        ),
        for (var band = 0; band < AudioSpectrumFrame.bandCount; band++)
          (
            level: 0.75,
            flux: 0.4,
            bands: List<double>.generate(12, (index) => index == band ? 1 : 0),
          ),
      ];

      for (final input in cases) {
        final radii = _targetRadii(
          level: input.level,
          bands: input.bands,
          flux: input.flux,
        );
        final repeated = _targetRadii(
          level: input.level,
          bands: input.bands,
          flux: input.flux,
        );

        expect(radii, hasLength(RecordingMembranePainter.contourSampleCount));
        expect(repeated, radii);
        _expectRadiiBounded(radii);
        final radiusRange = radii.reduce(math.max) - radii.reduce(math.min);
        for (var sample = 0; sample < radii.length; sample++) {
          final next = radii[(sample + 1) % radii.length];
          expect(
            (radii[sample] - next).abs(),
            lessThan(math.max(0.2, 0.24 * radiusRange)),
          );
        }
      }
    });

    test('scalar fallback is a monotonic breathing circle', () {
      final radiiByLevel = <List<double>>[];
      for (final level in [0.0, 0.5, 1.0]) {
        final radii = RecordingMembranePainter.contourRadii(
          level: level,
          bands: List<double>.filled(AudioSpectrumFrame.bandCount, level),
          flux: 0,
          spectrumMix: 0,
        );
        radiiByLevel.add(radii);
        expect(_range(radii), lessThan(1e-10));
      }
      expect(radiiByLevel[0].first, lessThan(radiiByLevel[1].first));
      expect(radiiByLevel[1].first, lessThan(radiiByLevel[2].first));
    });

    test('uniform spectra remain circular instead of becoming a flower', () {
      for (final energy in [0.2, 0.7, 1.0]) {
        final coefficients = RecordingMembraneModel.coefficientsFor(
          level: 0.8,
          bands: List<double>.filled(AudioSpectrumFrame.bandCount, energy),
          flux: 0.5,
          spectrumMix: 1,
        );
        final radii = RecordingMembraneModel.radiiFromCoefficients(
          coefficients,
        );

        expect(
          coefficients.skip(1).map((value) => value.abs()).reduce(math.max),
          lessThan(1e-10),
        );
        expect(_range(radii), lessThan(1e-9));
      }
    });

    test('normal loud targets reserve spring overshoot headroom', () {
      for (var band = 0; band < AudioSpectrumFrame.bandCount; band++) {
        final radii = _targetRadii(
          level: 1,
          bands: List<double>.generate(
            AudioSpectrumFrame.bandCount,
            (index) => index == band ? 1 : 0,
          ),
          flux: 1,
        );

        expect(radii.reduce(math.min), greaterThanOrEqualTo(3.5 - 1e-9));
        expect(radii.reduce(math.max), lessThanOrEqualTo(12.5 + 1e-9));
      }
    });

    test('voice-shaped spectra create broad high-amplitude signed folds', () {
      final voiceSpectra = <List<double>>[
        const [.7, .95, .85, .55, .4, .3, .25, .2, .15, .1, .08, .05],
        const [.08, .1, .12, .2, .3, .45, .7, .9, 1, .8, .6, .4],
        const [.35, .9, .55, .75, .3, .6, .85, .4, .7, .25, .5, .2],
      ];

      for (final bands in voiceSpectra) {
        final radii = _targetRadii(level: 0.78, bands: bands, flux: 0.45);
        final mean = _average(radii);
        final range = _range(radii);
        final peaks = _prominentCircularPeaks(radii);

        expect(range, greaterThan(4.5));
        expect(radii.reduce(math.max) - mean, greaterThan(0.8));
        expect(mean - radii.reduce(math.min), greaterThan(0.8));
        expect(peaks.length, inInclusiveRange(1, 5));
      }
    });

    test('moving frequency energy rotates the dominant membrane fold', () {
      final firstBands = List<double>.filled(AudioSpectrumFrame.bandCount, 0.05)
        ..[2] = 1;
      final secondBands = List<double>.filled(
        AudioSpectrumFrame.bandCount,
        0.05,
      )..[9] = 1;
      final first = _targetRadii(level: 0.75, bands: firstBands, flux: 0.3);
      final second = _targetRadii(level: 0.75, bands: secondBands, flux: 0.3);
      final firstPeak = first.indexOf(first.reduce(math.max));
      final secondPeak = second.indexOf(second.reduce(math.max));

      expect(
        _circularSampleDistance(firstPeak, secondPeak, first.length),
        greaterThan(12),
      );
      expect(_maxDifference(first, second), greaterThan(1.5));
      expect((_average(first) - _average(second)).abs(), lessThan(1e-8));
    });

    test('adjacent-band crossfade moves the fold continuously', () {
      final angles = <double>[];
      for (var step = 0; step <= 20; step++) {
        final radii = _targetRadii(
          level: 0.78,
          bands: _adjacentCrossfadeBands(step / 20),
          flux: 0.45,
        );
        var angle = _positiveDeformationAngle(radii);
        if (angles.isNotEmpty) {
          angle = _unwrapNear(angle, angles.last);
          expect(angle, greaterThanOrEqualTo(angles.last - 1e-6));
          expect(angle - angles.last, lessThan(0.07));
        }
        angles.add(angle);
      }

      expect(angles.last - angles.first, inInclusiveRange(0.35, 0.70));
    });
  });

  group('membrane spring dynamics', () {
    test('retarget preserves current position and velocity exactly', () {
      final silence = _fallbackCoefficients(0.2);
      final firstTarget = _voiceCoefficients(hotBand: 2);
      final secondTarget = _voiceCoefficients(hotBand: 8);
      final dynamics = RecordingMembraneDynamics(silence);

      dynamics.retarget(firstTarget);
      for (var frame = 0; frame < 5; frame++) {
        dynamics.advance(1 / 60);
      }
      expect(
        dynamics.velocity.map((value) => value.abs()).reduce(math.max),
        greaterThan(0.05),
      );

      final positionBefore = dynamics.snapshot;
      final velocityBefore = dynamics.velocity;
      expect(dynamics.retarget(secondTarget), isTrue);

      expect(dynamics.snapshot, positionBefore);
      expect(dynamics.velocity, velocityBefore);
      expect(dynamics.target, secondTarget);
    });

    test('analytic spring is effectively frame-rate invariant', () {
      final at30 = _simulateAtFps(30);
      final at60 = _simulateAtFps(60);
      final at120 = _simulateAtFps(120);

      expect(at30.isAtRest, isFalse);
      expect(at60.isAtRest, isFalse);
      expect(at120.isAtRest, isFalse);
      expect(_maxDifference(at30.snapshot, at120.snapshot), lessThan(1e-8));
      expect(_maxDifference(at60.snapshot, at120.snapshot), lessThan(1e-8));
      expect(_maxDifference(at30.velocity, at120.velocity), lessThan(1e-7));
      expect(_maxDifference(at60.velocity, at120.velocity), lessThan(1e-7));
    });

    test('integrates ordinary long frames and snaps after a resume gap', () {
      final singleStep = RecordingMembraneDynamics(_fallbackCoefficients(0.1));
      final sliced = RecordingMembraneDynamics(_fallbackCoefficients(0.1));
      final target = _voiceCoefficients(hotBand: 4);
      singleStep.retarget(target);
      sliced.retarget(target);

      singleStep.advance(0.1);
      for (var step = 0; step < 10; step++) {
        sliced.advance(0.01);
      }
      expect(
        _maxDifference(singleStep.snapshot, sliced.snapshot),
        lessThan(1e-9),
      );
      expect(
        _maxDifference(singleStep.velocity, sliced.velocity),
        lessThan(1e-8),
      );

      final resumeTarget = _voiceCoefficients(hotBand: 9);
      singleStep.retarget(resumeTarget);
      expect(singleStep.advance(0.3), isFalse);
      expect(singleStep.isAtRest, isTrue);
      expect(singleStep.snapshot, resumeTarget);
      expect(singleStep.velocity, everyElement(0));
    });

    test('rapid signed retargets remain bounded through spring overshoot', () {
      final dynamics = RecordingMembraneDynamics(_fallbackCoefficients(0));
      for (var frame = 0; frame < 180; frame++) {
        if (frame % 6 == 0) {
          dynamics.retarget(
            _voiceCoefficients(hotBand: (frame ~/ 6).isEven ? 1 : 8),
          );
        }
        dynamics.advance(1 / 60);
        _expectRadiiBounded(
          RecordingMembraneModel.radiiFromCoefficients(dynamics.snapshot),
        );
      }
    });

    test('32ms target sequence has bounded visual acceleration', () {
      final dynamics = RecordingMembraneDynamics(_crossfadeCoefficients(0));
      final frames = <List<double>>[
        RecordingMembraneModel.radiiFromCoefficients(dynamics.snapshot),
      ];
      for (var targetStep = 1; targetStep <= 20; targetStep++) {
        dynamics.retarget(_crossfadeCoefficients(targetStep / 20));
        for (var visualFrame = 0; visualFrame < 2; visualFrame++) {
          dynamics.advance(0.016);
          frames.add(
            RecordingMembraneModel.radiiFromCoefficients(dynamics.snapshot),
          );
        }
      }

      final endpointSpan = _maxDifference(
        RecordingMembraneModel.radiiFromCoefficients(_crossfadeCoefficients(0)),
        RecordingMembraneModel.radiiFromCoefficients(_crossfadeCoefficients(1)),
      );
      var maxSecondDifference = 0.0;
      for (var frame = 2; frame < frames.length; frame++) {
        for (var sample = 0; sample < frames[frame].length; sample++) {
          maxSecondDifference = math.max(
            maxSecondDifference,
            (frames[frame][sample] -
                    2 * frames[frame - 1][sample] +
                    frames[frame - 2][sample])
                .abs(),
          );
        }
      }

      expect(maxSecondDifference / endpointSpan, lessThan(0.25));
    });

    test('silence settles to an exact circle with zero velocity', () {
      final dynamics = RecordingMembraneDynamics(
        _voiceCoefficients(hotBand: 3),
      );
      dynamics.retarget(_voiceCoefficients(hotBand: 8));
      for (var frame = 0; frame < 12; frame++) {
        dynamics.advance(1 / 60);
      }
      final silence = _fallbackCoefficients(0);
      dynamics.retarget(silence);

      for (var frame = 0; frame < 180 && !dynamics.isAtRest; frame++) {
        dynamics.advance(1 / 60);
      }

      expect(dynamics.isAtRest, isTrue);
      expect(dynamics.snapshot, silence);
      expect(dynamics.velocity, everyElement(0));
      expect(
        _range(RecordingMembraneModel.radiiFromCoefficients(dynamics.snapshot)),
        lessThan(1e-10),
      );
    });
  });

  group('RecordingDot widget', () {
    testWidgets('fallback paints a 30px circle', (tester) async {
      await tester.pumpWidget(_recordingDot(level: 0.6));

      final painter = _membranePainter(tester);
      final radii = RecordingMembranePainter.radiiFromCoefficients(
        painter.coefficients,
      );
      expect(_range(radii), lessThan(1e-10));
      expect(tester.getSize(find.byType(RecordingDot)), const Size(30, 30));
    });

    testWidgets('a real spectrum seeds its exact stateful target', (
      tester,
    ) async {
      final frame = _spectrumFrame(hotBand: 4, sequence: 1);
      await tester.pumpWidget(_recordingDot(level: 0.1, spectrumFrame: frame));

      final expected =
          RecordingMembraneMapper()
              .map(level: frame.level, bands: frame.bands, flux: frame.flux)
              .coefficients;
      expect(_membranePainter(tester).coefficients, expected);
    });

    testWidgets('rebuilds ingest each spectrum sequence only once', (
      tester,
    ) async {
      var frame = _spectrumFrame(hotBand: 4, sequence: 1);
      var fillColor = Colors.red;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return Center(
                child: RecordingDot(
                  level: 0.7,
                  spectrumFrame: frame,
                  fillColor: fillColor,
                  borderColor: Colors.white,
                ),
              );
            },
          ),
        ),
      );
      final initial = _membranePainter(tester).coefficients;

      for (var rebuildIndex = 0; rebuildIndex < 20; rebuildIndex++) {
        rebuild(() {
          fillColor = rebuildIndex.isEven ? Colors.blue : Colors.red;
        });
        await tester.pump();
        expect(_membranePainter(tester).coefficients, initial);
      }

      rebuild(() => frame = _spectrumFrame(hotBand: 4, sequence: 2));
      await tester.pump();
      expect(_membranePainter(tester).coefficients, initial);
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      expect(
        _maxDifference(_membranePainter(tester).coefficients, initial),
        greaterThan(1e-4),
      );
    });

    testWidgets('spectrum retarget keeps position continuous then moves', (
      tester,
    ) async {
      var frame = _spectrumFrame(hotBand: 2, sequence: 1);
      final expectedMapper =
          RecordingMembraneMapper()
            ..map(level: frame.level, bands: frame.bands, flux: frame.flux);
      late StateSetter updateDot;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              updateDot = setState;
              return Center(
                child: RecordingDot(
                  level: 0.7,
                  spectrumFrame: frame,
                  fillColor: Colors.red,
                  borderColor: Colors.white,
                ),
              );
            },
          ),
        ),
      );

      final before = _painterRadii(_membranePainter(tester));
      updateDot(() => frame = _spectrumFrame(hotBand: 9, sequence: 2));
      expectedMapper.map(
        level: frame.level,
        bands: frame.bands,
        flux: frame.flux,
      );
      await tester.pump();
      _expectRadiiClose(_painterRadii(_membranePainter(tester)), before);

      await tester.pump(const Duration(milliseconds: 16));
      final afterOneFrame = _painterRadii(_membranePainter(tester));
      expect(_maxDifference(afterOneFrame, before), greaterThan(1e-4));

      final beforeMidRetarget = afterOneFrame;
      updateDot(() => frame = _spectrumFrame(hotBand: 5, sequence: 3));
      final expectedTarget = expectedMapper.map(
        level: frame.level,
        bands: frame.bands,
        flux: frame.flux,
      );
      await tester.pump();
      _expectRadiiClose(
        _painterRadii(_membranePainter(tester)),
        beforeMidRetarget,
      );

      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      final expected = RecordingMembraneModel.radiiFromCoefficients(
        expectedTarget.coefficients,
      );
      expect(
        _maxDifference(_painterRadii(_membranePainter(tester)), expected),
        lessThan(0.01),
      );
    });

    testWidgets('spectrum to fallback has no jump and settles to a circle', (
      tester,
    ) async {
      var level = 0.7;
      var frame = _spectrumFrame(hotBand: 5, sequence: 1);
      late StateSetter updateDot;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              updateDot = setState;
              return Center(
                child: RecordingDot(
                  level: level,
                  spectrumFrame: frame,
                  fillColor: Colors.red,
                  borderColor: Colors.white,
                ),
              );
            },
          ),
        ),
      );

      final before = _painterRadii(_membranePainter(tester));
      updateDot(() {
        level = 0.3;
        frame = AudioSpectrumFrame.unavailable;
      });
      await tester.pump();
      _expectRadiiClose(_painterRadii(_membranePainter(tester)), before);

      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      final finalRadii = _painterRadii(_membranePainter(tester));
      expect(_range(finalRadii), lessThan(1e-8));
    });

    testWidgets('fallback to spectrum has no jump and settles to membrane', (
      tester,
    ) async {
      var level = 0.3;
      var frame = AudioSpectrumFrame.unavailable;
      final expectedMapper = RecordingMembraneMapper();
      late StateSetter updateDot;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              updateDot = setState;
              return Center(
                child: RecordingDot(
                  level: level,
                  spectrumFrame: frame,
                  fillColor: Colors.red,
                  borderColor: Colors.white,
                ),
              );
            },
          ),
        ),
      );

      final before = _painterRadii(_membranePainter(tester));
      updateDot(() {
        level = 0.78;
        frame = _spectrumFrame(hotBand: 4, sequence: 1);
      });
      final expectedTarget = expectedMapper.map(
        level: frame.level,
        bands: frame.bands,
        flux: frame.flux,
      );
      await tester.pump();
      _expectRadiiClose(_painterRadii(_membranePainter(tester)), before);

      await tester.pump(const Duration(milliseconds: 16));
      expect(
        _maxDifference(_painterRadii(_membranePainter(tester)), before),
        greaterThan(1e-4),
      );

      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      final expected = RecordingMembraneModel.radiiFromCoefficients(
        expectedTarget.coefficients,
      );
      expect(
        _maxDifference(_painterRadii(_membranePainter(tester)), expected),
        lessThan(0.01),
      );
    });
  });
}

RecordingMembraneDynamics _simulateAtFps(int fps) {
  final dynamics = RecordingMembraneDynamics(_fallbackCoefficients(0.1));
  dynamics.retarget(_voiceCoefficients(hotBand: 2));
  for (var frame = 0; frame < fps ~/ 10; frame++) {
    dynamics.advance(1 / fps);
  }
  dynamics.retarget(_voiceCoefficients(hotBand: 9));
  for (var frame = 0; frame < fps ~/ 10; frame++) {
    dynamics.advance(1 / fps);
  }
  return dynamics;
}

List<double> _adjacentCrossfadeBands(double progress) {
  final bands = List<double>.filled(AudioSpectrumFrame.bandCount, 0.05);
  bands[4] = 1 - 0.95 * progress;
  bands[5] = 0.05 + 0.95 * progress;
  return bands;
}

List<double> _crossfadeCoefficients(double progress) {
  return RecordingMembraneModel.coefficientsFor(
    level: 0.78,
    bands: _adjacentCrossfadeBands(progress),
    flux: 0.45,
    spectrumMix: 1,
  );
}

List<double> _fallbackCoefficients(double level) {
  return RecordingMembraneModel.coefficientsFor(
    level: level,
    bands: List<double>.filled(AudioSpectrumFrame.bandCount, 0),
    flux: 0,
    spectrumMix: 0,
  );
}

List<double> _voiceCoefficients({required int hotBand}) {
  return RecordingMembraneModel.coefficientsFor(
    level: 0.78,
    bands: List<double>.filled(AudioSpectrumFrame.bandCount, 0.05)
      ..[hotBand] = 1,
    flux: 0.45,
    spectrumMix: 1,
  );
}

List<double> _targetRadii({
  required double level,
  required List<double> bands,
  required double flux,
}) {
  return RecordingMembranePainter.contourRadii(
    level: level,
    bands: bands,
    flux: flux,
    spectrumMix: 1,
  );
}

RecordingMembranePainter _membranePainter(WidgetTester tester) {
  return tester
          .widget<CustomPaint>(
            find.descendant(
              of: find.byType(RecordingDot),
              matching: find.byType(CustomPaint),
            ),
          )
          .painter!
      as RecordingMembranePainter;
}

List<double> _painterRadii(RecordingMembranePainter painter) {
  return RecordingMembranePainter.radiiFromCoefficients(painter.coefficients);
}

void _expectRadiiBounded(List<double> radii) {
  for (final radius in radii) {
    expect(radius.isFinite, isTrue);
    expect(
      radius,
      greaterThanOrEqualTo(RecordingMembranePainter.minCenterRadius - 1e-9),
    );
    expect(
      radius,
      lessThanOrEqualTo(RecordingMembranePainter.maxCenterRadius + 1e-9),
    );
    expect(
      radius + RecordingMembranePainter.strokeWidth / 2,
      lessThanOrEqualTo(13.4 + 1e-9),
    );
  }
}

List<int> _prominentCircularPeaks(List<double> values) {
  final threshold = math.max(0.08 * _range(values), 0.15);
  final peaks = <int>[];
  for (var index = 0; index < values.length; index++) {
    final previous = values[(index - 1 + values.length) % values.length];
    final current = values[index];
    final next = values[(index + 1) % values.length];
    if (current <= previous || current < next) continue;

    var leftValley = current;
    var rightValley = current;
    for (var distance = 1; distance <= 12; distance++) {
      leftValley = math.min(
        leftValley,
        values[(index - distance + values.length) % values.length],
      );
      rightValley = math.min(
        rightValley,
        values[(index + distance) % values.length],
      );
    }
    if (current - math.max(leftValley, rightValley) >= threshold) {
      peaks.add(index);
    }
  }
  return peaks;
}

int _circularSampleDistance(int first, int second, int length) {
  final direct = (first - second).abs();
  return math.min(direct, length - direct);
}

double _average(List<double> values) {
  return values.fold<double>(0, (sum, value) => sum + value) / values.length;
}

double _positiveDeformationAngle(List<double> radii) {
  final mean = _average(radii);
  var x = 0.0;
  var y = 0.0;
  for (var sample = 0; sample < radii.length; sample++) {
    final weight = math.max(0.0, radii[sample] - mean);
    final angle = -math.pi / 2 + sample * 2 * math.pi / radii.length;
    x += weight * math.cos(angle);
    y += weight * math.sin(angle);
  }
  return math.atan2(y, x);
}

double _unwrapNear(double angle, double reference) {
  var unwrapped = angle;
  while (unwrapped - reference > math.pi) {
    unwrapped -= 2 * math.pi;
  }
  while (unwrapped - reference < -math.pi) {
    unwrapped += 2 * math.pi;
  }
  return unwrapped;
}

double _range(List<double> values) {
  return values.reduce(math.max) - values.reduce(math.min);
}

double _maxDifference(List<double> first, List<double> second) {
  return List<double>.generate(
    first.length,
    (index) => (first[index] - second[index]).abs(),
    growable: false,
  ).reduce(math.max);
}

void _expectRadiiClose(List<double> actual, List<double> expected) {
  expect(actual, hasLength(expected.length));
  for (var index = 0; index < actual.length; index++) {
    expect(actual[index], closeTo(expected[index], 1e-9));
  }
}

AudioSpectrumFrame _spectrumFrame({
  required int hotBand,
  required int sequence,
}) {
  return AudioSpectrumFrame(
    bands: List<double>.filled(AudioSpectrumFrame.bandCount, 0.05)
      ..[hotBand] = 1,
    level: 0.78,
    flux: 0.45,
    activityDb: -22,
    sequence: sequence,
  );
}

Widget _recordingDot({
  required double level,
  AudioSpectrumFrame? spectrumFrame,
}) {
  return MaterialApp(
    home: Center(
      child: RecordingDot(
        level: level,
        spectrumFrame: spectrumFrame ?? AudioSpectrumFrame.unavailable,
        fillColor: Colors.red,
        borderColor: Colors.white,
      ),
    ),
  );
}
