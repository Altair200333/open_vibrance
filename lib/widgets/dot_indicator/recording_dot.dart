import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:open_vibrance/services/audio_spectrum_analyzer.dart';
import 'package:open_vibrance/services/recording_membrane.dart';
import 'package:open_vibrance/services/recording_membrane_impact.dart';

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
  late final RecordingMembraneImpactController _impactController;
  late final Ticker _ticker;
  late RecordingMembraneTarget _visualTarget;
  final List<List<double>> _history = [];
  Duration? _lastTickTime;
  int? _lastSpectrumSequence;
  bool _hadSpectrum = false;
  bool _impactSpawned = false;
  double _historyElapsed = 0;

  @override
  void initState() {
    super.initState();
    _mapper = RecordingMembraneMapper();
    _impactController = RecordingMembraneImpactController();
    _visualTarget = _resolveTarget();
    _dynamics = RecordingMembraneDynamics(_visualTarget.coefficients);
    _history.add(_dynamics.snapshot);
    _ticker = createTicker(_onTick);
    if (_impactController.hasActiveImpacts) _ensureTickerRunning();
  }

  @override
  void didUpdateWidget(covariant RecordingDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _visualTarget = _resolveTarget();
    final geometryRetargeted = _dynamics.retarget(_visualTarget.coefficients);
    if (geometryRetargeted ||
        _impactSpawned ||
        _impactController.hasActiveImpacts) {
      _ensureTickerRunning();
    }
  }

  RecordingMembraneTarget _resolveTarget() {
    _impactSpawned = false;
    final spectrum = widget.spectrumFrame;
    if (!spectrum.hasSpectrum) {
      if (_hadSpectrum) _impactController.reset();
      _hadSpectrum = false;
      _lastSpectrumSequence = null;
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
      _impactController.reset();
      _history.clear();
      _historyElapsed = 0;
    }
    final sequenceDelta =
        _hadSpectrum &&
                previousSequence != null &&
                spectrum.sequence > previousSequence
            ? spectrum.sequence - previousSequence
            : 1;
    final elapsedSeconds =
        sequenceDelta * RecordingMembraneMapper.defaultFrameSeconds;
    if (_hadSpectrum && elapsedSeconds > 0.25) {
      _impactController.reset();
    }
    _hadSpectrum = true;
    _lastSpectrumSequence = spectrum.sequence;
    final target = _mapper.map(
      level: spectrum.level,
      bands: spectrum.bands,
      flux: spectrum.flux,
      elapsedSeconds: elapsedSeconds,
    );
    _impactSpawned = _impactController.processTarget(target) != null;
    return target;
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
      _impactController.clear();
    }
    final geometryMoving = _dynamics.advance(dt);
    final impactMoving = _impactController.advance(dt);
    _captureHistory(dt);
    if (!mounted) return;
    setState(() {});
    if (!geometryMoving && !impactMoving) {
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
              impacts: _impactController.impacts,
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
    List<RecordingMembraneImpactSnapshot> impacts = const [],
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
       ),
       impacts = List<RecordingMembraneImpactSnapshot>.unmodifiable(impacts);

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
  final List<RecordingMembraneImpactSnapshot> impacts;
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

      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.fill
          ..color = _tone(
            fillColor,
            saturationFactor: 0.96,
            lightnessFactor: 0.42,
          ).withValues(alpha: 0.99)
          ..isAntiAlias = true,
      );

      if (activity > 0.01 || impacts.isNotEmpty) {
        canvas.save();
        canvas.clipPath(path);
        _paintImpacts(canvas: canvas, center: center, baseRadius: baseRadius);

        if (activity > 0.01) {
          final innerBandPaint =
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.35
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
            activity: impacts.isEmpty ? activity : activity * 0.40,
            currentBaseRadius: baseRadius,
          );
        }
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
      _paintImpactRim(
        canvas: canvas,
        center: center,
        radii: radii,
        baseRadius: baseRadius,
      );
    } finally {
      canvas.restore();
    }
  }

  void _paintImpacts({
    required Canvas canvas,
    required Offset center,
    required double baseRadius,
  }) {
    final visible = _renderedImpacts(center, baseRadius);
    if (visible.isEmpty) return;
    final secondary = visible.reduce(
      (first, second) => first.envelope >= second.envelope ? first : second,
    );

    for (final impact in visible) {
      _paintImpactDimple(canvas, impact);

      final troughRadius = impact.frontRadius - 1.20;
      if (troughRadius > 0.35 && impact.envelope > 0.001) {
        _paintImpactOval(
          canvas: canvas,
          impact: impact,
          radius: troughRadius,
          color: _tone(
            fillColor,
            hueShift: -8,
            saturationFactor: 0.78,
            lightnessFactor: 0.28,
          ),
          alpha: 0.18 * impact.envelope,
          strokeWidth: 1.42,
          blendMode: BlendMode.multiply,
          angularFloor: 0.06,
        );
      }

      if (identical(impact, secondary) &&
          impact.frontRadius > 2.95 &&
          impact.envelope > 0.001) {
        _paintImpactOval(
          canvas: canvas,
          impact: impact,
          radius: impact.frontRadius - 2.45,
          color: _crestColor,
          alpha: 0.06 * impact.envelope,
          strokeWidth: 0.50,
          blendMode: BlendMode.screen,
          angularFloor: 0.00,
          chromatic: true,
        );
      }

      if (impact.envelope <= 0.001) continue;
      _paintImpactOval(
        canvas: canvas,
        impact: impact,
        radius: impact.frontRadius,
        color: _crestColor,
        alpha: 0.18 * impact.envelope,
        strokeWidth: 1.74,
        blendMode: BlendMode.screen,
        blurSigma: 0.32,
        angularFloor: 0.04,
        chromatic: true,
      );
      _paintImpactOval(
        canvas: canvas,
        impact: impact,
        radius: impact.frontRadius,
        color: _crestColor,
        alpha: 0.64 * impact.envelope,
        strokeWidth: 0.84,
        blendMode: BlendMode.screen,
        angularFloor: 0.06,
        chromatic: true,
      );
    }
  }

  void _paintImpactDimple(Canvas canvas, _RenderedImpact impact) {
    final life = math.exp(-impact.snapshot.age / 0.12);
    if (life < 0.015) return;
    final radius = 0.92 + 0.56 * impact.snapshot.strength;
    final bounds = Rect.fromCenter(
      center: Offset.zero,
      width: radius * 2.70,
      height: radius * 1.52,
    );
    canvas.save();
    canvas.translate(impact.origin.dx, impact.origin.dy);
    canvas.rotate(impact.snapshot.angle);
    canvas.drawOval(
      bounds,
      Paint()
        ..style = PaintingStyle.fill
        ..color = _tone(
          fillColor,
          saturationFactor: 0.72,
          lightnessFactor: 0.24,
        ).withValues(alpha: 0.06 * impact.snapshot.strength * life)
        ..blendMode = BlendMode.multiply
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.32)
        ..isAntiAlias = true,
    );
    canvas.drawArc(
      bounds,
      -math.pi * 0.42,
      math.pi * 0.84,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.48
        ..strokeCap = StrokeCap.round
        ..color = _crestColor.withValues(
          alpha: 0.16 * impact.snapshot.strength * life,
        )
        ..blendMode = BlendMode.screen
        ..isAntiAlias = true,
    );
    canvas.restore();
  }

  void _paintImpactOval({
    required Canvas canvas,
    required _RenderedImpact impact,
    required double radius,
    required Color color,
    required double alpha,
    required double strokeWidth,
    required BlendMode blendMode,
    required double angularFloor,
    bool chromatic = false,
    double blurSigma = 0,
  }) {
    if (radius <= 0 || alpha <= 0.001) return;
    final major = radius * (1 + impact.eccentricity);
    final minor = radius * (1 - 0.55 * impact.eccentricity);
    final bounds = Rect.fromCenter(
      center: Offset.zero,
      width: 2 * major,
      height: 2 * minor,
    );
    final angular = _impactAngularColors(
      impact: impact,
      color: color,
      alpha: alpha,
      floor: angularFloor,
      chromatic: chromatic,
    );
    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..blendMode = blendMode
          ..shader = SweepGradient(
            colors: angular.colors,
            stops: angular.stops,
          ).createShader(bounds)
          ..isAntiAlias = true;
    if (blurSigma > 0) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma);
    }
    canvas.save();
    canvas.translate(impact.origin.dx, impact.origin.dy);
    canvas.rotate(impact.snapshot.angle);
    canvas.drawPath(_impactWavePath(impact, radius), paint);
    canvas.restore();
  }

  Path _impactWavePath(_RenderedImpact impact, double radius) {
    const samples = 48;
    final phase = impact.snapshot.colorPhase - impact.snapshot.angle;
    final warpAmount = 0.045 + 0.045 * impact.snapshot.highBandShare;
    final major = radius * (1 + impact.eccentricity);
    final minor = radius * (1 - 0.55 * impact.eccentricity);
    final path = Path();
    for (var sample = 0; sample < samples; sample++) {
      final angle = sample * 2 * math.pi / samples;
      final warp =
          1 +
          warpAmount *
              (0.68 * math.sin(2 * angle + phase) +
                  0.32 * math.sin(3 * angle - 0.55 * phase));
      final point = Offset(
        math.cos(angle) * major * warp,
        math.sin(angle) * minor * warp,
      );
      if (sample == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    return path;
  }

  _AngularPalette _impactAngularColors({
    required _RenderedImpact impact,
    required Color color,
    required double alpha,
    required double floor,
    required bool chromatic,
  }) {
    const stopCount = 16;
    final phase =
        impact.snapshot.colorPhase -
        impact.snapshot.angle +
        impact.snapshot.highBandShare * math.pi * 0.45;
    final colors = <Color>[];
    final stops = <double>[];
    for (var stop = 0; stop <= stopCount; stop++) {
      final angle = stop * 2 * math.pi / stopCount;
      final broadWave =
          0.45 + 0.42 * math.cos(angle) + 0.13 * math.cos(2 * angle + phase);
      final modulation = (floor + (1 - floor) * broadWave).clamp(floor, 1.0);
      final chroma =
          chromatic
              ? Color.lerp(
                Color.lerp(
                  _tone(
                    fillColor,
                    hueShift: -28,
                    saturationFactor: 1.08,
                    lightnessDelta: 0.20,
                  ),
                  strokeColor,
                  0.40,
                ),
                color,
                0.5 + 0.5 * math.cos(angle + phase),
              )!
              : color;
      colors.add(chroma.withValues(alpha: _unit(alpha * modulation)));
      stops.add(stop / stopCount);
    }
    return _AngularPalette(
      colors: List<Color>.unmodifiable(colors),
      stops: List<double>.unmodifiable(stops),
    );
  }

  void _paintImpactRim({
    required Canvas canvas,
    required Offset center,
    required List<double> radii,
    required double baseRadius,
  }) {
    final visible = _renderedImpacts(center, baseRadius);
    if (visible.isEmpty) return;
    final points = List<Offset>.generate(contourSampleCount, (sample) {
      final angle = -math.pi / 2 + sample * 2 * math.pi / contourSampleCount;
      return center + Offset(math.cos(angle), math.sin(angle)) * radii[sample];
    }, growable: false);
    final hits = List<double>.generate(contourSampleCount, (sample) {
      final point = points[sample];
      var maximum = 0.0;
      for (final impact in visible) {
        if (impact.envelope <= 0.001) continue;
        final delta = point - impact.origin;
        final cosine = math.cos(impact.snapshot.angle);
        final sine = math.sin(impact.snapshot.angle);
        final u = delta.dx * cosine + delta.dy * sine;
        final v = -delta.dx * sine + delta.dy * cosine;
        final ellipticalRadius = math.sqrt(
          math.pow(u / (1 + impact.eccentricity), 2) +
              math.pow(v / (1 - 0.55 * impact.eccentricity), 2),
        );
        final distance = (ellipticalRadius - impact.frontRadius) / 0.68;
        maximum = math.max(
          maximum,
          impact.envelope * math.exp(-0.5 * distance * distance),
        );
      }
      return maximum;
    }, growable: false);

    const stopCount = 24;
    final rimColor = Color.lerp(_crestColor, strokeColor, 0.62)!;
    final stops = <double>[];
    final glowColors = <Color>[];
    final coreColors = <Color>[];
    for (var stop = 0; stop <= stopCount; stop++) {
      final sample = stop % stopCount * contourSampleCount ~/ stopCount;
      final normalized = _unit(hits[sample] / 0.48);
      final intensity = normalized * normalized * (3 - 2 * normalized);
      stops.add(stop / stopCount);
      glowColors.add(rimColor.withValues(alpha: 0.13 * intensity));
      coreColors.add(rimColor.withValues(alpha: 0.27 * intensity));
    }
    final path = _pathForRadii(radii, center);
    final bounds = Rect.fromCircle(center: center, radius: maxCenterRadius);
    final rotation = GradientRotation(-math.pi / 2);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.82
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..shader = SweepGradient(
          colors: glowColors,
          stops: stops,
          transform: rotation,
        ).createShader(bounds)
        ..blendMode = BlendMode.screen
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.30)
        ..isAntiAlias = true,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.82
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..shader = SweepGradient(
          colors: coreColors,
          stops: stops,
          transform: rotation,
        ).createShader(bounds)
        ..blendMode = BlendMode.screen
        ..isAntiAlias = true,
    );
  }

  List<_RenderedImpact> _renderedImpacts(Offset center, double baseRadius) {
    final alive = impacts.where((impact) => impact.isAlive).toList();
    if (alive.length > 2) alive.removeRange(0, alive.length - 2);
    alive.sort((first, second) => second.age.compareTo(first.age));
    return List<_RenderedImpact>.unmodifiable(
      alive.map((snapshot) {
        return _RenderedImpact(
          snapshot: snapshot,
          origin:
              center +
              Offset(snapshot.origin.x, snapshot.origin.y) * baseRadius,
          frontRadius: snapshot.frontRadiusFor(baseRadius),
          eccentricity: (0.06 + 0.30 * snapshot.eccentricity).clamp(0.08, 0.23),
          envelope: math.min(
            1,
            snapshot.fade * math.pow(math.max(snapshot.strength, 1e-6), -0.24),
          ),
        );
      }),
    );
  }

  Color get _crestColor =>
      Color.lerp(
        _tone(
          fillColor,
          hueShift: 24,
          saturationFactor: 1.05,
          lightnessDelta: 0.24,
        ),
        strokeColor,
        0.50,
      )!;

  void _paintHistory({
    required Canvas canvas,
    required Offset center,
    required Rect shaderBounds,
    required _MembranePalette palette,
    required double activity,
    required double currentBaseRadius,
  }) {
    const historyIndices = [3];
    const insets = [1.60];
    const scales = [0.52];
    const widths = [0.38];
    const alphas = [0.055];

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
        !_sameHistory(history, oldDelegate.history) ||
        !_sameImpacts(impacts, oldDelegate.impacts);
  }

  @override
  bool? hitTest(Offset position) => false;
}

final class _RenderedImpact {
  const _RenderedImpact({
    required this.snapshot,
    required this.origin,
    required this.frontRadius,
    required this.eccentricity,
    required this.envelope,
  });

  final RecordingMembraneImpactSnapshot snapshot;
  final Offset origin;
  final double frontRadius;
  final double eccentricity;
  final double envelope;
}

final class _AngularPalette {
  const _AngularPalette({required this.colors, required this.stops});

  final List<Color> colors;
  final List<double> stops;
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

bool _sameImpacts(
  List<RecordingMembraneImpactSnapshot> first,
  List<RecordingMembraneImpactSnapshot> second,
) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    final a = first[index];
    final b = second[index];
    if (a.id != b.id ||
        a.age != b.age ||
        a.strength != b.strength ||
        a.angle != b.angle ||
        a.origin.x != b.origin.x ||
        a.origin.y != b.origin.y ||
        a.eccentricity != b.eccentricity ||
        a.colorPhase != b.colorPhase ||
        a.highBandShare != b.highBandShare ||
        a.lifetime != b.lifetime) {
      return false;
    }
  }
  return true;
}

double _unit(double value) {
  if (!value.isFinite) return 0;
  return value.clamp(0.0, 1.0).toDouble();
}
