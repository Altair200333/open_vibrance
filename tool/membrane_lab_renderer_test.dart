import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_vibrance/services/recording_membrane_impact.dart';
import 'package:open_vibrance/widgets/dot_indicator/recording_dot.dart';

void main() {
  const inputPath = String.fromEnvironment('MEMBRANE_LAB_INPUT');
  const outputPath = String.fromEnvironment('MEMBRANE_LAB_OUTPUT');
  const impactInputPath = String.fromEnvironment('MEMBRANE_LAB_IMPACT_INPUT');
  const impactOutputPath = String.fromEnvironment('MEMBRANE_LAB_IMPACT_OUTPUT');
  if (inputPath.isEmpty ||
      outputPath.isEmpty ||
      impactInputPath.isEmpty ||
      impactOutputPath.isEmpty) {
    test(
      'membrane lab renderer is invoked only by tool/membrane_lab.dart',
      () {},
    );
    return;
  }

  testWidgets('renders the production painter contact and impact sheets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final decoded = jsonDecode(File(inputPath).readAsStringSync()) as List;
    final snapshots = decoded
        .cast<Map<String, dynamic>>()
        .map(_PainterSnapshot.fromJson)
        .toList(growable: false);
    final impactPayload = _ImpactPayload.fromJson(
      jsonDecode(File(impactInputPath).readAsStringSync())
          as Map<String, dynamic>,
    );
    final contactKey = GlobalKey();
    final impactKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ColoredBox(
          color: const Color(0xFF070509),
          child: SizedBox(
            width: 1200,
            height: 960,
            child: Column(
              children: [
                _sheetBoundary(
                  key: contactKey,
                  child: Wrap(
                    children: [
                      for (final snapshot in snapshots.take(24))
                        _SnapshotCell(snapshot: snapshot),
                    ],
                  ),
                ),
                _sheetBoundary(
                  key: impactKey,
                  child: _ImpactGrid(payload: impactPayload),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final encoded = await Future.wait([
      _boundaryPng(contactKey),
      _boundaryPng(impactKey),
    ]);
    final outputs = [File(outputPath), File(impactOutputPath)];
    for (final output in outputs) {
      output.parent.createSync(recursive: true);
    }
    outputs[0].writeAsBytesSync(encoded[0]);
    outputs[1].writeAsBytesSync(encoded[1]);
    expect(outputs[0].lengthSync(), greaterThan(1000));
    expect(outputs[1].lengthSync(), greaterThan(1000));
  });
}

Widget _sheetBoundary({required GlobalKey key, required Widget child}) =>
    RepaintBoundary(
      key: key,
      child: ColoredBox(
        color: const Color(0xFF070509),
        child: SizedBox(width: 1200, height: 480, child: child),
      ),
    );

Future<Uint8List> _boundaryPng(GlobalKey key) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    expect(data, isNotNull);
    return Uint8List.fromList(
      data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  } finally {
    image.dispose();
  }
}

final class _PainterSnapshot {
  const _PainterSnapshot({
    required this.level,
    required this.flux,
    required this.novelty,
    required this.colorPhase,
    required this.baselineCoefficients,
    required this.candidateCoefficients,
    required this.candidateVelocity,
    required this.candidateHistory,
    required this.impacts,
  });

  final double level;
  final double flux;
  final double novelty;
  final double colorPhase;
  final List<double> baselineCoefficients;
  final List<double> candidateCoefficients;
  final List<double> candidateVelocity;
  final List<List<double>> candidateHistory;
  final List<RecordingMembraneImpactSnapshot> impacts;

  factory _PainterSnapshot.fromJson(Map<String, dynamic> json) =>
      _PainterSnapshot(
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
        impacts: ((json['impacts'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(_impactFromJson)
            .toList(growable: false),
      );
}

RecordingMembraneImpactSnapshot _impactFromJson(Map<String, dynamic> json) =>
    RecordingMembraneImpactSnapshot(
      id: (json['id'] as num).toInt(),
      age: (json['age'] as num).toDouble(),
      strength: (json['strength'] as num).toDouble(),
      angle: (json['angle'] as num).toDouble(),
      origin: RecordingMembraneImpactOrigin(
        x: (json['origin_x'] as num).toDouble(),
        y: (json['origin_y'] as num).toDouble(),
      ),
      eccentricity: (json['eccentricity'] as num).toDouble(),
      colorPhase: (json['color_phase'] as num).toDouble(),
      highBandShare: (json['high_band_share'] as num).toDouble(),
      lifetime: (json['lifetime'] as num).toDouble(),
    );

final class _ImpactPayload {
  const _ImpactPayload({required this.events});

  final List<_ImpactEvent> events;

  factory _ImpactPayload.fromJson(Map<String, dynamic> json) => _ImpactPayload(
    events: (json['events'] as List)
        .cast<Map<String, dynamic>>()
        .map(_ImpactEvent.fromJson)
        .toList(growable: false),
  );
}

final class _ImpactEvent {
  const _ImpactEvent({
    required this.tier,
    required this.recording,
    required this.id,
    required this.emissionTime,
    required this.strength,
    required this.snapshots,
  });

  final String tier;
  final String recording;
  final int id;
  final double emissionTime;
  final double strength;
  final List<_ImpactGridSnapshot> snapshots;

  factory _ImpactEvent.fromJson(Map<String, dynamic> json) => _ImpactEvent(
    tier: json['tier'] as String,
    recording: json['recording'] as String,
    id: (json['impact_id'] as num).toInt(),
    emissionTime: (json['emission_time'] as num).toDouble(),
    strength: (json['strength'] as num).toDouble(),
    snapshots: (json['snapshots'] as List)
        .cast<Map<String, dynamic>>()
        .map(_ImpactGridSnapshot.fromJson)
        .toList(growable: false),
  );
}

final class _ImpactGridSnapshot {
  const _ImpactGridSnapshot({
    required this.requestedOffsetMs,
    required this.actualOffsetMs,
    required this.painter,
  });

  final int requestedOffsetMs;
  final int actualOffsetMs;
  final _PainterSnapshot painter;

  factory _ImpactGridSnapshot.fromJson(Map<String, dynamic> json) =>
      _ImpactGridSnapshot(
        requestedOffsetMs: (json['requested_offset_ms'] as num).toInt(),
        actualOffsetMs: (json['actual_offset_ms'] as num).toInt(),
        painter: _PainterSnapshot.fromJson(json),
      );
}

class _ImpactGrid extends StatelessWidget {
  const _ImpactGrid({required this.payload});

  final _ImpactPayload payload;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var row = 0; row < 3; row++)
          if (row < payload.events.length)
            _ImpactRow(event: payload.events[row])
          else
            const SizedBox(width: 1200, height: 160),
      ],
    );
  }
}

class _ImpactRow extends StatelessWidget {
  const _ImpactRow({required this.event});

  final _ImpactEvent event;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 1200,
      height: 160,
      child: Row(
        children: [
          for (var column = 0; column < 8; column++)
            if (column < event.snapshots.length)
              _ImpactCell(
                event: event,
                snapshot: event.snapshots[column],
                showEventLabel: column == 0,
              )
            else
              const SizedBox(width: 150, height: 160),
        ],
      ),
    );
  }
}

