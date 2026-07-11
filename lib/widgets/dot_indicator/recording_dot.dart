import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:open_vibrance/services/audio_spectrum_analyzer.dart';
import 'package:open_vibrance/services/recording_membrane.dart';

export 'package:open_vibrance/services/recording_membrane.dart'
    show
        RecordingMembraneDynamics,
        RecordingMembraneMapper,
        RecordingMembraneModel,
        RecordingMembraneTarget;

class RecordingDot extends StatefulWidget {
  const RecordingDot({
    super.key,
    required this.level,
    required this.spectrumFrame,
    required this.fillColor,
    required this.borderColor,
  });

  final double level;
  final AudioSpectrumFrame spectrumFrame;
  final Color fillColor;
  final Color borderColor;

  @override
  State<RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<RecordingDot>
    with SingleTickerProviderStateMixin {
  static const double _historySampleSeconds = 0.048;
  static const int _historyCapacity = 7;

  late final RecordingMembraneMapper _mapper;
  late final RecordingMembraneDynamics _dynamics;
  late final Ticker _ticker;
  late RecordingMembraneTarget _visualTarget;
  final List<List<double>> _history = [];
  Duration? _lastTickTime;
  int? _lastSpectrumSequence;
  bool _hadSpectrum = false;
  double _historyElapsed = 0;

  @override
  void initState() {
    super.initState();
    _mapper = RecordingMembraneMapper();
    _visualTarget = _resolveTarget();
    _dynamics = RecordingMembraneDynamics(_visualTarget.coefficients);
    _history.add(_dynamics.snapshot);
    _ticker = createTicker(_onTick);
  }

  @override
  void didUpdateWidget(covariant RecordingDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _visualTarget = _resolveTarget();
    if (_dynamics.retarget(_visualTarget.coefficients)) _ensureTickerRunning();
  }

  RecordingMembraneTarget _resolveTarget() {
    final spectrum = widget.spectrumFrame;
    if (!spectrum.hasSpectrum) {
      _hadSpectrum = false;
      return _mapper.map(
        level: widget.level,
        bands: List<double>.filled(AudioSpectrumFrame.bandCount, 0),
        flux: 0,
        spectrumMix: 0,
      );
    }

    final previousSequence = _lastSpectrumSequence;
    final isNewFrame = !_hadSpectrum || previousSequence != spectrum.sequence;
    if (!isNewFrame) return _visualTarget;

    if (_hadSpectrum &&
        previousSequence != null &&
        spectrum.sequence < previousSequence) {
      _mapper.reset();
      _history.clear();
      _historyElapsed = 0;
    }
    final sequenceDelta =
        _hadSpectrum &&
                previousSequence != null &&
                spectrum.sequence > previousSequence
            ? spectrum.sequence - previousSequence
            : 1;
    _hadSpectrum = true;
    _lastSpectrumSequence = spectrum.sequence;
    return _mapper.map(
      level: spectrum.level,
      bands: spectrum.bands,
      flux: spectrum.flux,
      elapsedSeconds:
          sequenceDelta * RecordingMembraneMapper.defaultFrameSeconds,
    );
  }

  void _ensureTickerRunning() {
    if (_ticker.isActive) return;
    _lastTickTime = null;
    _ticker.start();
  }

  void _onTick(Duration elapsed) {
    final previous = _lastTickTime;
    final dt = switch (previous) {
      final last? => (elapsed - last).inMicroseconds / 1e6,
      null => 1 / 60,
    };
    _lastTickTime = elapsed;

    if (dt > RecordingMembraneDynamics.maxIntegratedSeconds) {
      _history.clear();
      _historyElapsed = 0;
    }
    final stillMoving = _dynamics.advance(dt);
    _captureHistory(dt);
    if (!mounted) return;
    setState(() {});
    if (!stillMoving) {
      _ticker.stop();
      _lastTickTime = null;
    }
  }

  void _captureHistory(double dt) {
    _historyElapsed += dt;
    if (_historyElapsed < _historySampleSeconds && _history.isNotEmpty) return;
    _historyElapsed %= _historySampleSeconds;
    _history.insert(0, _dynamics.snapshot);
    if (_history.length > _historyCapacity) {
      _history.removeRange(_historyCapacity, _history.length);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: RecordingMembranePainter.canvasSize,
        child: IgnorePointer(
          child: CustomPaint(
            painter: RecordingMembranePainter(
              coefficients: _dynamics.snapshot,
              velocity: _dynamics.velocity,
              history: _history,
              level: _visualTarget.level,
              flux: _visualTarget.flux,
              novelty: _visualTarget.novelty,
              colorPhase: _visualTarget.colorPhase,
              fillColor: widget.fillColor,
              strokeColor: widget.borderColor,
            ),
          ),
        ),
      ),
    );
  }
}

