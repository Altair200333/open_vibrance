import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:open_vibrance/services/audio_spectrum_analyzer.dart';
import 'package:open_vibrance/services/recording_membrane.dart';
import 'package:open_vibrance/services/recording_membrane_impact.dart';

Future<void> main(List<String> arguments) async {
  final options = _LabOptions.parse(arguments);
  final audioFiles = _discoverAudio(options);
  if (audioFiles.isEmpty) {
    stderr.writeln(
      'No WAV recordings found. Pass --input <file-or-directory>.',
    );
    exitCode = 64;
    return;
  }

  final output = Directory(options.outputPath)..createSync(recursive: true);
  final simulations = <_Simulation>[];
  for (final file in audioFiles) {
    stdout.writeln('Analyzing ${file.path}');
    final wav = _WavAudio.read(file);
    final simulation = _simulate(wav, fps: options.fps);
    simulations.add(simulation);
    await _writeRecordingArtifacts(output, simulation);
  }

  final summary = _buildSummary(simulations, options);
  File(
    '${output.path}${Platform.pathSeparator}summary.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(summary));
  File(
    '${output.path}${Platform.pathSeparator}summary.md',
  ).writeAsStringSync(_summaryMarkdown(simulations, options));
  File(
    '${output.path}${Platform.pathSeparator}replay.html',
  ).writeAsStringSync(_replayHtml(simulations));

  final renderFrames = _combinedRenderFrames(simulations);
  final renderInput = File(
    '${output.path}${Platform.pathSeparator}render_frames.json',
  );
  renderInput.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(renderFrames),
  );
  final impactPayload = _impactRenderPayload(simulations);
  final impactInput = File(
    '${output.path}${Platform.pathSeparator}impact_frames.json',
  );
  impactInput.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(impactPayload),
  );
  final impactEventCount = (impactPayload['events'] as List).length;
  if (impactEventCount < 3) {
    stderr.writeln(
      'Only $impactEventCount eligible emitted impacts were found; the impact grid will contain empty rows.',
    );
  }

  var pngRendered = false;
  if (options.renderPng) {
    pngRendered = await _renderExactPngs(output, renderInput, impactInput);
  }

  stdout.writeln('');
  stdout.writeln('Membrane lab complete: ${output.absolute.path}');
  stdout.writeln(
    '  summary: ${File('${output.path}${Platform.pathSeparator}summary.md').absolute.path}',
  );
  stdout.writeln(
    '  replay:  ${File('${output.path}${Platform.pathSeparator}replay.html').absolute.path}',
  );
  if (pngRendered) {
    stdout.writeln(
      '  exact PNG: ${File('${output.path}${Platform.pathSeparator}contact-sheet.png').absolute.path}',
    );
    stdout.writeln(
      '  impact PNG: ${File('${output.path}${Platform.pathSeparator}impact-grid.png').absolute.path}',
    );
  }
}

final class _LabOptions {
  const _LabOptions({
    required this.inputs,
    required this.longest,
    required this.outputPath,
    required this.fps,
    required this.renderPng,
  });

  final List<String> inputs;
  final int longest;
  final String outputPath;
  final int fps;
  final bool renderPng;

  static _LabOptions parse(List<String> arguments) {
    final inputs = <String>[];
    var longest = 3;
    var outputPath = 'build${Platform.pathSeparator}membrane_lab';
    var fps = 60;
    var renderPng = true;

    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      String valueFor(String name) {
        if (index + 1 >= arguments.length) {
          throw FormatException('Missing value after $name');
        }
        return arguments[++index];
      }

      switch (argument) {
        case '--input':
        case '-i':
          inputs.add(valueFor(argument));
        case '--longest':
          longest = int.parse(valueFor(argument));
        case '--out':
        case '-o':
          outputPath = valueFor(argument);
        case '--fps':
          fps = int.parse(valueFor(argument));
        case '--no-png':
          renderPng = false;
        case '--help':
        case '-h':
          stdout.writeln(_usage);
          exit(0);
        default:
          throw FormatException('Unknown argument: $argument\n\n$_usage');
      }
    }

    final appData = Platform.environment['APPDATA'];
    if (inputs.isEmpty && appData != null) {
      inputs.add(
        '$appData${Platform.pathSeparator}com.example${Platform.pathSeparator}open_vibrance${Platform.pathSeparator}recordings',
      );
    }
    if (longest < 1) throw const FormatException('--longest must be >= 1');
    if (fps < 30 || fps > 120) {
      throw const FormatException('--fps must be between 30 and 120');
    }
    return _LabOptions(
      inputs: List<String>.unmodifiable(inputs),
      longest: longest,
      outputPath: outputPath,
      fps: fps,
      renderPng: renderPng,
    );
  }

  static const _usage = '''
Offline Open Vibrance membrane lab

Usage:
  dart run tool/membrane_lab.dart [options]

Options:
  -i, --input <wav|directory>  Repeatable; defaults to the app recordings folder
      --longest <count>        Analyze the longest recordings (default: 3)
  -o, --out <directory>       Artifact directory (default: build/membrane_lab)
      --fps <30..120>         Simulation cadence (default: 60)
      --no-png                Skip exact Flutter contact-sheet rendering
  -h, --help                  Show this help
''';
}

List<File> _discoverAudio(_LabOptions options) {
  final files = <File>[];
  for (final input in options.inputs) {
    final type = FileSystemEntity.typeSync(input);
    if (type == FileSystemEntityType.file &&
        input.toLowerCase().endsWith('.wav')) {
      files.add(File(input));
    } else if (type == FileSystemEntityType.directory) {
      files.addAll(
        Directory(input)
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((file) => file.path.toLowerCase().endsWith('.wav')),
      );
    }
  }
  final unique = <String, File>{};
  for (final file in files) {
    unique[file.absolute.path.toLowerCase()] = file.absolute;
  }
  final compatible = <(File, int)>[];
  for (final file in unique.values) {
    final samples = _compatiblePcm16Samples(file);
    if (samples != null) compatible.add((file, samples));
  }
  compatible.sort((first, second) {
    final durationOrder = second.$2.compareTo(first.$2);
    return durationOrder != 0
        ? durationOrder
        : first.$1.path.compareTo(second.$1.path);
  });
  return List<File>.unmodifiable(
    compatible.take(options.longest).map((entry) => entry.$1),
  );
}

