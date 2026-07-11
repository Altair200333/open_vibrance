# Audio Spectrum Visualizer

Status: Implemented and verified. The FFT pipeline and Fourier-membrane renderer are current; radial rays and fixed lobes are retained only as rejected design history.

Last updated: 2026-07-11

## Goal

Provide immediate, attractive voice feedback while recording without changing the audio delivered to transcription providers or the WAV saved in history.

The visualizer has two independent parts:

1. A reusable PCM spectrum analyzer. This part is implemented and should be preserved.
2. A recording-state renderer. The implemented signed Fourier membrane replaces the rejected radial-rays and fixed-lobe prototypes.

## Current data flow

```text
Microphone PCM16 LE, mono, 16 kHz
  -> AudioService raw stream listener
     -> append the original chunk to the WAV buffer
     -> enqueue the same original chunk for realtime transcription
     -> best-effort FFT analysis after forwarding
        -> immutable AudioSpectrumFrame
        -> DotIndicator -> RecordingDot -> RecordingMembranePainter
```

Batch recording does not expose raw PCM to the app and therefore uses the scalar amplitude fallback. The true spectrum is currently available on the ElevenLabs realtime path.

## Safety invariants

The visualizer is an observer and must never become part of audio finalization.

1. `_pcmBuffer.add(chunk)` and `controller.add(chunk)` happen before spectrum analysis.
2. The original chunk is never mutated, split, coalesced, or replaced.
3. The downstream controller stays single-subscription and non-broadcast so early PCM is buffered until the transcription provider attaches its listener.
4. Analyzer errors disable only the spectrum and restore scalar amplitude fallback.
5. Analyzer errors never set `_pcmStreamError`, add an error to the transcription stream, cancel the recorder, or affect the WAV.
6. The delayed-tail barrier is unchanged: recorder stop -> final PCM events -> raw `onDone` queues downstream close/done and completes the drain barrier -> WAV build; transcript finality is awaited separately.
7. Analyzer state is reset on start, normal stop after drain, force reset, raw failure cleanup, and disposal.
8. A trailing byte from an odd PCM chunk is carried only inside the analyzer. Forwarded audio chunks remain byte-identical.

These rules are enforced primarily in `lib/services/audio_service.dart` and by `test/services/audio_service_test.dart`.

## Spectrum analyzer

Implementation: `lib/services/audio_spectrum_analyzer.dart`

