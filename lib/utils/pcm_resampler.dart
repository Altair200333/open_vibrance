import 'dart:typed_data';

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