int? _compatiblePcm16Samples(File file) {
  try {
    final handle = file.openSync();
    final bytes = handle.readSync(math.min(4096, file.lengthSync()));
    handle.closeSync();
    if (bytes.length < 44 ||
        ascii.decode(bytes.sublist(0, 4), allowInvalid: true) != 'RIFF' ||
        ascii.decode(bytes.sublist(8, 12), allowInvalid: true) != 'WAVE') {
      return null;
    }
    final data = ByteData.sublistView(bytes);
    int? audioFormat;
    int? channels;
    int? sampleRate;
    int? bitsPerSample;
    int? dataSize;
    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final id = ascii.decode(
        bytes.sublist(offset, offset + 4),
        allowInvalid: true,
      );
      final chunkSize = data.getUint32(offset + 4, Endian.little);
      final payload = offset + 8;
      if (id == 'fmt ' && payload + 16 <= bytes.length) {
        audioFormat = data.getUint16(payload, Endian.little);
        channels = data.getUint16(payload + 2, Endian.little);
        sampleRate = data.getUint32(payload + 4, Endian.little);
        bitsPerSample = data.getUint16(payload + 14, Endian.little);
      } else if (id == 'data') {
        dataSize = math.min(chunkSize, file.lengthSync() - payload);
        break;
      }
      final next = payload + chunkSize + chunkSize.isOdd.toInt();
      if (next <= offset || next > bytes.length) break;
      offset = next;
    }
    if (audioFormat != 1 ||
        channels != 1 ||
        sampleRate != 16000 ||
        bitsPerSample != 16 ||
        dataSize == null) {
      return null;
    }
    return dataSize ~/ 2;
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  } on RangeError {
    return null;
  }
}

final class _WavAudio {
  const _WavAudio({
    required this.file,
    required this.sampleRate,
    required this.samples,
    required this.pcmBytes,
  });

  final File file;
  final int sampleRate;
  final int samples;
  final Uint8List pcmBytes;

  double get durationSeconds => samples / sampleRate;

  static _WavAudio read(File file) {
    final bytes = file.readAsBytesSync();
    if (bytes.length < 44 ||
        ascii.decode(bytes.sublist(0, 4), allowInvalid: true) != 'RIFF' ||
        ascii.decode(bytes.sublist(8, 12), allowInvalid: true) != 'WAVE') {
      throw FormatException('${file.path}: not a RIFF/WAVE file');
    }
    final data = ByteData.sublistView(bytes);
    int? sampleRate;
    int? channels;
    int? bitsPerSample;
    int? audioFormat;
    Uint8List? pcm;
    final riffEnd = math.min(
      bytes.length,
      8 + data.getUint32(4, Endian.little),
    );
    var offset = 12;
    while (offset + 8 <= riffEnd) {
      final id = ascii.decode(
        bytes.sublist(offset, offset + 4),
        allowInvalid: true,
      );
      final chunkSize = data.getUint32(offset + 4, Endian.little);
      final payload = offset + 8;
      if (payload + chunkSize > riffEnd) {
        throw FormatException('${file.path}: truncated $id chunk');
      }
      if (id == 'fmt ' && chunkSize >= 16) {
        audioFormat = data.getUint16(payload, Endian.little);
        channels = data.getUint16(payload + 2, Endian.little);
        sampleRate = data.getUint32(payload + 4, Endian.little);
        bitsPerSample = data.getUint16(payload + 14, Endian.little);
      } else if (id == 'data') {
        pcm = Uint8List.sublistView(bytes, payload, payload + chunkSize);
      }
      offset = payload + chunkSize + chunkSize.isOdd.toInt();
    }
    if (audioFormat != 1 || channels != 1 || bitsPerSample != 16) {
      throw FormatException(
        '${file.path}: lab requires PCM16 mono; got format=$audioFormat channels=$channels bits=$bitsPerSample',
      );
    }
    if (sampleRate != 16000) {
      throw FormatException(
        '${file.path}: lab requires 16 kHz audio; got $sampleRate Hz',
      );
    }
    if (pcm == null) throw FormatException('${file.path}: missing data chunk');
    return _WavAudio(
      file: file.absolute,
      sampleRate: sampleRate!,
      samples: pcm.length ~/ 2,
      pcmBytes: Uint8List.fromList(pcm),
    );
  }
}

extension on bool {
  int toInt() => this ? 1 : 0;
}

final class _Simulation {
  const _Simulation({
    required this.wav,
    required this.fps,
    required this.frames,
    required this.baselineMetrics,
    required this.candidateMetrics,
    required this.impactEmissions,
    required this.impactMetrics,
  });

  final _WavAudio wav;
  final int fps;
  final List<_SimFrame> frames;
  final Map<String, Object> baselineMetrics;
  final Map<String, Object> candidateMetrics;
  final List<_ImpactEmission> impactEmissions;
  final Map<String, Object> impactMetrics;
}

final class _ImpactEmission {
  const _ImpactEmission({
    required this.id,
    required this.time,
    required this.strength,
  });

  final int id;
  final double time;
  final double strength;
}

final class _SelectedImpact {
  const _SelectedImpact({
    required this.tier,
    required this.simulation,
    required this.emission,
  });

  final String tier;
  final _Simulation simulation;
  final _ImpactEmission emission;
}

typedef _ImpactCandidate = ({_Simulation simulation, _ImpactEmission emission});

final class _ShapeState {
  const _ShapeState({
    required this.coefficients,
    required this.velocity,
    required this.radii,
  });

  final List<double> coefficients;
  final List<double> velocity;
  final List<double> radii;
}

final class _SimFrame {
  const _SimFrame({
    required this.time,
    required this.sequence,
    required this.level,
    required this.flux,
    required this.activityDb,
    required this.candidateTarget,
    required this.baseline,
    required this.candidate,
    required this.impacts,
    required this.impactDrive,
    required this.impactShapeKick,
  });

  final double time;
  final int sequence;
  final double level;
  final double flux;
  final double activityDb;
  final RecordingMembraneTarget candidateTarget;
  final _ShapeState baseline;
  final _ShapeState candidate;
  final List<RecordingMembraneImpactSnapshot> impacts;
  final double impactDrive;
  final double impactShapeKick;
}

