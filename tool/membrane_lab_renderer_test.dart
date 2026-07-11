import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_vibrance/widgets/dot_indicator/recording_dot.dart';

void main() {
  const inputPath = String.fromEnvironment('MEMBRANE_LAB_INPUT');
  const outputPath = String.fromEnvironment('MEMBRANE_LAB_OUTPUT');
  if (inputPath.isEmpty || outputPath.isEmpty) {
    test(
      'membrane lab renderer is invoked only by tool/membrane_lab.dart',
      () {},
    );
    return;
  }

  testWidgets('renders the production painter contact sheet', (tester) async {
    tester.view.physicalSize = const Size(1200, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final decoded = jsonDecode(File(inputPath).readAsStringSync()) as List;
    final snapshots = decoded
        .cast<Map<String, dynamic>>()
        .map(_LabSnapshot.fromJson)
        .toList(growable: false);
    final boundaryKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ColoredBox(
          color: const Color(0xFF070509),
          child: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: ColoredBox(
                color: const Color(0xFF070509),
                child: SizedBox(
                  width: 1200,
                  height: 480,
                  child: Wrap(
                    children: [
                      for (final snapshot in snapshots.take(24))
                        _SnapshotCell(snapshot: snapshot),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    expect(data, isNotNull);
    final output = File(outputPath)..parent.createSync(recursive: true);
    output.writeAsBytesSync(data!.buffer.asUint8List(), flush: true);
    expect(output.lengthSync(), greaterThan(1000));
  });
}

final class _LabSnapshot {
  const _LabSnapshot({
    required this.level,
    required this.flux,
    required this.novelty,
    required this.colorPhase,
    required this.baselineCoefficients,
    required this.candidateCoefficients,
    required this.candidateVelocity,
    required this.candidateHistory,
  });

  final double level;
  final double flux;
  final double novelty;
  final double colorPhase;
  final List<double> baselineCoefficients;
  final List<double> candidateCoefficients;
  final List<double> candidateVelocity;
  final List<List<double>> candidateHistory;

  factory _LabSnapshot.fromJson(Map<String, dynamic> json) => _LabSnapshot(
    level: (json['level'] as num).toDouble(),
    flux: (json['flux'] as num).toDouble(),
    novelty: (json['novelty'] as num).toDouble(),
    colorPhase: (json['color_phase'] as num).toDouble(),
    baselineCoefficients: _doubles(json['baseline_coefficients']),
    candidateCoefficients: _doubles(json['candidate_coefficients']),
    candidateVelocity: _doubles(json['candidate_velocity']),
    candidateHistory: (json['candidate_history'] as List)
        .map(_doubles)
        .toList(growable: false),
  );
}

class _SnapshotCell extends StatelessWidget {
  const _SnapshotCell({required this.snapshot});

  final _LabSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 120,
      child: Row(
        children: [
          Expanded(
            child: _ScaledIndicator(
              painter: _LegacyPainter(
                coefficients: snapshot.baselineCoefficients,
              ),
            ),
          ),
          Expanded(
            child: _ScaledIndicator(
              painter: RecordingMembranePainter(
                coefficients: snapshot.candidateCoefficients,
                velocity: snapshot.candidateVelocity,
                history: snapshot.candidateHistory,
                level: snapshot.level,
                flux: snapshot.flux,
                novelty: snapshot.novelty,
                colorPhase: snapshot.colorPhase,
                fillColor: const Color(0xFFE9334C),
                strokeColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScaledIndicator extends StatelessWidget {
  const _ScaledIndicator({required this.painter});

  final CustomPainter painter;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Transform.scale(
        scale: 3.35,
        child: SizedBox.square(
          dimension: RecordingMembranePainter.canvasSize,
          child: CustomPaint(painter: painter),
        ),
      ),
    );
  }
}

final class _LegacyPainter extends CustomPainter {
  _LegacyPainter({required this.coefficients});

  final List<double> coefficients;

  @override
  void paint(Canvas canvas, Size size) {
    final radii = RecordingMembraneModel.radiiFromCoefficients(coefficients);
    final center = size.center(Offset.zero);
    final path = Path();
    for (var sample = 0; sample < radii.length; sample++) {
      final angle = -math.pi / 2 + sample * 2 * math.pi / radii.length;
      final point =
          center + Offset(math.cos(angle), math.sin(angle)) * radii[sample];
      if (sample == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.fill
        ..color = const Color(0xFFE9334C)
        ..isAntiAlias = true,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant _LegacyPainter oldDelegate) => true;
}

List<double> _doubles(dynamic values) =>
    (values as List).map((value) => (value as num).toDouble()).toList();
