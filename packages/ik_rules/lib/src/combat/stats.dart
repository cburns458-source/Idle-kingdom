import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../activity/xp.dart';
import '../config.dart';
import '../equipment/loadout.dart';
import '../js_compat.dart';
import '../npcs/knowledge.dart';
import '../projects/enchantments.dart';
import '../races/races.dart';
import '../rng/mulberry32.dart';
import '../save/generated/save_models.dart';
import '../spells/spells.dart';

const String combatSkillId = 'SKL-0001';

/// Combat Level bonuses begin at this level (inclusive).
const int combatLevelBonusStart = 10;

/// Each Combat Level grants this percent to max HP and damage range once the bonus is active.
const num combatLevelBonusPercentPerLevel = 1;

/// An inclusive damage range.
class DamageRange {
  const DamageRange({required this.min, required this.max});

  final num min;
  final num max;

  Map<String, Object?> toJson() => <String, Object?>{'min': min, 'max': max};
}

List<EquipmentRow> _equippedRows(GameDatabase db, PlayerSave save) {
  final rows = <EquipmentRow>[];
  for (final stack in save.equipment.slots.values) {
    if (stack == null || isBlank(stack.itemId)) continue;
    final row = db.equipment.firstWhereOrNull((entry) => entry.raw['Item ID'] == stack.itemId);
    if (row != null) rows.add(row);
  }
  return rows;
}

/// Multiplier from Combat Level.
///
/// Below level 10: none. Level 10+: +1% per Combat Level (level 10 → ×1.10).
num combatLevelBonusMultiplier(PlayerSave save) {
  final level = getSkillProgress(save, combatSkillId).level;
  if (level < combatLevelBonusStart) return 1;
  return 1 + (level * combatLevelBonusPercentPerLevel) / 100;
}

num _scaleStat(num value, num multiplier) => math.max(0, (value * multiplier).floor());

num _damageRangeMultipliers(GameDatabase db, PlayerSave save) {
  final levelMult = combatLevelBonusMultiplier(save);
  final spellMult = activeSpellDamageRangeMultiplier(db, save);
  final potion = save.activePotionEffect;
  final potionBonus = potion?.damageBonusPercent;
  final potionMult =
      potionBonus != null && potionBonus > 0 && potion?.scope == 'one_combat_encounter'
      ? 1 + potionBonus / 100
      : 1;
  return levelMult * spellMult * potionMult;
}

DamageRange _scaleDamageRange(num min, num max, num multiplier) {
  final scaledMin = _scaleStat(min, multiplier);
  return DamageRange(min: scaledMin, max: math.max(scaledMin, _scaleStat(max, multiplier)));
}

DamageRange _unarmedRange(GameDatabase db, num enchantBonus) {
  return DamageRange(
    min: configNumber(db, 'unarmed_min_damage', 10) + enchantBonus,
    max: configNumber(db, 'unarmed_max_damage', 30) + enchantBonus,
  );
}

num staffPowerMultiplier(GameDatabase db, PlayerSave save) {
  final weaponId = save.equipment.slots[weaponToolSlotId]?.itemId;
  if (isBlank(weaponId) || !itemHasCapability(db, weaponId!, 'staff_power')) return 1;
  return 1 + getSkillProgress(save, arcanaSkillId).level / 100;
}

/// Spark splat range from Arcana level only: ±10%, floored, never below 1.
DamageRange staffSparksDamageRange(num arcanaLevel) {
  final min = math.max(1, (arcanaLevel * 0.9).floor());
  final max = math.max(min, (arcanaLevel * 1.1).floor());
  return DamageRange(min: min, max: max);
}

DamageRange playerDamageRange(GameDatabase db, PlayerSave save) {
  final enchantBonus = equippedEnchantmentDamageBonus(db, save);
  final combined = _damageRangeMultipliers(db, save) * staffPowerMultiplier(db, save);
  final weaponId = save.equipment.slots[weaponToolSlotId]?.itemId;
  var base = _unarmedRange(db, enchantBonus);
  if (isNotBlank(weaponId)) {
    final weapon = db.equipment.firstWhereOrNull((entry) => entry.raw['Item ID'] == weaponId);
    final weaponMin = weapon?.raw['Min Damage'];
    final weaponMax = weapon?.raw['Max Damage'];
    if (weaponMin is num && weaponMax is num) {
      base = DamageRange(
        min: weaponMin + enchantBonus,
        max: math.max(weaponMin, weaponMax) + enchantBonus,
      );
    }
  }

  return _scaleDamageRange(base.min, base.max, combined);
}

/// Off-hand dagger damage range, or null when no dagger is equipped there.
///
/// Uses the same global enchant / spell / potion / race multipliers as main-hand.
DamageRange? playerOffhandDamageRange(GameDatabase db, PlayerSave save) {
  final offhandId = save.equipment.slots[offhandSlotId]?.itemId;
  if (isBlank(offhandId) || !isDaggerItem(db, offhandId!)) return null;
  final dagger = db.equipment.firstWhereOrNull((entry) => entry.raw['Item ID'] == offhandId);
  final daggerMin = dagger?.raw['Min Damage'];
  final daggerMax = dagger?.raw['Max Damage'];
  if (daggerMin is! num || daggerMax is! num) return null;

  final enchantBonus = equippedEnchantmentDamageBonus(db, save);
  return _scaleDamageRange(
    daggerMin + enchantBonus,
    math.max(daggerMin, daggerMax) + enchantBonus,
    _damageRangeMultipliers(db, save),
  );
}

num playerDamageReduction(GameDatabase db, PlayerSave save) {
  return _equippedRows(
    db,
    save,
  ).fold<num>(0, (sum, row) => sum + jsNumber(row.raw['Damage Reduction'] ?? 0));
}

num playerMaxHp(GameDatabase db, PlayerSave save) {
  final base = configNumber(db, 'starting_max_hp', 1000);
  final bonus = _equippedRows(
    db,
    save,
  ).fold<num>(0, (sum, row) => sum + jsNumber(row.raw['HP Bonus'] ?? 0));
  final levelMult = combatLevelBonusMultiplier(save);
  final raceMult = raceMaxHpMultiplier(db, save);
  return math.max(1, _scaleStat(base + bonus, levelMult * raceMult));
}

num rollDamage(num min, num max, RandomFn random) {
  final lo = math.min(min, max);
  final hi = math.max(min, max);
  return lo + (random() * (hi - lo + 1)).floor();
}

num applyMitigation(num rawDamage, num reduction, num damageFloor) {
  return math.max(damageFloor, rawDamage - math.max(0, reduction));
}