_Simulation _simulate(_WavAudio wav, {required int fps}) {
  final analyzer = AudioSpectrumAnalyzer(sampleRate: wav.sampleRate);
  final events = <AudioSpectrumFrame>[];
  const chunkBytes = 4096;
  for (var offset = 0; offset < wav.pcmBytes.length; offset += chunkBytes) {
    analyzer.addPcm16(
      Uint8List.sublistView(
        wav.pcmBytes,
        offset,
        math.min(wav.pcmBytes.length, offset + chunkBytes),
      ),
      events.add,
    );
  }

  final zeroBands = List<double>.filled(AudioSpectrumFrame.bandCount, 0);
  final mapper = RecordingMembraneMapper();
  final impactController = RecordingMembraneImpactController();
  final impactEmissions = <_ImpactEmission>[];
  var candidateTarget = mapper.map(
    level: 0,
    bands: zeroBands,
    flux: 0,
    spectrumMix: 0,
  );
  final initial = RecordingMembraneModel.coefficientsFor(
    level: 0,
    bands: zeroBands,
    flux: 0,
    spectrumMix: 0,
  );
  final baselineDynamics = RecordingMembraneDynamics(initial);
  final candidateDynamics = RecordingMembraneDynamics(initial);
  final frames = <_SimFrame>[];
  var eventIndex = 0;
  var currentTime = 0.0;
  var previousEventTime = 0.0;
  var silenceApplied = false;
  var lastSequence = 0;
  var lastLevel = 0.0;
  var lastFlux = 0.0;
  var lastActivityDb = -160.0;
  const tailSeconds = 0.75;
  final frameCount = ((wav.durationSeconds + tailSeconds) * fps).ceil();

  void advanceTo(double targetTime) {
    final dt = targetTime - currentTime;
    if (dt > 1e-12) {
      baselineDynamics.advance(dt);
      candidateDynamics.advance(dt);
      impactController.advance(dt);
      currentTime = targetTime;
    }
  }

  for (var frameIndex = 0; frameIndex <= frameCount; frameIndex++) {
    final outputTime = frameIndex / fps;
    while (eventIndex < events.length) {
      final event = events[eventIndex];
      final eventTime = event.endSampleExclusive / wav.sampleRate;
      if (eventTime > outputTime + 1e-12) break;
      advanceTo(eventTime);
      final eventDt = math.max(
        RecordingMembraneMapper.defaultFrameSeconds,
        eventTime - previousEventTime,
      );
      candidateTarget = mapper.map(
        level: event.level,
        bands: event.bands,
        flux: event.flux,
        elapsedSeconds: eventDt,
      );
      final emittedImpact = impactController.processTarget(candidateTarget);
      if (emittedImpact != null) {
        impactEmissions.add(
          _ImpactEmission(
            id: emittedImpact.id,
            time: eventTime,
            strength: emittedImpact.strength,
          ),
        );
      }
      candidateDynamics.retarget(candidateTarget.coefficients);
      baselineDynamics.retarget(
        RecordingMembraneModel.coefficientsFor(
          level: event.level,
          bands: event.bands,
          flux: event.flux,
          spectrumMix: 1,
        ),
      );
      previousEventTime = eventTime;
      lastSequence = event.sequence;
      lastLevel = event.level;
      lastFlux = event.flux;
      lastActivityDb = event.activityDb;
      eventIndex++;
    }

    if (!silenceApplied && wav.durationSeconds <= outputTime) {
      advanceTo(wav.durationSeconds);
      candidateTarget = mapper.map(
        level: 0,
        bands: zeroBands,
        flux: 0,
        spectrumMix: 0,
      );
      impactController.reset();
      candidateDynamics.retarget(candidateTarget.coefficients);
      baselineDynamics.retarget(initial);
      lastLevel = 0;
      lastFlux = 0;
      lastActivityDb = -160;
      silenceApplied = true;
    }
    advanceTo(outputTime);

    final baselineCoefficients = baselineDynamics.snapshot;
    final candidateCoefficients = candidateDynamics.snapshot;
    frames.add(
      _SimFrame(
        time: outputTime,
        sequence: lastSequence,
        level: lastLevel,
        flux: lastFlux,
        activityDb: lastActivityDb,
        candidateTarget: candidateTarget,
        baseline: _ShapeState(
          coefficients: baselineCoefficients,
          velocity: baselineDynamics.velocity,
          radii: RecordingMembraneModel.radiiFromCoefficients(
            baselineCoefficients,
          ),
        ),
        candidate: _ShapeState(
          coefficients: candidateCoefficients,
          velocity: candidateDynamics.velocity,
          radii: RecordingMembraneModel.radiiFromCoefficients(
            candidateCoefficients,
          ),
        ),
        impacts: impactController.impacts,
        impactDrive: impactController.lastDrive,
        impactShapeKick: impactController.lastShapeKick,
      ),
    );
  }

  return _Simulation(
    wav: wav,
    fps: fps,
    frames: List<_SimFrame>.unmodifiable(frames),
    baselineMetrics: _metrics(frames, (frame) => frame.baseline),
    candidateMetrics: _metrics(frames, (frame) => frame.candidate),
    impactEmissions: List<_ImpactEmission>.unmodifiable(impactEmissions),
    impactMetrics: _impactMetrics(
      frames,
      impactEmissions,
      durationSeconds: wav.durationSeconds,
    ),
  );
}

Map<String, Object> _metrics(
  List<_SimFrame> frames,
  _ShapeState Function(_SimFrame frame) select,
) {
  final active = frames.where((frame) => frame.activityDb >= -62).toList();
  final ranges = <double>[];
  final orientations = <double>[];
  final peakCounts = <int>[];
  final modeHighShares = <double>[];
  final similarities = <double>[];
  final motions = <double>[];
  final accelerations = <double>[];
  final adjacentSimilarities = <double>[];
  final radialJumps = <double>[];
  final levels = <double>[];
  final normalized = <List<double>>[];

  for (var index = 0; index < active.length; index++) {
    final frame = active[index];
    final shape = select(frame);
    final radii = shape.radii;
    ranges.add(_range(radii));
    orientations.add(_orientation(radii));
    peakCounts.add(_prominentPeakCount(radii));
    modeHighShares.add(_highModeShare(shape.coefficients));
    normalized.add(_normalizedShape(radii));
    levels.add(frame.level);
    if (index > 0 && active[index].time - active[index - 1].time < 0.03) {
      final previousRadii = select(active[index - 1]).radii;
      motions.add(_rmsDifference(radii, previousRadii));
      radialJumps.add(_maxDifference(radii, previousRadii));
      adjacentSimilarities.add(
        _dot(_normalizedShape(radii), _normalizedShape(previousRadii)),
      );
      if (index > 1 && active[index - 1].time - active[index - 2].time < 0.03) {
        final olderRadii = select(active[index - 2]).radii;
        var accelerationSquared = 0.0;
        for (var sample = 0; sample < radii.length; sample++) {
          final acceleration =
              radii[sample] - 2 * previousRadii[sample] + olderRadii[sample];
          accelerationSquared += acceleration * acceleration;
        }
        accelerations.add(math.sqrt(accelerationSquared / radii.length));
      }
    }
  }

  if (active.isEmpty) return const {'active_frames': 0};
  final prototype = List<double>.filled(
    RecordingMembraneModel.contourSampleCount,
    0,
  );
  for (final shape in normalized) {
    for (var sample = 0; sample < shape.length; sample++) {
      prototype[sample] += shape[sample] / normalized.length;
    }
  }
  final prototypeNorm = math.sqrt(
    prototype.fold<double>(0, (sum, value) => sum + value * value),
  );
  for (final shape in normalized) {
    var dot = 0.0;
    for (var sample = 0; sample < shape.length; sample++) {
      dot += shape[sample] * prototype[sample];
    }
    similarities.add(prototypeNorm > 1e-12 ? dot / prototypeNorm : 1);
  }

  var orientationX = 0.0;
  var orientationY = 0.0;
  final occupiedBins = <int>{};
  for (final angle in orientations) {
    orientationX += math.cos(angle);
    orientationY += math.sin(angle);
    occupiedBins.add((((angle + math.pi) / (2 * math.pi) * 12).floor()) % 12);
  }
  final concentration =
      math.sqrt(orientationX * orientationX + orientationY * orientationY) /
      orientations.length;
  final fourPeakShare =
      peakCounts.where((count) => count >= 4).length / peakCounts.length;
  final twoThreePeakShare =
      peakCounts.where((count) => count == 2 || count == 3).length /
      peakCounts.length;

  return {
    'active_frames': active.length,
    'range_median_px': _quantile(ranges, 0.5),
    'range_p90_px': _quantile(ranges, 0.9),
    'motion_median_px': motions.isEmpty ? 0 : _quantile(motions, 0.5),
    'motion_p90_px': motions.isEmpty ? 0 : _quantile(motions, 0.9),
    'acceleration_p95_px':
        accelerations.isEmpty ? 0 : _quantile(accelerations, 0.95),
    'adjacent_similarity_p05':
        adjacentSimilarities.isEmpty
            ? 1
            : _quantile(adjacentSimilarities, 0.05),
    'radial_jump_p99_px':
        radialJumps.isEmpty ? 0 : _quantile(radialJumps, 0.99),
    'prototype_similarity_mean': _mean(similarities),
    'orientation_concentration': concentration,
    'orientation_bins_12': occupiedBins.length,
    'two_three_peak_share': twoThreePeakShare,
    'four_plus_peak_share': fourPeakShare,
    'modes_4_5_share_mean': _mean(modeHighShares),
    'range_level_correlation': _correlation(ranges, levels),
  };
}

