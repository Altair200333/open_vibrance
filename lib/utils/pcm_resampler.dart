import 'dart:typed_data';

/// Returns a 16-bit mono PCM WAV resampled down to [toRate]. Anything else
/// (other formats, stereo, already at or below [toRate], malformed header)
/// comes back unchanged, so callers can always pass the original bytes.
Uint8List downsampleWav(Uint8List wav, {int toRate = 16000}) {
  if (wav.length < 12) return wav;
  final data = ByteData.sublistView(wav);
  String tag(int at) => String.fromCharCodes(wav.sublist(at, at + 4));
  if (tag(0) != 'RIFF' || tag(8) != 'WAVE') return wav;

  int? rate;
  var pcm16Mono = false;
  var offset = 12;
  while (offset + 8 <= wav.length) {
    final id = tag(offset);
    final size = data.getUint32(offset + 4, Endian.little);
    final body = offset + 8;
    if (id == 'fmt ' && size >= 16 && body + 16 <= wav.length) {
      pcm16Mono =
          data.getUint16(body, Endian.little) == 1 &&
          data.getUint16(body + 2, Endian.little) == 1 &&
          data.getUint16(body + 14, Endian.little) == 16;
      rate = data.getUint32(body + 4, Endian.little);
    } else if (id == 'data') {
      if (!pcm16Mono || rate == null || rate <= toRate) return wav;
      final end = (body + size).clamp(body, wav.length);
      final pcm = Pcm16Resampler(
        fromRate: rate,
        toRate: toRate,
      ).convert(Uint8List.sublistView(wav, body, end));
      return _pcm16MonoWav(pcm, toRate);
    }
    offset = body + size + (size.isOdd ? 1 : 0);
  }
  return wav;
}

Uint8List _pcm16MonoWav(Uint8List pcm, int rate) {
  final header = ByteData(44);
  void tag(int at, String s) {
    for (var i = 0; i < 4; i++) {
      header.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  header.setUint32(4, 36 + pcm.length, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little); // PCM
  header.setUint16(22, 1, Endian.little); // mono
  header.setUint32(24, rate, Endian.little);
  header.setUint32(28, rate * 2, Endian.little); // byte rate
  header.setUint16(32, 2, Endian.little); // block align
  header.setUint16(34, 16, Endian.little); // bits per sample
  tag(36, 'data');
  header.setUint32(40, pcm.length, Endian.little);
  return (BytesBuilder(copy: false)
        ..add(header.buffer.asUint8List())
        ..add(pcm))
      .toBytes();
}

/// Streaming linear resampler for mono little-endian PCM16.
///
/// Keeps state across chunks (last sample, fractional read position, a
/// dangling odd byte), so feeding a recording chunk by chunk produces the
/// same audio as resampling it in one piece. Used to give each live
/// Composite slot its own sample rate from a single microphone stream.
class Pcm16Resampler {
  final int fromRate;
  final int toRate;
  final double _step;

  /// Read position of the next output sample, relative to [_prev] at index 0
  /// (or to the first sample of the chunk while [_prev] is null).
  double _pos = 0;
  int? _prev;
  int? _oddByte;

  Pcm16Resampler({required this.fromRate, required this.toRate})
    : assert(fromRate > 0 && toRate > 0),
      _step = fromRate / toRate;

  Uint8List convert(Uint8List chunk) {
    var bytes = chunk;
    if (_oddByte != null) {
      bytes =
          Uint8List(chunk.length + 1)
            ..[0] = _oddByte!
            ..setRange(1, chunk.length + 1, chunk);
      _oddByte = null;
    }
    if (bytes.length.isOdd) {
      _oddByte = bytes.last;
      bytes = Uint8List.sublistView(bytes, 0, bytes.length - 1);
    }

    final input = ByteData.sublistView(bytes);
    final count = bytes.length ~/ 2;
    final offset = _prev == null ? 0 : 1;
    final total = count + offset;
    if (total == 0) return Uint8List(0);

    int sampleAt(int i) =>
        i < offset ? _prev! : input.getInt16((i - offset) * 2, Endian.little);

    final capacity = ((total - _pos) / _step).ceil() + 1;
    final out = ByteData(capacity < 0 ? 0 : capacity * 2);
    var written = 0;
    while (_pos < total - 1 && written < capacity) {
      final i = _pos.floor();
      final frac = _pos - i;
      final a = sampleAt(i);
      final value = a + (sampleAt(i + 1) - a) * frac;
      out.setInt16(
        written * 2,
        value.round().clamp(-32768, 32767),
        Endian.little,
      );
      written++;
      _pos += _step;
    }

    // The last sample becomes index 0 of the next chunk.
    _prev = sampleAt(total - 1);
    _pos -= total - 1;
    return Uint8List.sublistView(out, 0, written * 2);
  }
}
