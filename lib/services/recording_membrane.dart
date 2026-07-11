import 'dart:math' as math;

import 'package:open_vibrance/services/audio_spectrum_analyzer.dart';

/// Immutable audio-to-visual target consumed by the recording membrane.
final class RecordingMembraneTarget {
  RecordingMembraneTarget({
    required List<double> coefficients,
    required this.level,
    required this.flux,
    required this.contrast,
    required this.novelty,
    required this.highBandShare,
    required this.colorPhase,
    required this.requestedReach,
    required this.actualReach,
  }) : coefficients = List<double>.unmodifiable(
         RecordingMembraneModel.validatedCoefficients(coefficients),
       );

  final List<double> coefficients;
  final double level;
  final double flux;
  final double contrast;
  final double novelty;
  final double highBandShare;
  final double colorPhase;
  final double requestedReach;
  final double actualReach;

  double get activity =>
      _unit(0.30 * level + 0.45 * novelty / 0.12 + 0.25 * flux);
}

/// Stateful, deterministic audio-frame mapper.
///
/// A slow spectral envelope is removed before the DFT projection. This keeps a
/// person's persistent voice tilt from pinning the membrane to one silhouette,
/// while a small absolute component preserves broad folds during held vowels.
final class RecordingMembraneMapper {
  RecordingMembraneMapper();

  static const double defaultFrameSeconds =
      2 * AudioSpectrumAnalyzer.hopSize / 16000;
  static const double _slowEnvelopeSeconds = 0.52;
  static const double _colorReleaseSeconds = 0.20;
  static const double _absoluteMix = 0.30;
  static const double _noveltyMix = 0.70;
  static const double _noveltyBoost = 2.50;
  static const double _targetSafetyInset = 0.3;
  static const List<double> _modeWeights = [0, 0.06, 0.72, 0.90, 0.92, 0.62];

  final List<double> _slowBands = List<double>.filled(
    AudioSpectrumFrame.bandCount,
    0,
  );
  bool _hasHistory = false;
  double _colorPhase = -math.pi / 2;

  double get colorPhase => _colorPhase;

  void reset() {
    _slowBands.fillRange(0, _slowBands.length, 0);
    _hasHistory = false;
    _colorPhase = -math.pi / 2;
  }

