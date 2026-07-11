import 'dart:math' as math;

import 'package:open_vibrance/services/recording_membrane.dart';

/// A normalized, immutable point inside the recording membrane.
///
/// Coordinates are expressed as fractions of the membrane's base radius, so
/// the painter can apply them to a contour of any current size.
final class RecordingMembraneImpactOrigin {
  const RecordingMembraneImpactOrigin({required this.x, required this.y});

  final double x;
  final double y;

  double get radius => math.sqrt(x * x + y * y);
}

/// Immutable render state for one audio-caused disturbance.
///
/// [age] and [lifetime] are in seconds. [frontRadius] is normalized to the
/// membrane's base radius and [fade] already includes [strength].
final class RecordingMembraneImpactSnapshot {
  const RecordingMembraneImpactSnapshot({
    required this.id,
    required this.age,
    required this.strength,
    required this.angle,
    required this.origin,
    required this.eccentricity,
    required this.colorPhase,
    required this.highBandShare,
    required this.lifetime,
  });

  final int id;
  final double age;
  final double strength;
  final double angle;
  final RecordingMembraneImpactOrigin origin;
  final double eccentricity;
  final double colorPhase;
  final double highBandShare;
  final double lifetime;

  double get progress =>
      lifetime > 0 ? (age / lifetime).clamp(0.0, 1.0).toDouble() : 1;

  bool get isAlive => age < lifetime;

  /// Expanding wave-front radius as a fraction of the membrane base radius.
  double get frontRadius => 0.055 + 1.72 * progress;

  /// Pixel-space wave-front used by the production painter.
  double frontRadiusFor(double baseRadius) =>
      0.55 + 1.72 * math.max(0, baseRadius) * progress;

  /// Smooth visual envelope in the range `0..strength`.
  double get fade {
    final p = progress;
    if (p <= 0 || p >= 1) return 0;
    final attack = _smoothstep(_unit(p / 0.07));
    final release = _smoothstep(_unit((1 - p) / 0.24));
    return strength * attack * release * math.exp(-0.45 * p);
  }

  RecordingMembraneImpactSnapshot _advanced(double seconds) =>
      RecordingMembraneImpactSnapshot(
        id: id,
        age: age + seconds,
        strength: strength,
        angle: angle,
        origin: origin,
        eccentricity: eccentricity,
        colorPhase: colorPhase,
        highBandShare: highBandShare,
        lifetime: lifetime,
      );
}

/// Deterministic audio-event detector and finite ripple state.
///
/// Energy enters the system only through [processTarget]. [advance] merely
/// ages existing disturbances, which always expire after [impactLifetime].
/// There is no clock-driven oscillator, random source, or idle forcing.
final class RecordingMembraneImpactController {
  RecordingMembraneImpactController();

  static const int maxImpacts = 2;
  static const double impactLifetime = 0.55;
  static const double refractorySeconds = 0.12;
  static const double triggerDrive = 0.30;
  static const double rearmDrive = 0.24;
  static const double _noveltyReference = 0.12;
  static const double _shapeKickReference = 0.45;
  static const double _maximumOriginRadius = 0.40;
  static const double _maximumEccentricity = 0.55;

  List<RecordingMembraneImpactSnapshot> _impacts = const [];
  List<double>? _previousCoefficients;
  var _nextId = 0;
  var _armed = true;
  var _secondsSinceImpact = double.infinity;
  var _lastDrive = 0.0;
  var _lastShapeKick = 0.0;

  List<RecordingMembraneImpactSnapshot> get impacts =>
      List<RecordingMembraneImpactSnapshot>.unmodifiable(_impacts);

  bool get hasActiveImpacts => _impacts.isNotEmpty;
  bool get isArmed => _armed;
  double get lastDrive => _lastDrive;
  double get lastShapeKick => _lastShapeKick;

