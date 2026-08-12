import 'dart:convert';

/// Largest integer a JavaScript number represents exactly (2^53).
const int _jsSafeIntegerLimit = 9007199254740992;

/// Encodes [value] so that semantically equal TypeScript and Dart values
/// produce identical strings.
///
/// Object keys are sorted, and numbers are normalized: Dart draws a hard
/// int/double distinction that JavaScript does not, so `1` and `1.0` must
/// encode the same while `1` and `1.0000001` must not. Non-integral doubles use
/// the shortest round-trip form, which both languages produce identically.
///
/// Rules return infinity for "no limit" quantities, so non-finite numbers encode
/// as the quoted strings JSON has no literals for. A value that happens to be the
/// literal string `"Infinity"` encodes the same way on both sides, so the
/// ambiguity cannot make a mismatch look like a match.
String canonicalJson(Object? value) {
  final buffer = StringBuffer();
  _write(value, buffer, const <Object>[]);
  return buffer.toString();
}

/// True when the two values encode to the same canonical JSON.
bool canonicalEquals(Object? a, Object? b) => canonicalJson(a) == canonicalJson(b);

void _write(Object? value, StringBuffer out, List<Object> seen) {
  switch (value) {
    case null:
      out.write('null');
    case final bool b:
      out.write(b ? 'true' : 'false');
    case final num n:
      out.write(canonicalNumber(n));
    case final String s:
      out.write(jsonEncode(s));
    case final List<Object?> list:
      _guardCycle(list, seen);
      out.write('[');
      for (var i = 0; i < list.length; i++) {
        if (i > 0) out.write(',');
        _write(list[i], out, [...seen, list]);
      }
      out.write(']');
    case final Map<Object?, Object?> map:
      _guardCycle(map, seen);
      final keys = map.keys.map((key) {
        if (key is String) return key;
        throw ArgumentError('Canonical JSON requires String keys, got ${key.runtimeType}');
      }).toList()..sort();
      out.write('{');
      for (var i = 0; i < keys.length; i++) {
        if (i > 0) out.write(',');
        out.write(jsonEncode(keys[i]));
        out.write(':');
        _write(map[keys[i]], out, [...seen, map]);
      }
      out.write('}');
    default:
      throw ArgumentError('Cannot canonicalize ${value.runtimeType}');
  }
}

void _guardCycle(Object node, List<Object> seen) {
  for (final ancestor in seen) {
    if (identical(ancestor, node)) {
      throw ArgumentError('Cannot canonicalize a cyclic structure');
    }
  }
}

/// Normalizes a number the way `String(n)` does in JavaScript.
String canonicalNumber(num value) {
  if (value is int) return value.toString();
  final d = value as double;
  if (d.isNaN) return jsonEncode('NaN');
  if (d.isInfinite) return jsonEncode(d > 0 ? 'Infinity' : '-Infinity');
  if (d == d.roundToDouble() && d.abs() < _jsSafeIntegerLimit) {
    // Also collapses -0.0 to "0", matching String(-0) in JavaScript.
    return d.toInt().toString();
  }
  return d.toString();
}