  RecordingMembraneTarget map({
    required double level,
    required List<double> bands,
    required double flux,
    double spectrumMix = 1,
    double elapsedSeconds = defaultFrameSeconds,
  }) {
    if (bands.length != AudioSpectrumFrame.bandCount) {
      throw ArgumentError.value(
        bands.length,
        'bands.length',
        'A membrane target requires ${AudioSpectrumFrame.bandCount} bands',
      );
    }

    final safeLevel = _unit(level);
    final safeFlux = _unit(flux);
    final safeSpectrumMix = _unit(spectrumMix);
    final dt =
        elapsedSeconds.isFinite && elapsedSeconds > 0
            ? elapsedSeconds.clamp(1 / 240, 0.25).toDouble()
            : defaultFrameSeconds;
    final baseRadius = RecordingMembraneModel.baseRadiusFor(safeLevel);
    final coefficients = List<double>.filled(
      RecordingMembraneModel.coefficientCount,
      0,
    )..[0] = baseRadius;

    if (safeSpectrumMix == 0 || safeLevel == 0) {
      return RecordingMembraneTarget(
        coefficients: coefficients,
        level: safeLevel,
        flux: safeFlux,
        contrast: 0,
        novelty: 0,
        highBandShare: 0,
        colorPhase: _colorPhase,
        requestedReach: 0,
        actualReach: 0,
      );
    }

    final energies = List<double>.generate(
      AudioSpectrumFrame.bandCount,
      (band) => math.pow(_unit(bands[band]), 0.90).toDouble(),
      growable: false,
    );
    if (!_hasHistory) {
      for (var band = 0; band < energies.length; band++) {
        _slowBands[band] = energies[band] * 0.72;
      }
      _hasHistory = true;
    }

    final energyMean = _mean(energies);
    final residuals = List<double>.generate(
      energies.length,
      (band) => energies[band] - _slowBands[band],
      growable: false,
    );
    final residualMean = _mean(residuals);
    final absolute = List<double>.generate(
      energies.length,
      (band) => energies[band] - energyMean,
      growable: false,
    );
    final noveltySignal = List<double>.generate(
      energies.length,
      (band) => residuals[band] - residualMean,
      growable: false,
    );
    final contrast = _rms(absolute);
    final novelty = _rms(noveltySignal);

    final slowAlpha = 1 - math.exp(-dt / _slowEnvelopeSeconds);
    for (var band = 0; band < energies.length; band++) {
      _slowBands[band] += (energies[band] - _slowBands[band]) * slowAlpha;
    }

    final shaped = List<double>.generate(
      energies.length,
      (band) =>
          _absoluteMix * absolute[band] +
          _noveltyMix * _noveltyBoost * noveltySignal[band],
      growable: false,
    );
    final meaningfulVariation = math.max(contrast * 0.24, novelty);
    final gateInput = _unit((meaningfulVariation - 0.006) / 0.045);
    final noiseGate = gateInput * gateInput * (3 - 2 * gateInput);

    var totalEnergy = 0.0;
    var highEnergy = 0.0;
    var centroidNumerator = 0.0;
    for (var band = 0; band < energies.length; band++) {
      final energy = energies[band];
      totalEnergy += energy;
      if (band >= energies.length ~/ 2) highEnergy += energy;
      centroidNumerator += energy * band / (energies.length - 1);
    }
    final highBandShare = totalEnergy > 1e-9 ? highEnergy / totalEnergy : 0.0;
    final centroid = totalEnergy > 1e-9 ? centroidNumerator / totalEnergy : 0.5;
    final targetColorPhase = -math.pi / 2 + 2 * math.pi * centroid;
    final phaseDelta = _wrappedAngle(targetColorPhase - _colorPhase);
    final colorTau = _colorReleaseSeconds * (1 - 0.42 * safeFlux);
    final colorAlpha = 1 - math.exp(-dt / colorTau);
    _colorPhase += phaseDelta * colorAlpha;

    final transient = _unit(0.62 * safeFlux + 0.38 * highBandShare);
    for (var mode = 1; mode <= RecordingMembraneModel.modeCount; mode++) {
      var cosine = 0.0;
      var sine = 0.0;
      for (var band = 0; band < shaped.length; band++) {
        cosine += shaped[band] * RecordingMembraneModel.bandCosine(band, mode);
        sine += shaped[band] * RecordingMembraneModel.bandSine(band, mode);
      }
      final highModeBoost = switch (mode) {
        4 => 1 + 0.35 * transient,
        5 => 1 + 0.55 * transient,
        _ => 1.0,
      };
      final scale =
          2 /
          shaped.length *
          _modeWeights[mode] *
          highModeBoost *
          noiseGate *
          safeSpectrumMix;
      coefficients[RecordingMembraneModel.cosineIndex(mode)] = scale * cosine;
      coefficients[RecordingMembraneModel.sineIndex(mode)] = scale * sine;
    }

    final rawBound = RecordingMembraneModel.acBound(coefficients);
    final gain =
        42.0 * math.pow(safeLevel, 0.56).toDouble() * (0.82 + 0.30 * safeFlux);
    final requestedReach = rawBound * gain;
    final availableReach = math.max(
      0,
      math.min(
            RecordingMembraneModel.maxCenterRadius - baseRadius,
            baseRadius - RecordingMembraneModel.minCenterRadius,
          ) -
          _targetSafetyInset,
    );
    final actualReach =
        availableReach <= 0
            ? 0.0
            : availableReach * _tanh(requestedReach / availableReach);
    final coefficientScale = rawBound > 1e-9 ? actualReach / rawBound : 0.0;
    for (var index = 1; index < coefficients.length; index++) {
      coefficients[index] *= coefficientScale;
    }

    return RecordingMembraneTarget(
      coefficients: coefficients,
      level: safeLevel,
      flux: safeFlux,
      contrast: contrast,
      novelty: novelty,
      highBandShare: highBandShare,
      colorPhase: _colorPhase,
      requestedReach: requestedReach,
      actualReach: actualReach,
    );
  }
}

/// Pure velocity-preserving spring state for the membrane coefficients.
final class RecordingMembraneDynamics {
  RecordingMembraneDynamics(List<double> initial)
    : _position = RecordingMembraneModel.validatedCoefficients(initial),
      _target = RecordingMembraneModel.validatedCoefficients(initial),
      _velocity = List<double>.filled(
        RecordingMembraneModel.coefficientCount,
        0,
      );