class RecordingMembranePainter extends CustomPainter {
  RecordingMembranePainter({
    required List<double> coefficients,
    List<double>? velocity,
    List<List<double>> history = const [],
    this.level = 0,
    this.flux = 0,
    this.novelty = 0,
    this.colorPhase = -math.pi / 2,
    required this.fillColor,
    required this.strokeColor,
  }) : coefficients = List<double>.unmodifiable(
         RecordingMembraneModel.validatedCoefficients(coefficients),
       ),
       velocity = List<double>.unmodifiable(
         RecordingMembraneModel.validatedCoefficients(
           velocity ??
               List<double>.filled(RecordingMembraneModel.coefficientCount, 0),
         ),
       ),
       history = List<List<double>>.unmodifiable(
         history.map(
           (frame) => List<double>.unmodifiable(
             RecordingMembraneModel.validatedCoefficients(frame),
           ),
         ),
       );

  static const double canvasSize = 30;
  static const double strokeWidth = 1.0;
  static const int contourSampleCount =
      RecordingMembraneModel.contourSampleCount;
  static const int modeCount = RecordingMembraneModel.modeCount;
  static const double minCenterRadius = RecordingMembraneModel.minCenterRadius;
  static const double maxCenterRadius = RecordingMembraneModel.maxCenterRadius;

  final List<double> coefficients;
  final List<double> velocity;
  final List<List<double>> history;
  final double level;
  final double flux;
  final double novelty;
  final double colorPhase;
  final Color fillColor;
  final Color strokeColor;

  static List<double> contourRadii({
    required double level,
    required List<double> bands,
    required double flux,
    required double spectrumMix,
  }) => RecordingMembraneModel.contourRadii(
    level: level,
    bands: bands,
    flux: flux,
    spectrumMix: spectrumMix,
  );

  static List<double> radiiFromCoefficients(List<double> coefficients) =>
      RecordingMembraneModel.radiiFromCoefficients(coefficients);

