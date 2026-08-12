/// Clock conversions matching the JavaScript `Date` behaviour the rules rely on.
///
/// Saves store instants as ISO strings and rules compare them against a
/// millisecond `nowMs` parameter, so both directions of that conversion have to
/// agree with `Date.parse` / `Date.prototype.toISOString` exactly.
library;

/// `Date.parse(iso)`, including JavaScript's NaN for unparseable input.
///
/// NaN compares false against everything in Dart just as it does in JavaScript,
/// so callers can keep the `parse(x) > nowMs` shape of the original.
num jsDateParse(String? iso) {
  if (iso == null) return double.nan;
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return double.nan;
  return parsed.millisecondsSinceEpoch;
}

/// `new Date(ms).toISOString()`.
String isoFromMs(num ms) {
  return DateTime.fromMillisecondsSinceEpoch(ms.toInt(), isUtc: true).toIso8601String();
}
