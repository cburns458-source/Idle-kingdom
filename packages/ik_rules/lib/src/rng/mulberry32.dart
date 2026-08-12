import '../js_compat.dart';

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
    t = jsImul(t ^ (t >> 15), t | 1);
    t = (t ^ ((t + jsImul(t ^ (t >> 7), t | 61)) & _uint32Mask)) & _uint32Mask;
    return ((t ^ (t >> 14)) & _uint32Mask) / _uint32Divisor;
  }

  RandomFn get asFunction => next;

  /// Draws [count] values, for replaying a recorded sequence.
  List<double> drawSequence(int count) => List<double>.generate(count, (_) => next());
}
