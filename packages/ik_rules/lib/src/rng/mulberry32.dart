/// Signature every rule that needs randomness accepts, matching the
/// `RandomFn` type on the TypeScript side.
typedef RandomFn = double Function();

const int _uint32Mask = 0xFFFFFFFF;
const double _uint32Divisor = 4294967296.0;

/// Seeded PRNG that reproduces `mulberry32` from
/// [src/game/rng/mulberry32.ts](../../../../../src/game/rng/mulberry32.ts)
/// value for value, so recorded fixtures replay identically here.
class Mulberry32 {
  Mulberry32(int seed) : _state = seed & _uint32Mask;

  int _state;

  double next() {
    _state = (_state + 0x6D2B79F5) & _uint32Mask;
    var t = _state;
    t = _imul(t ^ (t >> 15), t | 1);
    t = (t ^ ((t + _imul(t ^ (t >> 7), t | 61)) & _uint32Mask)) & _uint32Mask;
    return ((t ^ (t >> 14)) & _uint32Mask) / _uint32Divisor;
  }

  RandomFn get asFunction => next;

  /// Draws [count] values, for replaying a recorded sequence.
  List<double> drawSequence(int count) => List<double>.generate(count, (_) => next());
}

/// 32-bit multiply matching JavaScript's `Math.imul`.
///
/// Split into 16-bit halves so intermediate products stay under 2^53 and the
/// result is identical on native and on Flutter Web, where a Dart `int` is a
/// JavaScript number.
int _imul(int a, int b) {
  final left = a & _uint32Mask;
  final right = b & _uint32Mask;
  final aHigh = (left >> 16) & 0xFFFF;
  final aLow = left & 0xFFFF;
  final bHigh = (right >> 16) & 0xFFFF;
  final bLow = right & 0xFFFF;
  final low = aLow * bLow;
  final cross = ((aHigh * bLow) + (aLow * bHigh)) & 0xFFFF;
  return (low + (cross << 16)) & _uint32Mask;
}