Map<String, Object> _impactMetrics(
  List<_SimFrame> frames,
  List<_ImpactEmission> emissions, {
  required double durationSeconds,
}) {
  final strengths = emissions
      .map((emission) => emission.strength)
      .toList(growable: false);
  final speechFrames = frames
      .where((frame) => frame.activityDb >= -62)
      .toList(growable: false);
  final drives = speechFrames
      .map((frame) => frame.impactDrive)
      .toList(growable: false);
  final shapeKicks = speechFrames
      .map((frame) => frame.impactShapeKick)
      .toList(growable: false);
  final activeFrames = frames.where((frame) => frame.impacts.isNotEmpty).length;
  var maximumConcurrent = 0;
  for (final frame in frames) {
    maximumConcurrent = math.max(maximumConcurrent, frame.impacts.length);
  }
  final gaps = <double>[];
  for (var index = 1; index < emissions.length; index++) {
    gaps.add(emissions[index].time - emissions[index - 1].time);
  }
  return {
    'emitted_count': emissions.length,
    'emitted_per_second':
        durationSeconds > 0 ? emissions.length / durationSeconds : 0,
    'gap_median_seconds': gaps.isEmpty ? 0 : _quantile(gaps, 0.50),
    'gap_p90_seconds': gaps.isEmpty ? 0 : _quantile(gaps, 0.90),
    'gap_max_seconds': gaps.isEmpty ? 0 : gaps.reduce(math.max),
    'strength_min': strengths.isEmpty ? 0 : strengths.reduce(math.min),
    'strength_median': strengths.isEmpty ? 0 : _quantile(strengths, 0.5),
    'strength_max': strengths.isEmpty ? 0 : strengths.reduce(math.max),
    'active_frame_share': frames.isEmpty ? 0 : activeFrames / frames.length,
    'max_concurrent': maximumConcurrent,
    'drive_p50': drives.isEmpty ? 0 : _quantile(drives, 0.50),
    'drive_p75': drives.isEmpty ? 0 : _quantile(drives, 0.75),
    'drive_p90': drives.isEmpty ? 0 : _quantile(drives, 0.90),
    'drive_above_trigger_share':
        drives.isEmpty
            ? 0
            : drives
                    .where(
                      (drive) =>
                          drive >=
                          RecordingMembraneImpactController.triggerDrive,
                    )
                    .length /
                drives.length,
    'shape_kick_p50': shapeKicks.isEmpty ? 0 : _quantile(shapeKicks, 0.50),
    'shape_kick_p90': shapeKicks.isEmpty ? 0 : _quantile(shapeKicks, 0.90),
  };
}

