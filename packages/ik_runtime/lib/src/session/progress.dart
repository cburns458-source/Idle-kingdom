import 'dart:math' as math;

import 'package:ik_rules/ik_rules.dart';

/// How far the timed action in progress has run, from 0 to 1.
///
/// Covers gathering actions and standard production crafts, which both time out
/// of `actionStartedAt` / `actionDurationMs`. Combat has no bar of its own here:
/// the combat panel animates its round from `combatRoundStartedAt`.
num actionProgressAt(PlayerSave save, num nowMs) {
  if (isNotBlank(save.combatEnemyId)) return 0;
  final state = restoreActiveActionState(save);
  if (state == null) return 0;
  final elapsed = nowMs - state.startedAtMs;
  return math.min(1, math.max(0, elapsed / math.max(1, state.durationMs)));
}
