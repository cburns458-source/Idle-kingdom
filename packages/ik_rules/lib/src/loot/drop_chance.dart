import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../js_compat.dart';
import '../save/generated/save_models.dart';
import '../tags.dart';

final RegExp _relativeDropChanceTag = RegExp(r'^\+(\d+(?:\.\d+)?)%\s+relative\s+drop\s+chance$');

/// Sums every `+N% relative Drop Chance` tag in a capability string.
num parseRelativeDropChanceBonusPercent(Object? effects) {
  num total = 0;
  for (final tag in capabilityTags(effects)) {
    final match = _relativeDropChanceTag.firstMatch(tag);
    if (match != null) total += jsNumber(match.group(1));
  }
  return total;
}

/// Equipped gear bonuses (Lucky Necklace, future luck items). Same bonus types add.
num equippedRelativeDropChanceBonusPercent(GameDatabase db, PlayerSave save) {
  num total = 0;
  for (final stack in save.equipment.slots.values) {
    if (stack == null || isBlank(stack.itemId)) continue;
    final equipment = db.equipment.firstWhereOrNull((row) => row.raw['Item ID'] == stack.itemId);
    total += parseRelativeDropChanceBonusPercent(equipment?.raw['Capabilities / Effects']);
  }
  return total;
}

/// Total relative drop-chance bonus from all sources (gear + active luck potion).
/// Same bonus types stack by addition.
num totalRelativeDropChanceBonusPercent(GameDatabase db, PlayerSave save) {
  var total = equippedRelativeDropChanceBonusPercent(db, save);
  final potion = save.activePotionEffect;
  if (potion?.scope == 'one_action') {
    total += potion?.relativeDropChanceBonusPercent ?? 0;
  }
  return total;
}

/// Applies a summed relative drop-chance bonus: base × (1 + bonus/100), capped at 100.
num? applyRelativeDropChance(num? baseChance, num relativeBonusPercent) {
  if (baseChance == null) return null;
  if (relativeBonusPercent == 0 || relativeBonusPercent.isNaN) return baseChance;
  return math.min(100, baseChance * (1 + relativeBonusPercent / 100));
}
