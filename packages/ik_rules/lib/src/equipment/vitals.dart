import 'dart:math' as math;

import 'package:ik_content/ik_content.dart';

import '../combat/stats.dart';
import '../save/generated/save_models.dart';

/// Keep blessing surplus as an absolute extra when max HP changes.
num currentHpAfterMaxChange(num currentHp, num previousMaxHp, num nextMaxHp) {
  final surplus = math.max(0, currentHp - previousMaxHp);
  if (surplus > 0) return nextMaxHp + surplus;
  return math.min(math.max(0, currentHp), nextMaxHp);
}

/// Recalculates max HP from gear and keeps any blessing surplus.
PlayerSave withRecalculatedVitals(GameDatabase db, PlayerSave save) {
  final maxHp = playerMaxHp(db, save);
  return save.copyWith(
    maxHp: maxHp,
    currentHp: currentHpAfterMaxChange(save.currentHp, save.maxHp, maxHp),
  );
}