  static const double _baseOmega = 22;
  static const double _shapeOmega = 22;
  static const double _baseDampingRatio = 1;
  static const double _shapeDampingRatio = 1.00;
  static const double _fineShapeDampingRatio = 1.00;
  static const double _positionEpsilon = 0.002;
  static const double _velocityEpsilon = 0.02;
  static const double maxIntegratedSeconds = 0.25;

  final List<double> _position;
  final List<double> _velocity;
  List<double> _target;

  List<double> get snapshot => List<double>.unmodifiable(_position);
  List<double> get velocity => List<double>.unmodifiable(_velocity);
  List<double> get target => List<double>.unmodifiable(_target);

  bool get isAtRest {
    for (var index = 0; index < _position.length; index++) {
      if ((_position[index] - _target[index]).abs() >= _positionEpsilon ||
          _velocity[index].abs() >= _velocityEpsilon) {
        return false;
      }
    }
    return true;
  }

  bool retarget(List<double> next) {
    final validated = RecordingMembraneModel.validatedCoefficients(next);
    var changed = false;
    for (var index = 0; index < validated.length; index++) {
      if ((validated[index] - _target[index]).abs() > 1e-9) {
        changed = true;
        break;
      }
    }
    if (changed) _target = validated;
    return changed;
  }

  bool advance(double elapsedSeconds) {
    if (!elapsedSeconds.isFinite || elapsedSeconds <= 0) return !isAtRest;
    if (elapsedSeconds > maxIntegratedSeconds) {
      _snapToTarget();
      return false;
    }

    for (var index = 0; index < _position.length; index++) {
      final mode = index == 0 ? 0 : (index + 1) ~/ 2;
      final omega = mode == 0 ? _baseOmega : _shapeOmega;
      final dampingRatio = switch (mode) {
        0 => _baseDampingRatio,
        >= 4 => _fineShapeDampingRatio,
        _ => _shapeDampingRatio,
      };
      final next = _advanceDampedSpring(
        position: _position[index],
        velocity: _velocity[index],
        target: _target[index],
        omega: omega,
        dampingRatio: dampingRatio,
        dt: elapsedSeconds,
      );
      _position[index] = next.$1;
      _velocity[index] = next.$2;
    }

    if (!isAtRest) return true;
    _snapToTarget();
    return false;
  }

  void _snapToTarget() {
    for (var index = 0; index < _position.length; index++) {
      _position[index] = _target[index];
      _velocity[index] = 0;
    }
  }

  static (double, double) _advanceDampedSpring({
    required double position,
    required double velocity,
    required double target,
    required double omega,
    required double dampingRatio,
    required double dt,
  }) {
    final displacement = position - target;
    final criticalDelta = 1 - dampingRatio * dampingRatio;
    if (criticalDelta <= 1e-6) {
      final decay = math.exp(-omega * dt);
      final q = velocity + omega * displacement;
      final nextDisplacement = (displacement + q * dt) * decay;
      final nextVelocity = (velocity - omega * q * dt) * decay;
      return (target + nextDisplacement, nextVelocity);
    }

    final alpha = dampingRatio * omega;
    final beta = omega * math.sqrt(criticalDelta);
    final decay = math.exp(-alpha * dt);
    final cosine = math.cos(beta * dt);
    final sine = math.sin(beta * dt);
    final nextDisplacement =
        decay *
        (displacement * cosine +
            ((velocity + alpha * displacement) / beta) * sine);
    final nextVelocity =
        decay *
        (velocity * cosine -
            ((alpha * velocity + omega * omega * displacement) / beta) * sine);
    return (target + nextDisplacement, nextVelocity);
  }
}

/// Pure Fourier geometry shared by Flutter and the offline membrane lab.
final class RecordingMembraneModel {
  RecordingMembraneModel._();

  static const int modeCount = 5;
  static const int coefficientCount = 1 + 2 * modeCount;
  static const int contourSampleCount = 96;
  static const double minCenterRadius = 3.2;
  static const double maxCenterRadius = 12.8;
  static const double _legacyMaxSignedReach = 4.8;
  static const double _targetSafetyInset = 0.3;
  static const List<double> _legacyModeWeights = [0, 0.30, 1, 0.90, 0.65, 0.40];
  static final _MembraneKernel _kernel = _MembraneKernel.build();

