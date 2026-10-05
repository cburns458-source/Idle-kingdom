import 'dart:math' as math;

import 'package:ik_content/ik_content.dart';

import '../combat/stats.dart';
import '../js_compat.dart';
import '../save/generated/save_models.dart';
import '../time.dart';

/// Seconds without damage before natural regen can start (or resume).
const num naturalHpRegenIdleSeconds = 60;

/// Base heal each regen trigger: 1% of max HP. Doubles each streak step.
const num naturalHpRegenBasePercent = 1;

/// Interval between regen triggers once the idle gate has passed.
const num naturalHpRegenTriggerMs = 60000;

num naturalHpRegenIdleMs() => naturalHpRegenIdleSeconds * 1000;

/// Heal amount for streak step [streak] (0 → 1% max, 1 → 2%, 2 → 4%, …).
num naturalHpRegenHealAmount(num maxHp, num streak) {
  final step = math.max(0, jsNumber(streak).floor());
  final percent = naturalHpRegenBasePercent * math.pow(2, step);
  return math.max(1, (maxHp * percent / 100).floor());
}

/// Stamp that the player took non-PvP damage. Resets the regen streak.
PlayerSave notePlayerDamaged(PlayerSave save, num nowMs) {
  return save.copyWith(lastDamagedAt: isoFromMs(nowMs), hpRegenStreak: 0);
}

class NaturalHpRegenResult {
  const NaturalHpRegenResult({required this.save, required this.remainderMs});

  final PlayerSave save;
  final num remainderMs;
}

/// Natural HP regen after 60s without damage; 1% max HP/min doubling per streak.
NaturalHpRegenResult applyNaturalHpRegen(
  GameDatabase db,
  PlayerSave save,
  num elapsedMs, [
  num? nowMs,
]) {
  if (!elapsedMs.isFinite || elapsedMs <= 0) {
    return NaturalHpRegenResult(save: save, remainderMs: 0);
  }
  final clock = nowMs ?? 0;
  final maxHp = playerMaxHp(db, save);
  // Blessing may sit above max. Regen fills up to max and never cuts surplus.
  if (save.currentHp >= maxHp) {
    if (save.hpRegenStreak == 0) {
      return NaturalHpRegenResult(save: save, remainderMs: 0);
    }
    return NaturalHpRegenResult(save: save.copyWith(hpRegenStreak: 0), remainderMs: 0);
  }

  final idleMs = naturalHpRegenIdleMs();
  final lastDamagedMs = isBlank(save.lastDamagedAt)
      ? double.negativeInfinity
      : jsDateParse(save.lastDamagedAt!);
  final gateEndMs = lastDamagedMs.isFinite ? lastDamagedMs + idleMs : double.negativeInfinity;
  final windowStartMs = clock - elapsedMs;
  final eligibleStartMs = math.max(windowStartMs, gateEndMs);
  final eligibleMs = math.max(0, clock - eligibleStartMs);
  if (eligibleMs <= 0) {
    return NaturalHpRegenResult(save: save, remainderMs: 0);
  }

  final interval = naturalHpRegenTriggerMs;
  final triggers = (eligibleMs / interval).floor();
  final remainder = eligibleMs - triggers * interval;
  if (triggers <= 0) {
    return NaturalHpRegenResult(save: save, remainderMs: remainder);
  }

  var hp = save.currentHp;
  var streak = math.max(0, jsNumber(save.hpRegenStreak).floor());
  for (var i = 0; i < triggers; i += 1) {
    if (hp >= maxHp) break;
    final heal = naturalHpRegenHealAmount(maxHp, streak);
    hp = math.min(maxHp, hp + heal);
    streak += 1;
  }
  if (hp >= maxHp) streak = 0;

  return NaturalHpRegenResult(
    save: save.copyWith(currentHp: hp, hpRegenStreak: streak),
    remainderMs: hp >= maxHp ? 0 : remainder,
  );
}
