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

/// `String(row?.[column])` for a database value interpolated into a template.
///
/// JavaScript prints `undefined` for a column the row never had and `null` for
/// one present but empty, and player-facing strings show the difference, so the
/// two cases stay distinct here instead of collapsing into one.
String jsRawString(Map<String, Object?>? raw, String column) {
  if (raw == null || !raw.containsKey(column)) return 'undefined';
  return jsString(raw[column]);
}

/// `(value ?? '').toLowerCase()` for optional string columns.
String lowerOrEmpty(Object? value) => value is String ? value.toLowerCase() : '';

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

/// `Number(value) || 0`, which the rules use to coerce optional numbers.
num jsNumberOrZero(Object? value) {
  final number = jsNumber(value);
  return number.isNaN || number == 0 ? 0 : number;
}

/// `a - b || tieBreak()`, the comparator shape the sorted lookups use.
///
/// JavaScript treats both `0` and `NaN` as falsy, so a missing sort order falls
/// through to the tie-break instead of ordering by whichever row came first.
int jsCompareThen(num delta, int Function() tieBreak) {
  if (delta == 0 || delta.isNaN) return tieBreak();
  return delta > 0 ? 1 : -1;
}

const int _uint32Mask = 0xFFFFFFFF;

/// `Math.imul(a, b)`, returned unsigned as the hashes here always mask with `>>> 0`.
///
/// Split into 16-bit halves so intermediate products stay under 2^53 and the
/// result is identical on native and on Flutter Web, where a Dart `int` is a
/// JavaScript number.
int jsImul(int a, int b) {
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

/// `Number.prototype.toLocaleString()` for the en-US default the UI strings use.
///
/// Grouping every three digits with commas and rounding to at most three
/// fraction digits is what the default formatter does for the plain counts the
/// rules put in player-facing text.
String jsLocaleNumber(num value) {
  if (value.isNaN) return 'NaN';
  if (value.isInfinite) return value.isNegative ? '-∞' : '∞';
  final rounded = (value * 1000).round() / 1000;
  final sign = rounded < 0 ? '-' : '';
  final magnitude = rounded.abs();
  final whole = magnitude.floor();
  final fraction = jsNumberToString(magnitude - whole);
  final digits = whole.toString();
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i += 1) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
    grouped.write(digits[i]);
  }
  // `fraction` renders as `0` or `0.xyz`; only the decimals after it matter.
  return '$sign$grouped${fraction == '0' ? '' : fraction.substring(1)}';
}

/// `String.prototype.localeCompare` for the ASCII text the database holds.
///
/// The default collation compares base letters first and only falls back to
/// case, where lowercase sorts before uppercase. Dart's [String.compareTo] is
/// code-unit ordering instead, which would put `Zebra` before `apple`, so every
/// comparison that feeds a sort order goes through here.
int jsLocaleCompare(String a, String b) {
  final primary = a.toLowerCase().compareTo(b.toLowerCase());
  if (primary != 0) return primary < 0 ? -1 : 1;
  if (a == b) return 0;
  for (var i = 0; i < a.length && i < b.length; i += 1) {
    final left = a[i];
    final right = b[i];
    if (left == right) continue;
    final leftIsLower = left.toUpperCase() != left;
    final rightIsLower = right.toUpperCase() != right;
    if (leftIsLower != rightIsLower) return leftIsLower ? -1 : 1;
  }
  return a.length == b.length ? 0 : (a.length < b.length ? -1 : 1);
}