Future<void> _writeRecordingArtifacts(
  Directory root,
  _Simulation simulation,
) async {
  final name = _stem(simulation.wav.file.path);
  final directory = Directory(
    '${root.path}${Platform.pathSeparator}recordings${Platform.pathSeparator}$name',
  )..createSync(recursive: true);
  final points =
      File(
        '${directory.path}${Platform.pathSeparator}points.ndjson',
      ).openWrite();
  for (var index = 0; index < simulation.frames.length; index++) {
    final frame = simulation.frames[index];
    points.writeln(
      jsonEncode({
        'frame': index,
        't': _rounded(frame.time),
        'sequence': frame.sequence,
        'level': _rounded(frame.level),
        'flux': _rounded(frame.flux),
        'baseline': frame.baseline.radii.map(_rounded).toList(),
        'candidate': frame.candidate.radii.map(_rounded).toList(),
        'impacts': frame.impacts.map(_impactJson).toList(growable: false),
        'impact_drive': _rounded(frame.impactDrive),
        'impact_shape_kick': _rounded(frame.impactShapeKick),
      }),
    );
  }
  await points.close();

  final trace = {
    'source': simulation.wav.file.path,
    'duration_seconds': simulation.wav.durationSeconds,
    'fps': simulation.fps,
    'baseline_metrics': simulation.baselineMetrics,
    'candidate_metrics': simulation.candidateMetrics,
    'impact_metrics': simulation.impactMetrics,
    'impact_emissions': [
      for (final emission in simulation.impactEmissions)
        {
          'id': emission.id,
          'time': _rounded(emission.time),
          'strength': _rounded(emission.strength),
        },
    ],
  };
  File(
    '${directory.path}${Platform.pathSeparator}trace.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(trace));
  File(
    '${directory.path}${Platform.pathSeparator}contact-sheet.svg',
  ).writeAsStringSync(_contactSheetSvg(simulation));
}

Map<String, Object> _buildSummary(
  List<_Simulation> simulations,
  _LabOptions options,
) => {
  'schema': 2,
  'generated_at': DateTime.now().toUtc().toIso8601String(),
  'fps': options.fps,
  'recordings': [
    for (final simulation in simulations)
      {
        'path': simulation.wav.file.path,
        'duration_seconds': simulation.wav.durationSeconds,
        'baseline': simulation.baselineMetrics,
        'candidate': simulation.candidateMetrics,
        'impacts': simulation.impactMetrics,
      },
  ],
};

String _summaryMarkdown(List<_Simulation> simulations, _LabOptions options) {
  final buffer =
      StringBuffer()
        ..writeln('# Recording membrane lab')
        ..writeln()
        ..writeln(
          'Simulation: exact analyzer + shared membrane core at ${options.fps} FPS.',
        )
        ..writeln()
        ..writeln(
          '| Recording | Model | Range med / P90 | Motion med / P90 | Adjacent P05 | Accel P95 | Jump P99 | Prototype similarity | Orientation R | 4+ peaks | Modes 4+5 | Range/level r |',
        )
        ..writeln(
          '|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|',
        );
  for (final simulation in simulations) {
    final name = _stem(simulation.wav.file.path);
    for (final entry in [
      ('baseline', simulation.baselineMetrics),
      ('candidate', simulation.candidateMetrics),
    ]) {
      final metrics = entry.$2;
      buffer.writeln(
        '| $name | ${entry.$1} | ${_metric(metrics, 'range_median_px')} / ${_metric(metrics, 'range_p90_px')} | ${_metric(metrics, 'motion_median_px')} / ${_metric(metrics, 'motion_p90_px')} | ${_metric(metrics, 'adjacent_similarity_p05')} | ${_metric(metrics, 'acceleration_p95_px')} | ${_metric(metrics, 'radial_jump_p99_px')} | ${_metric(metrics, 'prototype_similarity_mean')} | ${_metric(metrics, 'orientation_concentration')} | ${_percentMetric(metrics, 'four_plus_peak_share')} | ${_percentMetric(metrics, 'modes_4_5_share_mean')} | ${_metric(metrics, 'range_level_correlation')} |',
      );
    }
  }
  buffer
    ..writeln()
    ..writeln(
      '| Recording | Impacts | Rate/s | Gap med / P90 | Strength min / med / max | Active frames | Max concurrent | Drive P50 / P90 | Above trigger |',
    )
    ..writeln('|---|---:|---:|---:|---:|---:|---:|---:|---:|');
  for (final simulation in simulations) {
    final metrics = simulation.impactMetrics;
    buffer.writeln(
      '| ${_stem(simulation.wav.file.path)} | ${metrics['emitted_count']} | ${_metric(metrics, 'emitted_per_second')} | ${_metric(metrics, 'gap_median_seconds')} / ${_metric(metrics, 'gap_p90_seconds')} | ${_metric(metrics, 'strength_min')} / ${_metric(metrics, 'strength_median')} / ${_metric(metrics, 'strength_max')} | ${_percentMetric(metrics, 'active_frame_share')} | ${metrics['max_concurrent']} | ${_metric(metrics, 'drive_p50')} / ${_metric(metrics, 'drive_p90')} | ${_percentMetric(metrics, 'drive_above_trigger_share')} |',
    );
  }
  buffer
    ..writeln()
    ..writeln(
      'Artifacts use stored 96-point contours; replay code does not reimplement the audio model.',
    )
    ..writeln(
      '`contact-sheet.png` is rendered by Flutter with the production painter. Per-recording SVG/NDJSON files remain portable inspection artifacts.',
    );
  return buffer.toString();
}

String _metric(Map<String, Object> metrics, String key) {
  final value = metrics[key];
  return value is num ? value.toStringAsFixed(3) : '-';
}

String _percentMetric(Map<String, Object> metrics, String key) {
  final value = metrics[key];
  return value is num ? '${(value * 100).toStringAsFixed(1)}%' : '-';
}

List<_SimFrame> _representativeFrames(
  _Simulation simulation, {
  int count = 24,
}) {
  final active = simulation.frames
      .where((frame) => frame.activityDb >= -62)
      .toList(growable: false);
  if (active.length <= count) return active;
  final chronologicalCount = count ~/ 2;
  final selected = <_SimFrame>[];
  for (var index = 0; index < chronologicalCount; index++) {
    final position = ((index + 0.5) / chronologicalCount * active.length)
        .floor()
        .clamp(0, active.length - 1);
    selected.add(active[position]);
  }
  var seed = active.reduce(
    (first, second) =>
        _range(first.candidate.radii) >= _range(second.candidate.radii)
            ? first
            : second,
  );
  selected.add(seed);
  while (selected.length < count) {
    _SimFrame? best;
    var bestDistance = -1.0;
    for (final candidate in active) {
      if (selected.any((item) => (item.time - candidate.time).abs() < 0.35)) {
        continue;
      }
      var nearest = double.infinity;
      final normalizedCandidate = _normalizedShape(candidate.candidate.radii);
      for (final item in selected) {
        final distance = _shapeDistance(
          normalizedCandidate,
          _normalizedShape(item.candidate.radii),
        );
        nearest = math.min(nearest, distance);
      }
      if (nearest > bestDistance) {
        best = candidate;
        bestDistance = nearest;
      }
    }
    if (best == null) break;
    seed = best;
    selected.add(seed);
  }
  selected.sort((first, second) => first.time.compareTo(second.time));
  return List<_SimFrame>.unmodifiable(selected.take(count));
}

String _contactSheetSvg(_Simulation simulation) {
  final frames = _representativeFrames(simulation);
  const columns = 6;
  const cellWidth = 180;
  const cellHeight = 150;
  final rows = (frames.length / columns).ceil();
  final buffer =
      StringBuffer()
        ..writeln(
          '<svg xmlns="http://www.w3.org/2000/svg" width="${columns * cellWidth}" height="${rows * cellHeight}" viewBox="0 0 ${columns * cellWidth} ${rows * cellHeight}">',
        )
        ..writeln(
          '<defs><radialGradient id="orb"><stop offset="0" stop-color="#4b0618"/><stop offset=".68" stop-color="#c7193f"/><stop offset="1" stop-color="#ff5269"/></radialGradient><filter id="glow"><feGaussianBlur stdDeviation="1.2"/></filter></defs>',
        )
        ..writeln('<rect width="100%" height="100%" fill="#08060d"/>');
  for (var index = 0; index < frames.length; index++) {
    final frame = frames[index];
    final column = index % columns;
    final row = index ~/ columns;
    final x = column * cellWidth;
    final y = row * cellHeight;
    final baselinePath = _svgPath(frame.baseline.radii, x + 48, y + 68, 3.2);
    final candidatePath = _svgPath(frame.candidate.radii, x + 132, y + 68, 3.2);
    buffer
      ..writeln(
        '<path d="$baselinePath" fill="#cf193c" stroke="#fff" stroke-opacity=".85" stroke-width="2.8"/>',
      )
      ..writeln(
        '<path d="$candidatePath" fill="none" stroke="#ff4f88" stroke-opacity=".22" stroke-width="7" filter="url(#glow)"/>',
      )
      ..writeln(
        '<path d="$candidatePath" fill="url(#orb)" stroke="#ffd9f0" stroke-width="2.4"/>',
      )
      ..writeln(
        '<text x="${x + 48}" y="${y + 121}" text-anchor="middle" fill="#918997" font-family="Segoe UI" font-size="11">OLD</text>',
      )
      ..writeln(
        '<text x="${x + 132}" y="${y + 121}" text-anchor="middle" fill="#f3b9d6" font-family="Segoe UI" font-size="11">NEW</text>',
      )
      ..writeln(
        '<text x="${x + 90}" y="${y + 140}" text-anchor="middle" fill="#c7c0cb" font-family="Segoe UI" font-size="10">${frame.time.toStringAsFixed(2)}s · L ${frame.level.toStringAsFixed(2)} · F ${frame.flux.toStringAsFixed(2)}</text>',
      );
  }
  buffer.writeln('</svg>');
  return buffer.toString();
}

String _svgPath(
  List<double> radii,
  double centerX,
  double centerY,
  double scale,
) {
  final buffer = StringBuffer();
  for (var sample = 0; sample < radii.length; sample++) {
    final angle = -math.pi / 2 + sample * 2 * math.pi / radii.length;
    final x = centerX + math.cos(angle) * radii[sample] * scale;
    final y = centerY + math.sin(angle) * radii[sample] * scale;
    buffer.write(sample == 0 ? 'M' : 'L');
    buffer.write('${x.toStringAsFixed(2)},${y.toStringAsFixed(2)}');
  }
  return '${buffer}Z';
}

Map<String, Object> _impactJson(RecordingMembraneImpactSnapshot impact) => {
  'id': impact.id,
  'age': impact.age,
  'strength': impact.strength,
  'angle': impact.angle,
  'origin_x': impact.origin.x,
  'origin_y': impact.origin.y,
  'eccentricity': impact.eccentricity,
  'color_phase': impact.colorPhase,
  'high_band_share': impact.highBandShare,
  'lifetime': impact.lifetime,
};

List<List<double>> _historyForFrame(_Simulation simulation, int frameIndex) => [
  for (final secondsAgo in const [
    0.0,
    0.048,
    0.096,
    0.144,
    0.192,
    0.240,
    0.288,
  ])
    simulation
        .frames[math.max(0, frameIndex - (secondsAgo * simulation.fps).round())]
        .candidate
        .coefficients,
];

Map<String, Object> _painterSnapshotJson(
  _Simulation simulation,
  int frameIndex,
) {
  final frame = simulation.frames[frameIndex];
  return {
    'recording': _stem(simulation.wav.file.path),
    'time': frame.time,
    'level': frame.level,
    'flux': frame.flux,
    'novelty': frame.candidateTarget.novelty,
    'color_phase': frame.candidateTarget.colorPhase,
    'baseline_coefficients': frame.baseline.coefficients,
    'candidate_coefficients': frame.candidate.coefficients,
    'candidate_velocity': frame.candidate.velocity,
    'candidate_history': _historyForFrame(simulation, frameIndex),
    'impacts': frame.impacts.map(_impactJson).toList(growable: false),
  };
}

List<Map<String, Object>> _combinedRenderFrames(List<_Simulation> simulations) {
  final output = <Map<String, Object>>[];
  for (final simulation in simulations) {
    final representatives = _representativeFrames(simulation, count: 8);
    for (final frame in representatives) {
      output.add(
        _painterSnapshotJson(simulation, simulation.frames.indexOf(frame)),
      );
    }
  }
  return output;
}

const _impactOffsetsMs = [-96, -48, 0, 48, 96, 144, 240, 384];

List<_SelectedImpact> _selectImpactEvents(List<_Simulation> simulations) {
  List<_ImpactCandidate> candidates({required bool requireFullWindow}) => [
    for (final simulation in simulations)
      for (final emission in simulation.impactEmissions)
        if (!requireFullWindow ||
            (emission.time >= 0.096 &&
                emission.time + 0.384 <= simulation.wav.durationSeconds))
          (simulation: simulation, emission: emission),
  ];

  var pool = candidates(requireFullWindow: true);
  if (pool.length < 3) pool = candidates(requireFullWindow: false);
  pool.sort((first, second) {
    final strengthOrder = first.emission.strength.compareTo(
      second.emission.strength,
    );
    if (strengthOrder != 0) return strengthOrder;
    final pathOrder = first.simulation.wav.file.path.compareTo(
      second.simulation.wav.file.path,
    );
    if (pathOrder != 0) return pathOrder;
    final timeOrder = first.emission.time.compareTo(second.emission.time);
    return timeOrder != 0
        ? timeOrder
        : first.emission.id.compareTo(second.emission.id);
  });
  if (pool.length < 3) return const [];

  final boundaries = [
    0,
    (pool.length / 3).ceil(),
    (2 * pool.length / 3).ceil(),
    pool.length,
  ];
  final tiers = ['low', 'medium', 'high'];
  final usedRecordings = <String>{};
  final selected = <_SelectedImpact>[];
  for (var tierIndex = 0; tierIndex < tiers.length; tierIndex++) {
    final group = pool.sublist(
      boundaries[tierIndex],
      boundaries[tierIndex + 1],
    );
    final targetStrength = _quantile(
      group.map((item) => item.emission.strength).toList(growable: false),
      0.5,
    );
    group.sort((first, second) {
      final firstUsed = usedRecordings.contains(first.simulation.wav.file.path);
      final secondUsed = usedRecordings.contains(
        second.simulation.wav.file.path,
      );
      if (firstUsed != secondUsed) return firstUsed ? 1 : -1;
      final distanceOrder = (first.emission.strength - targetStrength)
          .abs()
          .compareTo((second.emission.strength - targetStrength).abs());
      if (distanceOrder != 0) return distanceOrder;
      final pathOrder = first.simulation.wav.file.path.compareTo(
        second.simulation.wav.file.path,
      );
      if (pathOrder != 0) return pathOrder;
      return first.emission.time.compareTo(second.emission.time);
    });
    final choice = group.first;
    usedRecordings.add(choice.simulation.wav.file.path);
    selected.add(
      _SelectedImpact(
        tier: tiers[tierIndex],
        simulation: choice.simulation,
        emission: choice.emission,
      ),
    );
  }
  return List<_SelectedImpact>.unmodifiable(selected);
}

Map<String, Object> _impactRenderPayload(List<_Simulation> simulations) {
  final selected = _selectImpactEvents(simulations);
  return {
    'schema': 1,
    'offsets_ms': _impactOffsetsMs,
    'events': [
      for (final event in selected)
        {
          'tier': event.tier,
          'recording': _stem(event.simulation.wav.file.path),
          'impact_id': event.emission.id,
          'emission_time': event.emission.time,
          'strength': event.emission.strength,
          'snapshots': [
            for (final requestedOffsetMs in _impactOffsetsMs)
              () {
                final targetTime =
                    event.emission.time + requestedOffsetMs / 1000;
                final frameIndex = (targetTime * event.simulation.fps)
                    .ceil()
                    .clamp(0, event.simulation.frames.length - 1);
                final frame = event.simulation.frames[frameIndex];
                return {
                  'requested_offset_ms': requestedOffsetMs,
                  'actual_offset_ms':
                      ((frame.time - event.emission.time) * 1000).round(),
                  ..._painterSnapshotJson(event.simulation, frameIndex),
                };
              }(),
          ],
        },
    ],
  };
}

Future<bool> _renderExactPngs(
  Directory output,
  File input,
  File impactInput,
) async {
  final pngs = [
    File('${output.path}${Platform.pathSeparator}contact-sheet.png').absolute,
    File('${output.path}${Platform.pathSeparator}impact-grid.png').absolute,
  ];
  for (final png in pngs) {
    if (png.existsSync()) png.deleteSync();
  }
  final process = await Process.start('flutter', [
    'test',
    'tool${Platform.pathSeparator}membrane_lab_renderer_test.dart',
    '--dart-define=MEMBRANE_LAB_INPUT=${input.absolute.path}',
    '--dart-define=MEMBRANE_LAB_OUTPUT=${pngs[0].path}',
    '--dart-define=MEMBRANE_LAB_IMPACT_INPUT=${impactInput.absolute.path}',
    '--dart-define=MEMBRANE_LAB_IMPACT_OUTPUT=${pngs[1].path}',
  ], runInShell: Platform.isWindows);
  final processOutput = StringBuffer();
  process.stdout.transform(utf8.decoder).listen(processOutput.write);
  process.stderr.transform(utf8.decoder).listen(processOutput.write);
  final exitFuture = process.exitCode;
  int? exitCode;
  final lastPngLengths = List<int>.filled(pngs.length, -1);
  final stablePngPolls = List<int>.filled(pngs.length, 0);
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    for (var index = 0; index < pngs.length; index++) {
      final png = pngs[index];
      if (!png.existsSync()) continue;
      final length = png.lengthSync();
      if (length > 1000 && length == lastPngLengths[index]) {
        stablePngPolls[index]++;
      } else {
        stablePngPolls[index] = 0;
      }
      lastPngLengths[index] = length;
    }
    if (stablePngPolls.every((polls) => polls >= 6)) {
      await _stopProcessTree(process);
      return true;
    }
    exitCode = await exitFuture
        .then<int?>((value) => value)
        .timeout(const Duration(milliseconds: 250), onTimeout: () => null);
    if (exitCode != null) break;
  }
  if (exitCode == null) await _stopProcessTree(process);
  if (pngs.every((png) => png.existsSync() && png.lengthSync() > 1000)) {
    return true;
  }
  stderr.writeln(
    'Exact PNG rendering failed; portable SVG/HTML artifacts remain valid.',
  );
  stderr.writeln(processOutput);
  return false;
}

