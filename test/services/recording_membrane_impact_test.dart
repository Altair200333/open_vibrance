import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:open_vibrance/services/recording_membrane.dart';
import 'package:open_vibrance/services/recording_membrane_impact.dart';

void main() {
  group('RecordingMembraneImpactController', () {
    const pastRefractory =
        RecordingMembraneImpactController.refractorySeconds + 0.001;
    test('silence never emits an impact', () {
      final controller = RecordingMembraneImpactController();
      final silence = _target(level: 0, flux: 0, novelty: 0, amplitude: 0);

      for (var frame = 0; frame < 120; frame++) {
        expect(controller.processTarget(silence), isNull);
        expect(controller.advance(1 / 60), isFalse);
      }

      expect(controller.impacts, isEmpty);
      expect(controller.lastDrive, 0);
      expect(controller.lastShapeKick, 0);
    });

    test('held input emits once and requires a low-drive rearm', () {
      final controller = RecordingMembraneImpactController();
      final held = _target();
      var emissions = 0;

      if (controller.processTarget(held) != null) emissions++;
      for (var frame = 0; frame < 30; frame++) {
        controller.advance(0.05);
        if (controller.processTarget(held) != null) emissions++;
      }

      expect(emissions, 1);
      expect(controller.impacts, isEmpty);
      expect(controller.isArmed, isFalse);

      expect(controller.processTarget(_lowDriveTarget()), isNull);
      expect(controller.isArmed, isTrue);
      controller.advance(RecordingMembraneImpactController.refractorySeconds);
      expect(controller.processTarget(held), isNotNull);
    });

    test('identical inputs and time steps are exactly deterministic', () {
      final first = RecordingMembraneImpactController();
      final second = RecordingMembraneImpactController();
      final sequence = [
        _target(phase: -0.7, highBandShare: 0.2),
        _lowDriveTarget(phase: -0.7),
        _target(phase: 1.1, highBandShare: 0.8, flux: 0.9),
        _lowDriveTarget(phase: 1.1),
        _target(phase: 2.4, novelty: 0.11),
      ];

      for (final target in sequence) {
        final firstEmission = first.processTarget(target);
        final secondEmission = second.processTarget(target);
        _expectImpactEqual(firstEmission, secondEmission);
        first.advance(pastRefractory);
        second.advance(pastRefractory);
        _expectImpactListsEqual(first.impacts, second.impacts);
      }

      expect(first.lastDrive, second.lastDrive);
      expect(first.lastShapeKick, second.lastShapeKick);
    });

    test('refractory interval blocks rapid retriggers', () {
      final controller = RecordingMembraneImpactController();
      final high = _target();

      expect(controller.processTarget(high), isNotNull);
      controller.processTarget(_lowDriveTarget());
      controller.advance(
        RecordingMembraneImpactController.refractorySeconds / 2,
      );
      expect(controller.processTarget(high), isNull);

      controller.advance(
        RecordingMembraneImpactController.refractorySeconds / 2 + 0.001,
      );
      final second = controller.processTarget(high);
      expect(second, isNotNull);
      expect(second!.id, 1);
    });

    test('ordinary speech valley rearms without requiring silence', () {
      final controller = RecordingMembraneImpactController();
      final high = _target();

      expect(controller.processTarget(high), isNotNull);
      expect(
        controller.processTarget(_target(flux: 0.25, novelty: 0.04)),
        isNull,
      );
      expect(controller.lastDrive, greaterThan(0.18));
      expect(
        controller.lastDrive,
        lessThanOrEqualTo(RecordingMembraneImpactController.rearmDrive),
      );
      expect(controller.isArmed, isTrue);

      controller.advance(pastRefractory);
      expect(controller.processTarget(high), isNotNull);
    });

    test('threshold chatter cannot exceed refractory cadence', () {
      final controller = RecordingMembraneImpactController();
      final high = _target();
      final valley = _target(flux: 0.25, novelty: 0.04);
      final emissionTimes = <double>[];
      var elapsed = 0.0;

      if (controller.processTarget(high) != null) emissionTimes.add(elapsed);
      for (var frame = 0; frame < 100; frame++) {
        controller.processTarget(valley);
        controller.advance(0.03);
        elapsed += 0.03;
        if (controller.processTarget(high) != null) {
          emissionTimes.add(elapsed);
        }
      }

      expect(emissionTimes.length, greaterThan(1));
      for (var index = 1; index < emissionTimes.length; index++) {
        expect(
          emissionTimes[index] - emissionTimes[index - 1],
          greaterThanOrEqualTo(
            RecordingMembraneImpactController.refractorySeconds - 1e-9,
          ),
        );
      }
    });

    test('keeps at most two newest impacts', () {
      final controller = RecordingMembraneImpactController();
      final high = _target();

      expect(controller.processTarget(high)!.id, 0);
      for (var event = 1; event < 5; event++) {
        controller.processTarget(_lowDriveTarget());
        controller.advance(pastRefractory);
        expect(controller.processTarget(high)!.id, event);
      }

      expect(
        controller.impacts.map((impact) => impact.id),
        orderedEquals([3, 4]),
      );
      expect(
        controller.impacts.length,
        RecordingMembraneImpactController.maxImpacts,
      );
    });

    test('front expands, fade is bounded, and every impact settles', () {
      final controller = RecordingMembraneImpactController();
      final emitted = controller.processTarget(_target())!;
      final initialFront = emitted.frontRadius;

      expect(emitted.age, 0);
      expect(emitted.fade, 0);
      expect(emitted.isAlive, isTrue);

      controller.advance(0.03);
      final early = controller.impacts.single;
      expect(early.frontRadius, greaterThan(initialFront));
      expect(early.fade, greaterThan(0));
      expect(early.fade, lessThanOrEqualTo(early.strength));

      var previousFront = early.frontRadius;
      while (controller.hasActiveImpacts) {
        controller.advance(0.02);
        if (controller.hasActiveImpacts) {
          final current = controller.impacts.single;
          expect(current.frontRadius, greaterThanOrEqualTo(previousFront));
          expect(current.fade, inInclusiveRange(0, current.strength));
          previousFront = current.frontRadius;
        }
      }

      expect(controller.impacts, isEmpty);
      expect(
        controller.advance(RecordingMembraneImpactController.impactLifetime),
        isFalse,
      );
    });

    test('clear preserves detector state while reset starts a new session', () {
      final controller = RecordingMembraneImpactController();
      final high = _target();
      final first = controller.processTarget(high)!;
      expect(first.id, 0);

      controller.clear();
      expect(controller.impacts, isEmpty);
      expect(controller.processTarget(high), isNull);

      controller.reset();
      expect(controller.isArmed, isTrue);
      expect(controller.lastDrive, 0);
      expect(controller.lastShapeKick, 0);
      final afterReset = controller.processTarget(high)!;
      expect(afterReset.id, 0);
    });

    test('snapshots and exposed collections stay immutable', () {
      final controller = RecordingMembraneImpactController();
      controller.processTarget(_target());
      final before = controller.impacts.single;

      expect(() => controller.impacts.add(before), throwsUnsupportedError);
      controller.advance(0.05);

      expect(before.age, 0);
      expect(controller.impacts.single.age, closeTo(0.05, 1e-12));
      expect(identical(before, controller.impacts.single), isFalse);
    });

    test('shape target delta contributes to drive and impact direction', () {
      final controller = RecordingMembraneImpactController();
      controller.processTarget(
        _target(flux: 0, novelty: 0, amplitude: 0, phase: 0),
      );
      final stableDrive = controller.lastDrive;
      controller.processTarget(
        _target(flux: 0, novelty: 0, amplitude: 1.2, phase: 1.2),
      );

      expect(controller.lastShapeKick, greaterThan(0.5));
      expect(controller.lastDrive, greaterThan(stableDrive));

      controller.reset();
      final first = controller.processTarget(_target(phase: -0.8))!;
      controller.processTarget(_lowDriveTarget(phase: -0.8));
      controller.advance(pastRefractory);
      final second = controller.processTarget(_target(phase: 1.2))!;
      expect(_angleDistance(first.angle, second.angle), greaterThan(0.2));
    });

    test(
      'all emitted geometry and rendering values are bounded and finite',
      () {
        final controller = RecordingMembraneImpactController();
        final targets = [
          _target(
            level: 4,
            flux: 4,
            novelty: 4,
            highBandShare: 4,
            colorPhase: 80,
            amplitude: 3,
          ),
          _target(
            level: 1,
            flux: 1,
            novelty: 1,
            highBandShare: 1,
            colorPhase: -80,
            amplitude: 3,
            phase: 2,
          ),
        ];

        for (final target in targets) {
          controller.processTarget(target);
          controller.advance(pastRefractory);
          controller.processTarget(_lowDriveTarget());
          controller.advance(pastRefractory);
        }

        for (final impact in controller.impacts) {
          expect(impact.id, greaterThanOrEqualTo(0));
          expect(impact.age.isFinite, isTrue);
          expect(impact.strength, inInclusiveRange(0.40, 1));
          expect(impact.angle.isFinite, isTrue);
          expect(impact.angle, inInclusiveRange(-math.pi, math.pi));
          expect(impact.origin.x.isFinite, isTrue);
          expect(impact.origin.y.isFinite, isTrue);
          expect(impact.origin.radius, lessThanOrEqualTo(0.40 + 1e-12));
          expect(impact.eccentricity, inInclusiveRange(0, 0.55));
          expect(impact.colorPhase, inInclusiveRange(-math.pi, math.pi));
          expect(impact.highBandShare, inInclusiveRange(0, 1));
          expect(impact.progress, inInclusiveRange(0, 1));
          expect(impact.frontRadius, inInclusiveRange(0.055, 1.775));
          expect(impact.frontRadiusFor(10), inInclusiveRange(0.55, 17.75));
          expect(impact.fade, inInclusiveRange(0, impact.strength));
        }

        final ages = controller.impacts.map((impact) => impact.age).toList();
        expect(controller.advance(double.nan), controller.hasActiveImpacts);
        expect(controller.impacts.map((impact) => impact.age), ages);
        expect(controller.advance(double.negativeInfinity), isTrue);
      },
    );
  });
}