class _ImpactCell extends StatelessWidget {
  const _ImpactCell({
    required this.event,
    required this.snapshot,
    required this.showEventLabel,
  });

  final _ImpactEvent event;
  final _ImpactGridSnapshot snapshot;
  final bool showEventLabel;

  @override
  Widget build(BuildContext context) {
    final painter = snapshot.painter;
    final offset = snapshot.actualOffsetMs;
    return SizedBox(
      width: 150,
      height: 160,
      child: Column(
        children: [
          SizedBox(
            height: 28,
            child: Center(
              child: Text(
                showEventLabel
                    ? '${event.tier.toUpperCase()} · strength ${event.strength.toStringAsFixed(2)}'
                    : '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFC7C0CB), fontSize: 9),
              ),
            ),
          ),
          Expanded(
            child: _ScaledIndicator(
              painter: RecordingMembranePainter(
                coefficients: painter.candidateCoefficients,
                velocity: painter.candidateVelocity,
                history: painter.candidateHistory,
                impacts: painter.impacts,
                level: painter.level,
                flux: painter.flux,
                novelty: painter.novelty,
                colorPhase: painter.colorPhase,
                fillColor: const Color(0xFFE9334C),
                strokeColor: Colors.white,
              ),
            ),
          ),
          SizedBox(
            height: 24,
            child: Text(
              '${offset >= 0 ? '+' : ''}$offset ms',
              style: TextStyle(
                color:
                    snapshot.requestedOffsetMs == 0
                        ? const Color(0xFFFF9BC4)
                        : const Color(0xFFA79DA9),
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SnapshotCell extends StatelessWidget {
  const _SnapshotCell({required this.snapshot});

  final _PainterSnapshot snapshot;

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
                impacts: snapshot.impacts,
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