Future<void> _stopProcessTree(Process process) async {
  if (Platform.isWindows) {
    await Process.run('taskkill', [
      '/PID',
      '${process.pid}',
      '/T',
      '/F',
    ], runInShell: true);
    return;
  }
  process.kill(ProcessSignal.sigterm);
}

String _replayHtml(List<_Simulation> simulations) {
  final payload = [
    for (final simulation in simulations)
      {
        'name': _stem(simulation.wav.file.path),
        'fps': simulation.fps,
        'duration': simulation.wav.durationSeconds,
        'frames': [
          for (
            var index = 0;
            index < simulation.frames.length;
            index += math.max(1, simulation.fps ~/ 30)
          )
            {
              't': _rounded(simulation.frames[index].time),
              'l': _rounded(simulation.frames[index].level),
              'f': _rounded(simulation.frames[index].flux),
              'n': _rounded(simulation.frames[index].candidateTarget.novelty),
              'p': _rounded(
                simulation.frames[index].candidateTarget.colorPhase,
              ),
              'b':
                  simulation.frames[index].baseline.radii
                      .map(_rounded)
                      .toList(),
              'c':
                  simulation.frames[index].candidate.radii
                      .map(_rounded)
                      .toList(),
              'i': simulation.frames[index].impacts
                  .map(_impactJson)
                  .toList(growable: false),
            },
        ],
      },
  ];
  final encoded = jsonEncode(payload).replaceAll('</', '<\\/');
  return '''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Open Vibrance membrane lab</title><style>
:root{color-scheme:dark;font:14px/1.45 "Segoe UI",sans-serif;background:#07060a;color:#e9e4ec}*{box-sizing:border-box}body{margin:0;padding:24px;background:radial-gradient(circle at 50% 20%,#21101c,#07060a 65%)}main{max-width:1000px;margin:auto}.panel{background:#100d13;border:1px solid #2d2630;border-radius:16px;padding:16px;box-shadow:0 18px 60px #0008}h1{font-size:20px;margin:0 0 14px}.controls{display:grid;grid-template-columns:auto auto 1fr auto;gap:10px;align-items:center}button,select{background:#211a23;color:#fff;border:1px solid #433746;border-radius:8px;padding:8px 12px}button{cursor:pointer}input[type=range]{width:100%}canvas{width:100%;height:auto;display:block;margin-top:14px;border-radius:12px;background:#050408}.meta{display:flex;justify-content:space-between;color:#a79da9;margin-top:8px}.legend{display:flex;gap:18px}.old{color:#a9a1aa}.new{color:#ff9bc4}@media(max-width:650px){body{padding:10px}.controls{grid-template-columns:auto 1fr}.controls input{grid-column:1/-1}}
</style></head><body><main><div class="panel"><h1>Real-recording membrane A/B replay</h1><div class="controls"><select id="recording" aria-label="Recording"></select><button id="play">Play</button><input id="scrub" type="range" min="0" max="1" step="0.0001" value="0" aria-label="Timeline"><span id="time">0.00s</span></div><canvas id="view" width="960" height="430"></canvas><div class="meta"><div class="legend"><span class="old">OLD · fixed spectral silhouette</span><span class="new">NEW · temporal membrane + field</span></div><span id="metrics"></span></div></div></main>
<script>const DATA=$encoded;const select=document.querySelector('#recording'),play=document.querySelector('#play'),scrub=document.querySelector('#scrub'),time=document.querySelector('#time'),metrics=document.querySelector('#metrics'),canvas=document.querySelector('#view'),ctx=canvas.getContext('2d');let record=0,pos=0,running=false,last=0;DATA.forEach((r,i)=>{const o=document.createElement('option');o.value=i;o.textContent=r.name;select.append(o)});function path(radii,cx,cy,scale){ctx.beginPath();radii.forEach((r,i)=>{const a=-Math.PI/2+i*Math.PI*2/radii.length,x=cx+Math.cos(a)*r*scale,y=cy+Math.sin(a)*r*scale;i?ctx.lineTo(x,y):ctx.moveTo(x,y)});ctx.closePath()}function orb(frame,cx,label,candidate){const r=candidate?frame.c:frame.b,scale=9;ctx.save();if(candidate){for(let h=4;h>=1;h--){const prior=DATA[record].frames[Math.max(0,Math.floor(pos)-h*2)];path(prior.c,cx,205,scale*(1-h*.035));ctx.strokeStyle='rgba(255,72,145,'+(.09*(5-h))+')';ctx.lineWidth=1.2;ctx.stroke()}path(r,cx,205,scale);ctx.shadowColor='#ff4f9a';ctx.shadowBlur=18*(.35+frame.l);const g=ctx.createRadialGradient(cx-18*Math.cos(frame.p),185-18*Math.sin(frame.p),8,cx,205,125);g.addColorStop(0,'#3f0719');g.addColorStop(.68,'#bd1742');g.addColorStop(1,'#ff5f78');ctx.fillStyle=g;ctx.fill();ctx.shadowBlur=0;const edge=ctx.createLinearGradient(cx-120,100,cx+120,310);edge.addColorStop(0,'#ffb38d');edge.addColorStop(.48,'#fff3fb');edge.addColorStop(1,'#ff62cf');ctx.strokeStyle=edge;ctx.lineWidth=3;ctx.stroke()}else{path(r,cx,205,scale);ctx.fillStyle='#c91c3f';ctx.fill();ctx.strokeStyle='#fff';ctx.lineWidth=3;ctx.stroke()}ctx.fillStyle=candidate?'#ff9bc4':'#aaa2ab';ctx.font='600 14px Segoe UI';ctx.textAlign='center';ctx.fillText(label,cx,370);ctx.restore()}function draw(){const rec=DATA[record],i=Math.min(rec.frames.length-1,Math.max(0,Math.floor(pos))),f=rec.frames[i];ctx.clearRect(0,0,canvas.width,canvas.height);const bg=ctx.createRadialGradient(480,210,10,480,210,520);bg.addColorStop(0,'#180d17');bg.addColorStop(1,'#050408');ctx.fillStyle=bg;ctx.fillRect(0,0,canvas.width,canvas.height);orb(f,270,'OLD',false);orb(f,690,'NEW',true);scrub.value=rec.frames.length>1?i/(rec.frames.length-1):0;time.textContent=f.t.toFixed(2)+'s';metrics.textContent='level '+f.l.toFixed(2)+' · flux '+f.f.toFixed(2)+' · novelty '+f.n.toFixed(3)+' · impacts '+f.i.length;}function tick(now){if(!running)return;if(!last)last=now;pos+=(now-last)/1000*30;last=now;const frames=DATA[record].frames;if(pos>=frames.length-1){pos=frames.length-1;running=false;play.textContent='Play'}draw();if(running)requestAnimationFrame(tick)}play.onclick=()=>{if(running){running=false;play.textContent='Play';return}if(pos>=DATA[record].frames.length-1)pos=0;running=true;last=0;play.textContent='Pause';requestAnimationFrame(tick)};scrub.oninput=()=>{pos=Number(scrub.value)*(DATA[record].frames.length-1);draw()};select.onchange=()=>{record=Number(select.value);pos=0;running=false;play.textContent='Play';draw()};draw();</script></body></html>''';
}