  static double baseRadiusFor(double level) =>
      6 + 2 * math.pow(_unit(level), 1.15).toDouble();

  /// The previous stateless mapper is retained as the lab's exact baseline and
  /// as a convenient deterministic geometry fixture for unit tests.
  static List<double> coefficientsFor({
    required double level,
    required List<double> bands,
    required double flux,
    required double spectrumMix,
  }) {
    if (bands.length != AudioSpectrumFrame.bandCount) {
      throw ArgumentError.value(
        bands.length,
        'bands.length',
        'A membrane target requires ${AudioSpectrumFrame.bandCount} bands',
      );
    }

    final safeLevel = _unit(level);
    final safeFlux = _unit(flux);
    final safeSpectrumMix = _unit(spectrumMix);
    final baseRadius = baseRadiusFor(safeLevel);
    final coefficients = List<double>.filled(coefficientCount, 0)
      ..[0] = baseRadius;
    if (safeSpectrumMix == 0 || safeLevel == 0) {
      return List<double>.unmodifiable(coefficients);
    }

    final energies = List<double>.generate(
      AudioSpectrumFrame.bandCount,
      (band) => math.pow(_unit(bands[band]), 0.90).toDouble(),
      growable: false,
    );
    final mean = _mean(energies);
    final deviations = List<double>.generate(
      energies.length,
      (index) => energies[index] - mean,
      growable: false,
    );
    final contrast = _rms(deviations);
    final contrastInput = _unit((contrast - 0.02) / 0.10);
    final contrastGate =
        contrastInput * contrastInput * (3 - 2 * contrastInput);
    if (contrastGate == 0) return List<double>.unmodifiable(coefficients);

    for (var mode = 1; mode <= modeCount; mode++) {
      var cosine = 0.0;
      var sine = 0.0;
      for (var band = 0; band < energies.length; band++) {
        cosine += deviations[band] * _kernel.bandCosines[band][mode];
        sine += deviations[band] * _kernel.bandSines[band][mode];
      }
      final normalization = 2 / energies.length;
      final weight = _legacyModeWeights[mode];
      coefficients[cosineIndex(mode)] = normalization * weight * cosine;
      coefficients[sineIndex(mode)] = normalization * weight * sine;
    }

    final bound = acBound(coefficients);
    if (bound <= 1e-9) return List<double>.unmodifiable(coefficients);
    final activityReach =
        _legacyMaxSignedReach *
        math.pow(safeLevel, 0.55).toDouble() *
        contrastGate *
        (0.90 + 0.10 * safeFlux) *
        safeSpectrumMix;
    final availableReach = math.max(
      0,
      math.min(maxCenterRadius - baseRadius, baseRadius - minCenterRadius) -
          _targetSafetyInset,
    );
    final desiredBound = math.min(activityReach, availableReach);
    final scale = desiredBound / bound;
    for (var index = 1; index < coefficients.length; index++) {
      coefficients[index] *= scale;
    }
    return List<double>.unmodifiable(coefficients);
  }

  static List<double> contourRadii({
    required double level,
    required List<double> bands,
    required double flux,
    required double spectrumMix,
  }) => radiiFromCoefficients(
    coefficientsFor(
      level: level,
      bands: bands,
      flux: flux,
      spectrumMix: spectrumMix,
    ),
  );

  static List<double> radiiFromCoefficients(List<double> coefficients) {
    final validated = validatedCoefficients(coefficients);
    final baseRadius = validated[0].clamp(minCenterRadius, maxCenterRadius);
    final bound = acBound(validated);
    final availableReach = math.min(
      maxCenterRadius - baseRadius,
      baseRadius - minCenterRadius,
    );
    final safeScale =
        bound > availableReach && bound > 0 ? availableReach / bound : 1.0;

    return List<double>.generate(contourSampleCount, (sample) {
      var displacement = 0.0;
      for (var index = 1; index < coefficientCount; index++) {
        displacement += validated[index] * _kernel.basis[sample][index];
      }
      return baseRadius + safeScale * displacement;
    }, growable: false);
  }

