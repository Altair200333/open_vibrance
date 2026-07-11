import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_vibrance/services/recording_membrane_impact.dart';
import 'package:open_vibrance/widgets/dot_indicator/recording_dot.dart';

void main() {
  group('RecordingMembranePainter impacts', () {
    testWidgets('accepts controller snapshots and paints without throwing', (
      tester,
    ) async {
      final coefficients = _circleCoefficients();
      final controller = _visibleImpactController(coefficients);
      final painter = _painter(
        coefficients: coefficients,
        impacts: controller.impacts,
      );

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);

      expect(controller.impacts, hasLength(1));
      expect(
        () => painter.paint(canvas, const ui.Size(30, 30)),
        returnsNormally,
      );
      recorder.endRecording().dispose();
    });

    test('shouldRepaint tracks impact list and age', () {
      final coefficients = _circleCoefficients();
      final controller = _visibleImpactController(coefficients);
      final withoutImpact = _painter(coefficients: coefficients);
      final first = _painter(
        coefficients: coefficients,
        impacts: controller.impacts,
      );
      final identicalState = _painter(
        coefficients: coefficients,
        impacts: controller.impacts,
      );

      expect(first.shouldRepaint(withoutImpact), isTrue);
      expect(identicalState.shouldRepaint(first), isFalse);

      controller.advance(0.01);
      final aged = _painter(
        coefficients: coefficients,
        impacts: controller.impacts,
      );
      expect(aged.shouldRepaint(first), isTrue);
      expect(withoutImpact.shouldRepaint(aged), isTrue);
    });

    test('impacts do not alter membrane coefficients or outer geometry', () {
      final coefficients = _circleCoefficients();
      final original = List<double>.of(coefficients);
      final radiiBefore = RecordingMembraneModel.radiiFromCoefficients(
        coefficients,
      );
      final controller = _visibleImpactController(coefficients);
      final withoutImpact = _painter(coefficients: coefficients);
      final withImpact = _painter(
        coefficients: coefficients,
        impacts: controller.impacts,
      );

      expect(coefficients, original);
      expect(withImpact.coefficients, withoutImpact.coefficients);
      expect(
        RecordingMembranePainter.radiiFromCoefficients(withImpact.coefficients),
        radiiBefore,
      );
      expect(
        RecordingMembranePainter.radiiFromCoefficients(
          withoutImpact.coefficients,
        ),
        radiiBefore,
      );
    });

    testWidgets('30px impact changes pixels only inside or near contour', (
      tester,
    ) async {
      final coefficients = _circleCoefficients();
      final baseRadius = coefficients.first;
      final controller = _visibleImpactController(coefficients);
      final rendered = await tester.runAsync(() async {
        final withoutImpact = await _render(
          _painter(coefficients: coefficients),
        );
        final withImpact = await _render(
          _painter(coefficients: coefficients, impacts: controller.impacts),
        );
        return (withoutImpact, withImpact);
      });
      expect(rendered, isNotNull);
      final (withoutImpact, withImpact) = rendered!;

      var changed = 0;
      var changedInterior = 0;
      var changedFarOutside = 0;
      for (var y = 0; y < 30; y++) {
        for (var x = 0; x < 30; x++) {
          final offset = (y * 30 + x) * 4;
          var differs = false;
          for (var channel = 0; channel < 4; channel++) {
            if (withoutImpact[offset + channel] !=
                withImpact[offset + channel]) {
              differs = true;
              break;
            }
          }
          if (!differs) continue;

          changed++;
          final distance = math.sqrt(
            math.pow(x + 0.5 - 15, 2) + math.pow(y + 0.5 - 15, 2),
          );
          if (distance < baseRadius - 1) changedInterior++;
          if (distance > baseRadius + 2.5) changedFarOutside++;
        }
      }

      expect(changed, greaterThan(10));
      expect(changedInterior, greaterThan(2));
      expect(changedFarOutside, 0);
    });
  });
}

List<double> _circleCoefficients() {
  final coefficients = List<double>.filled(
    RecordingMembraneModel.coefficientCount,
    0,
  );
  coefficients[0] = RecordingMembraneModel.baseRadiusFor(0.8);
  return coefficients;
}

RecordingMembraneImpactController _visibleImpactController(
  List<double> coefficients,
) {
  final controller = RecordingMembraneImpactController();
  final emitted = controller.processTarget(
    RecordingMembraneTarget(
      coefficients: coefficients,
      level: 0.8,
      flux: 0.9,
      contrast: 0.2,
      novelty: 0.10,
      highBandShare: 0.65,
      colorPhase: 0.7,
      requestedReach: 3,
      actualReach: 3,
    ),
  );
  expect(emitted, isNotNull);
  controller.advance(0.10);
  return controller;
}

RecordingMembranePainter _painter({
  required List<double> coefficients,
  List<RecordingMembraneImpactSnapshot> impacts = const [],
}) => RecordingMembranePainter(
  coefficients: coefficients,
  impacts: impacts,
  level: 0,
  flux: 0,
  novelty: 0,
  colorPhase: 0.7,
  fillColor: const Color(0xFFE9334C),
  strokeColor: Colors.white,
);

Future<Uint8List> _render(RecordingMembranePainter painter) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  painter.paint(canvas, const ui.Size(30, 30));
  final picture = recorder.endRecording();
  final image = await picture.toImage(30, 30);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  expect(data, isNotNull);
  final pixels = Uint8List.fromList(
    data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
  image.dispose();
  picture.dispose();
  return pixels;
}
