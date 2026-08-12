import 'dart:math' as math;

import 'package:ik_content/ik_content.dart';

import '../combat/stats.dart';
import '../save/generated/save_models.dart';

/// Recalculates max HP from gear and clamps current HP.
PlayerSave withRecalculatedVitals(GameDatabase db, PlayerSave save) {
  final maxHp = playerMaxHp(db, save);
  return save.copyWith(maxHp: maxHp, currentHp: math.min(math.max(0, save.currentHp), maxHp));
}
