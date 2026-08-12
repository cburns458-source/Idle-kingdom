import '../js_compat.dart';
import '../time.dart';
import 'catalog.dart';
import 'types.dart';

const int _uint32Mask = 0xFFFFFFFF;
const num _hourMs = 3600000;

/// UTC hour bucket, e.g. 2026-08-12T13
String bountyHourKey(num nowMs) {
  final date = DateTime.fromMillisecondsSinceEpoch(nowMs.toInt(), isUtc: true);
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  return '${date.year}-$month-${day}T$hour';
}

num bountyHourExpiresAtMs(String hourKey, num fallbackNowMs) {
  final parsed = jsDateParse('$hourKey:00:00.000Z');
  if (!parsed.isFinite) return fallbackNowMs + _hourMs;
  return parsed + _hourMs;
}

int _hashString(String input) {
  var hash = 2166136261;
  for (var i = 0; i < input.length; i += 1) {
    hash ^= input.codeUnitAt(i);
    hash = jsImul(hash, 16777619);
  }
  return hash & _uint32Mask;
}

/// Deterministic hourly sample from the bounty catalog.
HourlyBountyBoard hourlyBountyBoard(num nowMs) {
  final hourKey = bountyHourKey(nowMs);
  final pool = [...bountyCatalog];
  final selected = <BountyDefinition>[];
  var seed = _hashString(hourKey);
  while (selected.length < bountiesPerHour && pool.isNotEmpty) {
    seed = (jsImul(seed, 1664525) + 1013904223) & _uint32Mask;
    selected.add(pool.removeAt(seed % pool.length));
  }
  return HourlyBountyBoard(
    hourKey: hourKey,
    expiresAtMs: bountyHourExpiresAtMs(hourKey, nowMs),
    bounties: selected,
  );
}
