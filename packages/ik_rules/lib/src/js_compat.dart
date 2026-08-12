/// Helpers that reproduce JavaScript coercion rules the TypeScript rules rely on.
///
/// The TypeScript project does not enable `strict`, so values typed as `string`
/// or `number` can be null at runtime and comparisons lean on truthiness. Porting
/// those expressions literally into Dart would either crash or silently diverge,
/// so the coercions live here where they are named and testable.
library;

/// Largest integer a JavaScript number represents exactly (2^53).
const int _jsSafeIntegerLimit = 9007199254740992;

/// True when a string is falsy in JavaScript: null, undefined, or empty.
bool isBlank(String? value) => value == null || value.isEmpty;

/// True when a string is truthy in JavaScript.
bool isNotBlank(String? value) => !isBlank(value);

/// `String(value)` for the scalars the database holds.
///
/// Notably `String(5)` is `'5'`, not `'5.0'`, and null becomes the empty string
/// only because callers write `value ?? ''` first; here null maps to `'null'`
/// exactly as `String(null)` does.
String jsString(Object? value) {
  return switch (value) {
    null => 'null',
    final num n => jsNumberToString(n),
    final bool b => b ? 'true' : 'false',
    final String s => s,
    _ => value.toString(),
  };
}

/// `String(number)` in JavaScript, where there is no int/double distinction.
///
/// Mirrors `canonicalNumber` in `ik_parity`; the duplication is deliberate,
/// since the parity harness must not depend on the code it is checking.
String jsNumberToString(num value) {
  if (value is int) return value.toString();
  final d = value as double;
  if (d.isNaN) return 'NaN';
  if (d.isInfinite) return d.isNegative ? '-Infinity' : 'Infinity';
  if (d == d.roundToDouble() && d.abs() < _jsSafeIntegerLimit) {
    return d.toInt().toString();
  }
  return d.toString();
}

/// `Number.isInteger(value)`, which is true for `2.0` as well as `2`.
bool jsIsInteger(num value) => value.isFinite && value == value.roundToDouble();

/// `Number(value)`, including the NaN result for unparseable strings.
num jsNumber(Object? value) {
  return switch (value) {
    null => 0,
    final num n => n,
    final bool b => b ? 1 : 0,
    final String s => s.trim().isEmpty ? 0 : (num.tryParse(s.trim()) ?? double.nan),
    _ => double.nan,
  };
}