RecordingMembraneTarget _target({
  double level = 0.8,
  double flux = 0.8,
  double novelty = 0.10,
  double highBandShare = 0.5,
  double colorPhase = 0.25,
  double amplitude = 0.9,
  double phase = 0,
}) {
  final safeLevel = level.isFinite ? level.clamp(0.0, 1.0).toDouble() : 0.0;
  final coefficients = List<double>.filled(
    RecordingMembraneModel.coefficientCount,
    0,
  );
  coefficients[0] = RecordingMembraneModel.baseRadiusFor(safeLevel);
  coefficients[RecordingMembraneModel.cosineIndex(1)] =
      amplitude * math.cos(phase);
  coefficients[RecordingMembraneModel.sineIndex(1)] =
      amplitude * math.sin(phase);
  coefficients[RecordingMembraneModel.cosineIndex(3)] =
      0.35 * amplitude * math.cos(3 * phase + 0.4);
  coefficients[RecordingMembraneModel.sineIndex(3)] =
      0.35 * amplitude * math.sin(3 * phase + 0.4);
  return RecordingMembraneTarget(
    coefficients: coefficients,
    level: level,
    flux: flux,
    contrast: 0.2,
    novelty: novelty,
    highBandShare: highBandShare,
    colorPhase: colorPhase,
    requestedReach: amplitude.abs(),
    actualReach: amplitude.abs(),
  );
}