double _rounded(double value) => double.parse(value.toStringAsFixed(4));

String _stem(String path) {
  final name = path.split(RegExp(r'[/\\]')).last;
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

double _range(List<double> values) =>
    values.reduce(math.max) - values.reduce(math.min);

double _mean(List<double> values) =>
    values.fold<double>(0, (sum, value) => sum + value) / values.length;

double _quantile(List<double> values, double quantile) {
  final sorted = List<double>.of(values)..sort();
  final position = (sorted.length - 1) * quantile;
  final low = position.floor();
  final high = position.ceil();
  if (low == high) return sorted[low];
  return sorted[low] + (sorted[high] - sorted[low]) * (position - low);
}

double _rmsDifference(List<double> first, List<double> second) {
  var sum = 0.0;
  for (var index = 0; index < first.length; index++) {
    final difference = first[index] - second[index];
    sum += difference * difference;
  }
  return math.sqrt(sum / first.length);
}

double _maxDifference(List<double> first, List<double> second) {
  var maximum = 0.0;
  for (var index = 0; index < first.length; index++) {
    maximum = math.max(maximum, (first[index] - second[index]).abs());
  }
  return maximum;
}

double _dot(List<double> first, List<double> second) {
  var dot = 0.0;
  for (var index = 0; index < first.length; index++) {
    dot += first[index] * second[index];
  }
  return dot;
}

List<double> _normalizedShape(List<double> radii) {
  final mean = _mean(radii);
  final centered = radii.map((radius) => radius - mean).toList(growable: false);
  final norm = math.sqrt(
    centered.fold<double>(0, (sum, value) => sum + value * value),
  );
  if (norm < 1e-12) return List<double>.filled(radii.length, 0);
  return centered.map((value) => value / norm).toList(growable: false);
}

double _shapeDistance(List<double> first, List<double> second) {
  var sum = 0.0;
  for (var index = 0; index < first.length; index++) {
    final difference = first[index] - second[index];
    sum += difference * difference;
  }
  return math.sqrt(sum);
}

double _orientation(List<double> radii) {
  final mean = _mean(radii);
  var x = 0.0;
  var y = 0.0;
  for (var sample = 0; sample < radii.length; sample++) {
    final weight = math.max(0, radii[sample] - mean);
    final angle = -math.pi / 2 + sample * 2 * math.pi / radii.length;
    x += weight * math.cos(angle);
    y += weight * math.sin(angle);
  }
  return math.atan2(y, x);
}

int _prominentPeakCount(List<double> values) {
  final threshold = math.max(0.08 * _range(values), 0.15);
  var count = 0;
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
    if (current - math.max(leftValley, rightValley) >= threshold) count++;
  }
  return count;
}

double _highModeShare(List<double> coefficients) {
  var total = 0.0;
  var high = 0.0;
  for (var mode = 1; mode <= RecordingMembraneModel.modeCount; mode++) {
    final magnitude = math.sqrt(
      math.pow(coefficients[RecordingMembraneModel.cosineIndex(mode)], 2) +
          math.pow(coefficients[RecordingMembraneModel.sineIndex(mode)], 2),
    );
    total += magnitude;
    if (mode >= 4) high += magnitude;
  }
  return total > 1e-12 ? high / total : 0;
}

double _correlation(List<double> first, List<double> second) {
  if (first.length != second.length || first.isEmpty) return 0;
  final firstMean = _mean(first);
  final secondMean = _mean(second);
  var covariance = 0.0;
  var firstVariance = 0.0;
  var secondVariance = 0.0;
  for (var index = 0; index < first.length; index++) {
    final firstDelta = first[index] - firstMean;
    final secondDelta = second[index] - secondMean;
    covariance += firstDelta * secondDelta;
    firstVariance += firstDelta * firstDelta;
    secondVariance += secondDelta * secondDelta;
  }
  final denominator = math.sqrt(firstVariance * secondVariance);
  return denominator > 1e-12 ? covariance / denominator : 0;
}
