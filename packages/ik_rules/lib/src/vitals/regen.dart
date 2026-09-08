import 'dart:math' as math;

import 'package:ik_content/ik_content.dart';

import '../combat/stats.dart';
import '../js_compat.dart';
import '../save/generated/save_models.dart';

/// Out-of-combat natural recovery. Thievery and other non-combat work still regen.
const num naturalHpRegenPerMinute = 10;

num naturalHpRegenIntervalMs() => (60 * 1000) / naturalHpRegenPerMinute;

class NaturalHpRegenResult {
  const NaturalHpRegenResult({required this.save, required this.remainderMs});

  final PlayerSave save;
  final num remainderMs;
}

/// Grants whole HP for [elapsedMs] of non-combat time. Combat freezes regen.
NaturalHpRegenResult applyNaturalHpRegen(GameDatabase db, PlayerSave save, num elapsedMs) {
  if (isNotBlank(save.combatEnemyId)) {
    return NaturalHpRegenResult(save: save, remainderMs: 0);
  }
  if (!elapsedMs.isFinite || elapsedMs <= 0) {
    return NaturalHpRegenResult(save: save, remainderMs: 0);
  }
  final maxHp = playerMaxHp(db, save);
  if (save.currentHp >= maxHp) {
    return NaturalHpRegenResult(
      save: save.currentHp == maxHp ? save : save.copyWith(currentHp: maxHp),
      remainderMs: 0,
    );
  }
  final interval = naturalHpRegenIntervalMs();
  final gained = (elapsedMs / interval).floor();
  final remainder = elapsedMs - gained * interval;
  if (gained <= 0) {
    return NaturalHpRegenResult(save: save, remainderMs: remainder);
  }
  final nextHp = math.min(maxHp, save.currentHp + gained);
  return NaturalHpRegenResult(
    save: save.copyWith(currentHp: nextHp),
    remainderMs: nextHp >= maxHp ? 0 : remainder,
  );
}