RecordingMembraneTarget _lowDriveTarget({double phase = 0}) =>
    _target(flux: 0, novelty: 0, amplitude: 0.9, phase: phase);

void _expectImpactEqual(
  RecordingMembraneImpactSnapshot? first,
  RecordingMembraneImpactSnapshot? second,
) {
  expect(first == null, second == null);
  if (first == null || second == null) return;
  expect(first.id, second.id);
  expect(first.age, second.age);
  expect(first.strength, second.strength);
  expect(first.angle, second.angle);
  expect(first.origin.x, second.origin.x);
  expect(first.origin.y, second.origin.y);
  expect(first.eccentricity, second.eccentricity);
  expect(first.colorPhase, second.colorPhase);
  expect(first.highBandShare, second.highBandShare);
  expect(first.lifetime, second.lifetime);
  expect(first.frontRadius, second.frontRadius);
  expect(first.fade, second.fade);
}

void _expectImpactListsEqual(
  List<RecordingMembraneImpactSnapshot> first,
  List<RecordingMembraneImpactSnapshot> second,
) {
  expect(first.length, second.length);
  for (var index = 0; index < first.length; index++) {
    _expectImpactEqual(first[index], second[index]);
  }
}

double _angleDistance(double first, double second) {
  var difference = (first - second).abs() % (2 * math.pi);
  if (difference > math.pi) difference = 2 * math.pi - difference;
  return difference;
}
