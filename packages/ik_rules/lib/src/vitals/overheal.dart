import 'dart:math' as math;

import '../js_compat.dart';
import '../tags.dart';

/// Extra HP above max from one overheal source.
/// Ratio is a fraction of max (0.05 = 5%). Sources do not add together;
/// whichever ceiling is higher at apply time wins, and a lower source never
/// cuts surplus that is already above its own ceiling.
num overhealCeilingHp(num maxHp, num overhealRatio) {
  final max = math.max(0, jsNumber(maxHp));
  final ratio = math.max(0, jsNumber(overhealRatio));
  return max + (max * ratio).floor();
}

/// Snap to a source's ceiling (blessing).
num snapToOverhealCeiling(num maxHp, num overhealRatio) => overhealCeilingHp(maxHp, overhealRatio);

/// Apply a heal (or damage) against one source's ceiling.
/// Existing surplus above that ceiling is left alone.
num healTowardCeiling(num currentHp, num maxHp, num amount, num overhealRatio) {
  final current = jsNumber(currentHp);
  if (amount < 0) return math.max(1, current + amount);
  final ceiling = overhealCeilingHp(maxHp, overhealRatio);
  if (current >= ceiling) return current;
  return math.min(ceiling, current + amount);
}

/// Largest `overheal_percent:N` tag on a capability string, as a ratio.
num parseOverhealRatio(Object? effects) {
  var best = 0.0;
  for (final tag in capabilityTags(effects)) {
    final match = RegExp(r'^overheal_percent:(\d+(?:\.\d+)?)$').firstMatch(tag);
    if (match != null) {
      best = math.max(best, jsNumber(match.group(1)) / 100);
    }
  }
  return best;
}