  static List<double> periodicValues(List<double> coefficients) {
    final validated = validatedCoefficients(coefficients);
    return List<double>.generate(contourSampleCount, (sample) {
      var value = validated[0];
      for (var index = 1; index < coefficientCount; index++) {
        value += validated[index] * _kernel.basis[sample][index];
      }
      return value;
    }, growable: false);
  }

  static double acBound(List<double> coefficients) {
    var bound = 0.0;
    for (var mode = 1; mode <= modeCount; mode++) {
      bound += math.sqrt(
        math.pow(coefficients[cosineIndex(mode)], 2) +
            math.pow(coefficients[sineIndex(mode)], 2),
      );
    }
    return bound;
  }

  static double bandCosine(int band, int mode) =>
      _kernel.bandCosines[band][mode];
  static double bandSine(int band, int mode) => _kernel.bandSines[band][mode];
  static int cosineIndex(int mode) => 2 * mode - 1;
  static int sineIndex(int mode) => 2 * mode;

  static List<double> validatedCoefficients(List<double> coefficients) {
    if (coefficients.length != coefficientCount) {
      throw ArgumentError.value(
        coefficients.length,
        'coefficients.length',
        'A membrane requires $coefficientCount coefficients',
      );
    }
    return List<double>.generate(
      coefficients.length,
      (index) => coefficients[index].isFinite ? coefficients[index] : 0,
      growable: false,
    );
  }
}

final class _MembraneKernel {
  _MembraneKernel({
    required this.basis,
    required this.bandCosines,
    required this.bandSines,
  });

  final List<List<double>> basis;
  final List<List<double>> bandCosines;
  final List<List<double>> bandSines;

  static _MembraneKernel build() {
    final basis = <List<double>>[];
    final angleStep = 2 * math.pi / RecordingMembraneModel.contourSampleCount;
    for (
      var sample = 0;
      sample < RecordingMembraneModel.contourSampleCount;
      sample++
    ) {
      final angle = -math.pi / 2 + sample * angleStep;
      final sampleBasis = List<double>.filled(
        RecordingMembraneModel.coefficientCount,
        0,
      )..[0] = 1;
      for (var mode = 1; mode <= RecordingMembraneModel.modeCount; mode++) {
        sampleBasis[RecordingMembraneModel.cosineIndex(mode)] = math.cos(
          mode * angle,
        );
        sampleBasis[RecordingMembraneModel.sineIndex(mode)] = math.sin(
          mode * angle,
        );
      }
      basis.add(List<double>.unmodifiable(sampleBasis));
    }

    final bandCosines = <List<double>>[];
    final bandSines = <List<double>>[];
    for (var band = 0; band < AudioSpectrumFrame.bandCount; band++) {
      final angle =
          -math.pi / 2 + band * 2 * math.pi / AudioSpectrumFrame.bandCount;
      final cosines = List<double>.filled(
        RecordingMembraneModel.modeCount + 1,
        0,
      );
      final sines = List<double>.filled(
        RecordingMembraneModel.modeCount + 1,
        0,
      );
      for (var mode = 1; mode <= RecordingMembraneModel.modeCount; mode++) {
        cosines[mode] = math.cos(mode * angle);
        sines[mode] = math.sin(mode * angle);
      }
      bandCosines.add(List<double>.unmodifiable(cosines));
      bandSines.add(List<double>.unmodifiable(sines));
    }

    return _MembraneKernel(
      basis: List<List<double>>.unmodifiable(basis),
      bandCosines: List<List<double>>.unmodifiable(bandCosines),
      bandSines: List<List<double>>.unmodifiable(bandSines),
    );
  }
}

double _mean(List<double> values) =>
    values.fold<double>(0, (sum, value) => sum + value) / values.length;

double _rms(List<double> values) {
  var sum = 0.0;
  for (final value in values) {
    sum += value * value;
  }
  return math.sqrt(sum / values.length);
}

double _wrappedAngle(double angle) {
  var result = angle;
  while (result > math.pi) {
    result -= 2 * math.pi;
  }
  while (result < -math.pi) {
    result += 2 * math.pi;
  }
  return result;
}

double _tanh(double value) {
  if (value >= 20) return 1;
  final exponential = math.exp(2 * value);
  return (exponential - 1) / (exponential + 1);
}

double _unit(double value) {
  if (!value.isFinite) return 0;
  return value.clamp(0.0, 1.0).toDouble();
}