  @override
  void paint(Canvas canvas, Size size) {
    final radii = radiiFromCoefficients(coefficients);
    final center = size.center(Offset.zero);
    final path = _pathForRadii(radii, center);
    final shaderBounds = Rect.fromCircle(
      center: center,
      radius: maxCenterRadius,
    );
    final safeLevel = _unit(level);
    final safeFlux = _unit(flux);
    final safeNovelty = _unit(novelty / 0.12);
    final activity = _unit(
      0.30 * safeLevel + 0.45 * safeNovelty + 0.25 * safeFlux,
    );
    final baseRadius = coefficients[0].clamp(minCenterRadius, maxCenterRadius);
    final velocityValues = RecordingMembraneModel.periodicValues(velocity);
    final palette = _edgePalette(
      radii: radii,
      velocityValues: velocityValues,
      baseRadius: baseRadius,
    );

    canvas.save();
    try {
      canvas.clipRect(Offset.zero & size);

      if (activity > 0.01) {
        final glowPaint =
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.8
              ..strokeJoin = StrokeJoin.round
              ..strokeCap = StrokeCap.round
              ..shader = SweepGradient(
                colors: palette.glowColors,
                stops: palette.stops,
                transform: GradientRotation(colorPhase),
              ).createShader(shaderBounds)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.35)
              ..isAntiAlias = true;
        canvas.drawPath(path, glowPaint);
      }

      final bodyGradient = RadialGradient(
        center: Alignment(
          0.14 * math.cos(colorPhase),
          0.14 * math.sin(colorPhase),
        ),
        radius: 0.96,
        colors: [
          _tone(fillColor, lightnessFactor: 0.40).withValues(alpha: 0.96),
          _tone(fillColor, lightnessFactor: 0.82).withValues(alpha: 0.98),
          _tone(
            fillColor,
            hueShift: -10,
            lightnessDelta: 0.10,
          ).withValues(alpha: 1),
        ],
        stops: const [0, 0.66, 1],
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.fill
          ..shader = bodyGradient.createShader(shaderBounds)
          ..isAntiAlias = true,
      );

      if (activity > 0.01) {
        canvas.save();
        canvas.clipPath(path);
        final disturbancePaint =
            Paint()
              ..style = PaintingStyle.fill
              ..blendMode = BlendMode.screen
              ..shader = SweepGradient(
                colors: [
                  Colors.transparent,
                  _tone(
                    fillColor,
                    hueShift: -18,
                    lightnessDelta: 0.18,
                  ).withValues(alpha: 0.12 + 0.18 * activity),
                  Colors.transparent,
                  _tone(
                    fillColor,
                    hueShift: 34,
                    lightnessDelta: 0.12,
                  ).withValues(alpha: 0.10 + 0.20 * safeNovelty),
                  Colors.transparent,
                ],
                transform: GradientRotation(colorPhase),
              ).createShader(shaderBounds)
              ..isAntiAlias = true;
        canvas.drawRect(shaderBounds, disturbancePaint);

        final innerBandPaint =
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.2
              ..strokeJoin = StrokeJoin.round
              ..strokeCap = StrokeCap.round
              ..blendMode = BlendMode.screen
              ..shader = SweepGradient(
                colors: palette.innerColors,
                stops: palette.stops,
                transform: GradientRotation(colorPhase),
              ).createShader(shaderBounds)
              ..isAntiAlias = true;
        canvas.drawPath(path, innerBandPaint);
        _paintHistory(
          canvas: canvas,
          center: center,
          shaderBounds: shaderBounds,
          palette: palette,
          activity: activity,
          currentBaseRadius: baseRadius,
        );
        canvas.restore();
      }

      final rimPaint =
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth
            ..strokeJoin = StrokeJoin.round
            ..strokeCap = StrokeCap.round
            ..shader = SweepGradient(
              colors: palette.rimColors,
              stops: palette.stops,
              transform: GradientRotation(colorPhase),
            ).createShader(shaderBounds)
            ..isAntiAlias = true;
      canvas.drawPath(path, rimPaint);
    } finally {
      canvas.restore();
    }
  }

  void _paintHistory({
    required Canvas canvas,
    required Offset center,
    required Rect shaderBounds,
    required _MembranePalette palette,
    required double activity,
    required double currentBaseRadius,
  }) {
    const historyIndices = [0, 1, 3, 5];
    const insets = [0.65, 1.30, 2.05, 2.80];
    const scales = [0.86, 0.68, 0.50, 0.33];
    const widths = [0.62, 0.54, 0.46, 0.40];
    const alphas = [0.24, 0.17, 0.11, 0.07];

    for (var layer = historyIndices.length - 1; layer >= 0; layer--) {
      final index = historyIndices[layer];
      if (index >= history.length) continue;
      final old = history[index];
      final oldBase = old[0];
      final oldRadii = radiiFromCoefficients(old);
      final insetRadii = List<double>.generate(
        contourSampleCount,
        (sample) => math.max(
          1.8,
          currentBaseRadius -
              insets[layer] +
              scales[layer] * (oldRadii[sample] - oldBase),
        ),
        growable: false,
      );
      final alpha = alphas[layer] * activity;
      final colors = palette.innerColors
          .map((color) => color.withValues(alpha: alpha))
          .toList(growable: false);
      canvas.drawPath(
        _pathForRadii(insetRadii, center),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = widths[layer]
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round
          ..blendMode = BlendMode.screen
          ..shader = SweepGradient(
            colors: colors,
            stops: palette.stops,
            transform: GradientRotation(colorPhase),
          ).createShader(shaderBounds)
          ..isAntiAlias = true,
      );
    }
  }

  _MembranePalette _edgePalette({
    required List<double> radii,
    required List<double> velocityValues,
    required double baseRadius,
  }) {
    const stopCount = 24;
    final warm = _tone(
      fillColor,
      hueShift: -15,
      saturationFactor: 1.08,
      lightnessDelta: 0.16,
    );
    final cool = _tone(
      fillColor,
      hueShift: 34,
      saturationFactor: 1.04,
      lightnessDelta: 0.13,
    );
    final stops = <double>[];
    final rim = <Color>[];
    final glow = <Color>[];
    final inner = <Color>[];
    for (var stop = 0; stop <= stopCount; stop++) {
      final sample = stop % stopCount * contourSampleCount ~/ stopCount;
      final angle = stop * 2 * math.pi / stopCount;
      final edge = _unit(
        0.55 * (radii[sample] - baseRadius).abs() / 4.8 +
            0.35 * velocityValues[sample].abs() / 24 +
            0.10 * _unit(flux),
      );
      final chroma = Color.lerp(warm, cool, 0.5 + 0.5 * math.cos(angle))!;
      stops.add(stop / stopCount);
      rim.add(
        Color.lerp(
          chroma,
          strokeColor,
          0.46 + 0.49 * edge,
        )!.withValues(alpha: 0.74 + 0.24 * edge),
      );
      glow.add(chroma.withValues(alpha: 0.07 + 0.11 * edge));
      inner.add(chroma.withValues(alpha: 0.10 + 0.12 * edge));
    }
    return _MembranePalette(
      stops: List<double>.unmodifiable(stops),
      rimColors: List<Color>.unmodifiable(rim),
      glowColors: List<Color>.unmodifiable(glow),
      innerColors: List<Color>.unmodifiable(inner),
    );
  }

  static Path _pathForRadii(List<double> radii, Offset center) {
    final path = Path();
    for (var sample = 0; sample < contourSampleCount; sample++) {
      final angle = -math.pi / 2 + sample * 2 * math.pi / contourSampleCount;
      final point =
          center + Offset(math.cos(angle), math.sin(angle)) * radii[sample];
      if (sample == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant RecordingMembranePainter oldDelegate) {
    return fillColor != oldDelegate.fillColor ||
        strokeColor != oldDelegate.strokeColor ||
        level != oldDelegate.level ||
        flux != oldDelegate.flux ||
        novelty != oldDelegate.novelty ||
        colorPhase != oldDelegate.colorPhase ||
        !_sameList(coefficients, oldDelegate.coefficients) ||
        !_sameList(velocity, oldDelegate.velocity) ||
        !_sameHistory(history, oldDelegate.history);
  }

  @override
  bool? hitTest(Offset position) => false;
}

final class _MembranePalette {
  const _MembranePalette({
    required this.stops,
    required this.rimColors,
    required this.glowColors,
    required this.innerColors,
  });

  final List<double> stops;
  final List<Color> rimColors;
  final List<Color> glowColors;
  final List<Color> innerColors;
}

Color _tone(
  Color color, {
  double hueShift = 0,
  double saturationFactor = 1,
  double lightnessFactor = 1,
  double lightnessDelta = 0,
}) {
  final hsl = HSLColor.fromColor(color);
  return hsl
      .withHue((hsl.hue + hueShift) % 360)
      .withSaturation((hsl.saturation * saturationFactor).clamp(0.0, 1.0))
      .withLightness(
        (hsl.lightness * lightnessFactor + lightnessDelta).clamp(0.0, 1.0),
      )
      .toColor();
}

bool _sameList(List<double> first, List<double> second) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}

bool _sameHistory(List<List<double>> first, List<List<double>> second) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (!_sameList(first[index], second[index])) return false;
  }
  return true;
}

double _unit(double value) {
  if (!value.isFinite) return 0;
  return value.clamp(0.0, 1.0).toDouble();
}