Dependency: [`fftea`](https://pub.dev/packages/fftea) `1.5.0+1`.

### Input and STFT

| Parameter | Value |
|---|---:|
| PCM encoding | signed 16-bit little-endian |
| Channels | mono |
| Sample rate | 16,000 Hz |
| FFT frame | 512 samples / 32 ms |
| Window | symmetric Hann |
| Hop | 256 samples / 16 ms |
| UI publication | every second hop / 31.25 FPS |

The analyzer preserves an odd trailing byte between arbitrary input chunks and creates a new `STFT` object on reset instead of flushing a zero-padded fake frame.

### Frequency bands

- 12 logarithmic bands.
- Range: 80 Hz to 7,600 Hz.
- One-sided FFT power normalization: `4 / sum(Hann)^2`.
- Power is averaged across bins in each band so wider high-frequency bands do not win only because they contain more FFT bins.
- Band dB is calculated with `10 * log10(meanPower)`.

### Normalization and motion

| Parameter | Value |
|---|---:|
| Silence gate | -62 dB |
| Band floor | -78 dB |
| Band ceiling | -18 dB |
| Band response exponent | 0.68 |
| Activity response exponent | 0.58 |
| Band attack | 25 ms |
| Band release | 220 ms at low bands -> 140 ms at high bands |
| Overall level release | 180 ms |
| Flux release | 100 ms |
| Snap-to-zero threshold | 0.015 |

`AudioSpectrumFrame` contains:

- exactly 12 normalized immutable band values;
- normalized overall level;
- normalized positive spectral flux for short transients;
- source activity in dB;
- a frame sequence that increases monotonically within one analyzer capture/reset generation.

An empty band list means that a real spectrum is unavailable and the UI must use the scalar fallback.

## Rendering constraints

- Native recording window: 100 x 30 logical pixels.
- Existing indicator hit region: 50 x 30.
- Visualizer canvas: 30 x 30, centered in the existing hit region.
- No visual paint may cross the native 30-pixel window height.
- The visual layer does not participate in hit testing.
- Window geometry, click-through behavior, and hotkey recording lifecycle must remain unchanged.

## Rejected prototype: mirrored radial rays

The first renderer used:

- a separate red circular core with a white border;
- 24 thin rays made from 12 mirrored spectrum bands;
- bounded radial halo driven by level and spectral flux;
- a maximum painted radius of 14.2 px;
- 32 ms interpolation between real spectrum frames and 45/140 ms scalar fallback interpolation.

The prototype validated FFT band propagation, animation continuity, clipping bounds, and pointer behavior. It was rejected visually because the thin rays read as a subtle "hairy hedgehog" around an otherwise independent circle. At the real 30 x 30 size, the spectrum was too easy to miss and the white circular outline did not participate in the deformation. No radial-ray production code remains.

The FFT pipeline was preserved; only the recording renderer was replaced.

## Rejected prototype: fixed eight-lobe blob

The second renderer joined the red fill and white outline into one contour, which solved the separate "hairy core" problem. It reduced 12 bands to eight fixed 45-degree sectors, combined them with a hard local maximum, and linearly retargeted the complete shape every 32 ms.

It was rejected because equal energy mathematically produced a regular eight-petal flower. The hard winner changed at sector boundaries, while restarting a linear tween preserved position but not velocity. Live speech therefore produced micro-jerks, mostly outward deformation, and a residual impression of whole-body scale. The one-path paint and 96-sample contour were preserved; the fixed sectors, hard maximum, and restarted tween were removed.

## Fourier membrane renderer

The current visual is one continuous audio-reactive object. Its fill, luminous
rim, glow, and delayed internal sheets all use the same 96-point Fourier
contour. There are no separate rays, bars, fixed petals, procedural rotation,
or random movement. At silence every AC coefficient returns to zero and the
object becomes a clean small circle.

### Contour algorithm

Use a positive periodic radial function sampled at 96 monotonically increasing angles. Build a closed `Path` with `lineTo` and a round stroke join. At this size, 96 antialiased edges appear smooth and cannot overshoot like cubic control points can.

The old stateless mapping is retained in `RecordingMembraneModel.coefficientsFor`
only as an exact offline A/B baseline and geometry fixture. Production uses one
`RecordingMembraneMapper` per recording widget. It removes the persistent voice
envelope before projecting the bands, so the same speaker does not pin the
membrane to one screen sector:

The exact, canonical implementation record—including paint passes, lifecycle,
history, all constants, and lab caveats—is
[`Градиентная амёба`](../notes/gradient_amoeba.md).

```text
energy[i] = clamp(band[i], 0, 1) ^ 0.90
absolute[i] = energy[i] - mean(energy)
novelty[i]  = (energy[i] - slowPrevious[i])
            - mean(energy - slowPrevious)

slow[i]  += (energy[i] - slow[i]) * (1 - exp(-dt / 0.52s))
shape[i]    = 0.30 * absolute[i] + 0.70 * 2.50 * novelty[i]
```

Both components are zero-mean. Equal broadband energy therefore remains a
circle, and a small smooth variance gate prevents floating-point or microphone
noise from being magnified. A new mapper seeds its slow envelope at 72% of the
first spectrum so recording onset is visible without producing a full-scale
cold-start spike.

Project only modes 1 through 5 of the real discrete Fourier transform:

```text
a[k] = 2/12 * sum(shape[i] * cos(k * angle[i]))
b[k] = 2/12 * sum(shape[i] * sin(k * angle[i]))
k = 1..5

modeWeight = [0.06, 0.72, 0.90, 0.92, 0.62]
```

Mode 1 is almost removed so the contour does not read as a translated circle.
Modes 2-5 create several broad folds; flux and high-band share add bounded 35%
and 55% transient boosts to modes 4 and 5. A degree-five periodic contour still
cannot turn into fine spectral hair.

The body radius and signed deformation remain independent. Importantly, the
new mapper does not normalize every non-zero frame to the full available reach:

```text
base = 6.0 + 2.0 * level ^ 1.15
rawBound = sum(hypot(a[k], b[k]))
gain = 42.0 * level ^ 0.56 * (0.82 + 0.30 * flux)
requestedReach = rawBound * gain

availableReach = min(12.8 - base, base - 3.2) - 0.3
actualReach = availableReach * tanh(requestedReach / availableReach)
```

The hyperbolic limiter is linear for small changes and compresses only near the
window boundary. Real phonetic strength therefore survives instead of every
frame becoming the same silhouette at a different scale. The conservative
harmonic bound and 0.3 px target inset preserve spring headroom. Rendering
repeats the bound as a shrink-only safety operation.

The precomputed 96 x 5 sine/cosine basis is itself the spatial low-pass filter. No post-hoc local maximum, narrow Gaussian, per-point clamp, or spatial moving average remains.

### Material and field rendering

The 30 x 30 production painter builds the outer path once and uses a compact
multi-pass material stack:

1. a low-alpha reactive outer glow;
2. a flat deep-red membrane surface—there is no radial body gradient;
3. at most two causal, off-center elliptical impact fronts, each made from a
   dark trailing trough and a chromatic crest clipped to the live body;
4. a restrained inner membrane rim and one faint delayed contour near 144 ms;
5. a final coral-to-magenta-to-white rim plus a continuous local highlight
   where an impact front reaches the boundary.

The widget retains seven immutable coefficient snapshots sampled every 48 ms.
The painter now uses only the state near 144 ms, scales and insets it toward the
center, clips it to the current body, and draws it at very low opacity. This is
an actual prior audio state, not procedural mesh noise. A resume gap above
250 ms clears stale history.

Impact creation is separate from rendering. A pure-Dart Schmitt/refractory
controller observes only new spectrum targets and emits deterministic immutable
snapshots from flux, temporal novelty, and Fourier-target delta. Vsync only
ages those snapshots for 550 ms; it cannot inject new energy. There is no
random source or autonomous animation. The speech-tuned Schmitt gate uses
trigger/rearm `0.30/0.24` with a 120 ms refractory interval and a 0.40 minimum
impact strength; three fresh speech WAVs measured 0.98-1.50 impacts/s instead
of the previous 0.45-0.77 impacts/s.

### Scalar fallback

When no real spectrum exists, all AC coefficients target zero and the common base formula renders a uniformly breathing circle. No fake asymmetry is invented when frequency information is unavailable.

### Temporal behavior

The analyzer envelopes remain unchanged:

- per-band 25 ms attack and 140-220 ms release;
- spectrum targets published every 32 ms.

The UI no longer starts a new 32 ms tween for every target. It stores Cartesian position and velocity for the DC plus ten sine/cosine coefficients and advances them on one vsynced `Ticker`. Retargeting replaces only target coefficients; current position, velocity, and ticker time remain untouched.

Each coefficient uses the exact solution of a damped second-order spring. Starting parameters:

| State | Angular frequency | Damping ratio |
|---|---:|---:|
| DC/body radius | 22 s^-1 | 1.00 |
| modes 1-3 | 22 s^-1 | 1.00 |
| modes 4-5 | 22 s^-1 | 1.00 |

The exact spring integrates real elapsed time up to 250 ms, so an ordinary long frame does not slow the visual clock. A larger background/resume gap snaps to the newest target instead of replaying stale motion. Once every coefficient is within 0.002 px of target and every velocity is below 0.02 px/s, state snaps exactly to target and the ticker stops. Silence therefore has no perpetual animation or repaint cost.

Spectrum/fallback switches are continuous because only targets change; the current contour cannot jump on retarget. Identical audio targets and identical elapsed-time sequences produce identical motion. No procedural rotation or random noise is used.

## Offline membrane lab

`tool/membrane_lab.dart` runs the production analyzer, mapper, Fourier geometry,
and analytic spring against saved PCM16 mono 16 kHz WAV recordings. It defaults
to the three longest compatible files in the app recordings directory:

```powershell
dart run tool\membrane_lab.dart
dart run tool\membrane_lab.dart --input "C:\path\to\recordings" --longest 3 --out build\membrane_lab
```

The lab compares the retained stateless baseline with the production candidate
at exact analyzer sample timestamps and a configurable 30-120 FPS render clock.
It writes:

- `summary.json` and `summary.md` with amplitude, motion, acceleration,
  adjacent-shape smoothness, angular coverage, peak, mode-share, and prototype
  similarity metrics;
- a standalone local `replay.html` that draws stored point arrays rather than
  reimplementing the model in JavaScript;
- per-recording `points.ndjson`, `trace.json`, and portable SVG contact sheets;
- `render_frames.json` plus a PNG contact sheet rendered by Flutter with the
  production painter;
- `impact_frames.json` plus an exact 8 x 3 Flutter-rendered grid covering low,
  medium, and high real impacts at eight ages each.

Personal recordings and generated lab outputs stay outside source control. The
lab is a repeatable tuning instrument, not a golden-image assertion: metrics
catch amplitude collapse, fixed silhouettes, jitter, and clipping, while the
replay/contact sheet remains the visual acceptance step.

## Implementation ownership

| File | Responsibility |
|---|---|
| `lib/services/audio_spectrum_analyzer.dart` | PCM decoding, STFT, band normalization, envelopes, flux |
| `lib/services/recording_membrane.dart` | Shared pure-Dart stateful mapper, legacy A/B baseline, Fourier geometry, analytic spring |
| `lib/services/recording_membrane_impact.dart` | Deterministic impact detector, immutable causal wave snapshots, lifetime/envelope math |
| `lib/services/audio_service.dart` | Observer-only analyzer integration, fallback, lifecycle isolation |
| `lib/widgets/dot_window.dart` | Pass immutable spectrum frame through the existing scoped rebuild |
| `lib/widgets/dot_indicator.dart` | Select real spectrum or scalar fallback for recording state |
| `lib/widgets/dot_indicator/recording_dot.dart` | Mapper ownership/sequence gating, ticker/history, and production material painter |
| `tool/membrane_lab.dart` | Real-WAV simulation, A/B metrics, point traces, replay, and contact sheets |

## Tests as executable specification

| Test file | Contract |
|---|---|
| `test/services/audio_service_test.dart` | chunk boundaries/order, delayed tail, pre-listener buffering, analyzer failure isolation, WAV parity, meter reset |
| `test/services/audio_spectrum_analyzer_test.dart` | silence, sine-to-band mapping, odd chunk equivalence, reset, immutable frames, exact decay to zero |
| `test/services/recording_membrane_test.dart` | temporal whitening, determinism/reset, diversity, bounds, exact silence settling |
| `test/dot_indicator_test.dart` | signed/bounded Fourier geometry, circle fallback, spring invariance, retarget continuity, settling |

The membrane test suite protects:

- 96 finite, positive, angle-ordered contour radii;
- center radii in 3.2-12.8 px, reserved spring headroom, and clipping to the native 30 px canvas;
- deterministic output for identical frames;
- uniform spectra remaining circular;
- near-flat spectra never being expanded into visible folds;
- deterministic mapper reset/replay and immutable returned targets;
- phonetic pulses reaching diverse angular sectors instead of one voice-locked silhouette;
- broad high-amplitude outward and inward folds on representative voice spectra;
- monotonic continuous movement of the dominant fold during an adjacent-band crossfade;
- spatial smoothness and the periodic seam;
- scalar fallback remaining a circle;
- retarget preserving position and velocity exactly;
- analytic spring equivalence at 30, 60, and 120 FPS;
- analytic equivalence for a 100 ms frame and safe snapping after a 300 ms resume gap;
- bounded intermediate spring overshoot under rapid signed retargets;
- bounded visual acceleration under a new target every 32 ms;
- spectrum/fallback transition continuity in both directions and during mid-flight retarget;
- exact zero-velocity settling in silence.

Manual visual QA now uses the offline lab on long real recordings, the stored-point
replay, and the exact Flutter PNG contact sheet. Synthetic silence, uniform
energy, single-band folds, and timed cross-band transitions remain unit fixtures.

## Recalibration triggers

Revisit fixed gate/range values only after observing real-device evidence:

- quiet microphones never open the visualizer;
- fan or tonal background keeps the membrane deformed;
- high-frequency speech is consistently weaker because wide logarithmic bands average more bins;
- synchronous FFT processing exceeds 2 ms per raw chunk in a Release profile.

Do not add adaptive noise estimation, AGC, or an isolate before one of these conditions is measured.
