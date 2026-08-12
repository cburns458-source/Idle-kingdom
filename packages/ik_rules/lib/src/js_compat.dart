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