  /// Observes one new mapper target and returns a newly emitted impact, if any.
  ///
  /// Repeated calls with a held high drive do not retrigger: the Schmitt gate
  /// must first observe a target at or below [rearmDrive], and the refractory
  /// interval must have elapsed through [advance].
  RecordingMembraneImpactSnapshot? processTarget(
    RecordingMembraneTarget target,
  ) {
    final coefficients = RecordingMembraneModel.validatedCoefficients(
      target.coefficients,
    );
    final delta = _coefficientDelta(coefficients, _previousCoefficients);
    _previousCoefficients = List<double>.unmodifiable(coefficients);

    final shapeKick = _shapeKick(delta);
    final safeLevel = _unit(target.level);
    final safeFlux = _unit(target.flux);
    final safeNovelty = _unit(target.novelty / _noveltyReference);
    final levelInput = _unit((safeLevel - 0.04) / 0.22);
    final levelGate = levelInput * levelInput * (3 - 2 * levelInput);
    final drive = _unit(
      levelGate * (0.45 * safeFlux + 0.35 * safeNovelty + 0.20 * shapeKick),
    );
    _lastShapeKick = shapeKick;
    _lastDrive = drive;

    if (drive <= rearmDrive) _armed = true;
    if (!_armed ||
        drive < triggerDrive ||
        _secondsSinceImpact < refractorySeconds) {
      return null;
    }

    final angle = _impactAngle(
      delta: delta,
      fallback: _finiteAngle(target.colorPhase),
    );
    final highBandShare = _unit(target.highBandShare);
    final originRadius = math.min(
      _maximumOriginRadius,
      0.14 + 0.20 * highBandShare + 0.05 * safeFlux,
    );
    final strengthInput = _unit((drive - triggerDrive) / (1 - triggerDrive));
    final strengthCurve =
        strengthInput * strengthInput * (3 - 2 * strengthInput);
    final impact = RecordingMembraneImpactSnapshot(
      id: _nextId++,
      age: 0,
      strength: 0.40 + 0.60 * strengthCurve,
      angle: angle,
      origin: RecordingMembraneImpactOrigin(
        x: originRadius * math.cos(angle),
        y: originRadius * math.sin(angle),
      ),
      eccentricity: math.min(
        _maximumEccentricity,
        0.10 + 0.30 * highBandShare + 0.12 * safeFlux,
      ),
      colorPhase: _finiteAngle(target.colorPhase),
      highBandShare: highBandShare,
      lifetime: impactLifetime,
    );

    final next = List<RecordingMembraneImpactSnapshot>.of(_impacts);
    if (next.length == maxImpacts) next.removeAt(0);
    next.add(impact);
    _impacts = List<RecordingMembraneImpactSnapshot>.unmodifiable(next);
    _armed = false;
    _secondsSinceImpact = 0;
    return impact;
  }

  /// Advances causal ripple time and returns whether an impact remains alive.
  bool advance(double elapsedSeconds) {
    if (!elapsedSeconds.isFinite || elapsedSeconds <= 0) {
      return hasActiveImpacts;
    }
    _secondsSinceImpact = math.min(
      refractorySeconds,
      _secondsSinceImpact + elapsedSeconds,
    );
    if (_impacts.isEmpty) return false;
    _impacts = List<RecordingMembraneImpactSnapshot>.unmodifiable(
      _impacts
          .map((impact) => impact._advanced(elapsedSeconds))
          .where((impact) => impact.isAlive),
    );
    return hasActiveImpacts;
  }

  /// Removes visible ripples while preserving detector history and IDs.
  void clear() {
    _impacts = const [];
  }

  /// Starts a completely new deterministic recording session.
  void reset() {
    clear();
    _previousCoefficients = null;
    _nextId = 0;
    _armed = true;
    _secondsSinceImpact = double.infinity;
    _lastDrive = 0;
    _lastShapeKick = 0;
  }

  static List<double> _coefficientDelta(
    List<double> current,
    List<double>? previous,
  ) {
    final delta = List<double>.filled(
      RecordingMembraneModel.coefficientCount,
      0,
    );
    for (var index = 1; index < delta.length; index++) {
      delta[index] = current[index] - (previous?[index] ?? 0);
    }
    return delta;
  }

  static double _shapeKick(List<double> delta) {
    var sum = 0.0;
    for (var index = 1; index < delta.length; index++) {
      sum += delta[index] * delta[index];
    }
    final rms = math.sqrt(sum / (delta.length - 1));
    return _unit(rms / _shapeKickReference);
  }

  static double _impactAngle({
    required List<double> delta,
    required double fallback,
  }) {
    final field = RecordingMembraneModel.periodicValues(delta);
    var maximum = 0.0;
    var maximumSample = 0;
    var weightedX = 0.0;
    var weightedY = 0.0;
    var totalWeight = 0.0;
    for (var sample = 0; sample < field.length; sample++) {
      final magnitude = field[sample].abs();
      final angle = -math.pi / 2 + sample * 2 * math.pi / field.length;
      if (magnitude > maximum) {
        maximum = magnitude;
        maximumSample = sample;
      }
      final weight = magnitude * magnitude;
      weightedX += weight * math.cos(angle);
      weightedY += weight * math.sin(angle);
      totalWeight += weight;
    }
    if (maximum <= 1e-9 || totalWeight <= 1e-12) return fallback;

    final resultant = math.sqrt(weightedX * weightedX + weightedY * weightedY);
    final fieldAngle =
        resultant / totalWeight > 0.08
            ? math.atan2(weightedY, weightedX)
            : -math.pi / 2 + maximumSample * 2 * math.pi / field.length;
    final confidence = _unit(maximum / _shapeKickReference);
    return _wrappedAngle(
      fallback +
          _wrappedAngle(fieldAngle - fallback) * (0.35 + 0.65 * confidence),
    );
  }
}

double _unit(double value) {
  if (!value.isFinite) return 0;
  return value.clamp(0.0, 1.0).toDouble();
}

double _smoothstep(double value) => value * value * (3 - 2 * value);

double _finiteAngle(double value) =>
    value.isFinite ? _wrappedAngle(value) : -math.pi / 2;

double _wrappedAngle(double value) {
  var wrapped = value;
  while (wrapped > math.pi) {
    wrapped -= 2 * math.pi;
  }
  while (wrapped < -math.pi) {
    wrapped += 2 * math.pi;
  }
  return wrapped;
}
