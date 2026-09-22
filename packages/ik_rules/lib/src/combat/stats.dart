import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../activity/xp.dart';
import '../config.dart';
import '../equipment/loadout.dart';
import '../js_compat.dart';
import '../skills/skill_actions.dart';
import '../npcs/knowledge.dart';
import '../projects/enchantments.dart';
import '../races/races.dart';
import '../rng/mulberry32.dart';
import '../save/generated/save_models.dart';
import '../spells/spells.dart';

/// Might — weapons and damage scaling. Formerly Combat (`SKL-0001`).
const String mightSkillId = 'SKL-0001';

/// Vitality — armor/shields and max HP scaling.
const String vitalitySkillId = 'SKL-0016';

/// @deprecated Use [mightSkillId]. Kept for transitional call sites.
const String combatSkillId = mightSkillId;

/// Level bonuses (Might→damage, Vitality→HP) begin at this level (inclusive).
const int combatLevelBonusStart = 10;

/// Each contributing skill level grants this percent once the bonus is active.
const num combatLevelBonusPercentPerLevel = 1;

const List<String> attackStyles = <String>['offensive', 'defensive', 'balanced'];

String normalizeAttackStyle(Object? value) {
  if (value == 'offensive' || value == 'defensive' || value == 'balanced') {
    return value as String;
  }
  return 'offensive';
}

/// Combined Combat Level = ceil((Might + Vitality) × 0.75).
num combatLevelOf(PlayerSave save) {
  final might = getSkillProgress(save, mightSkillId).level;
  final vitality = getSkillProgress(save, vitalitySkillId).level;
  return ((might + vitality) * 0.75).ceil();
}

/// Multiplier from a single skill's level (Might or Vitality).
num skillLevelBonusMultiplier(num level) {
  if (level < combatLevelBonusStart) return 1;
  return 1 + (level * combatLevelBonusPercentPerLevel) / 100;
}

num mightDamageMultiplier(PlayerSave save) {
  return skillLevelBonusMultiplier(getSkillProgress(save, mightSkillId).level);
}

num vitalityHpMultiplier(PlayerSave save) {
  return skillLevelBonusMultiplier(getSkillProgress(save, vitalitySkillId).level);
}

/// Flat style damage bonus percent (0 for balanced).
num attackStyleDamageBonusPercent(String style) {
  if (style == 'offensive') return 1;
  return 0;
}

/// Flat style damage-reduction points (0 for balanced).
num attackStyleDamageReduction(String style) {
  if (style == 'defensive') return 1;
  return 0;
}

/// Split kill XP across Might / Vitality by attack style.
///
/// Balanced splits evenly; odd remainder goes to Might.
({num mightXp, num vitalityXp}) splitCombatVictoryXp(num totalXp, String style) {
  final amount = math.max(0, (jsNumber(totalXp)).floor());
  if (amount <= 0) return (mightXp: 0, vitalityXp: 0);
  if (style == 'offensive') return (mightXp: amount, vitalityXp: 0);
  if (style == 'defensive') return (mightXp: 0, vitalityXp: amount);
  final vitalityXp = (amount / 2).floor();
  return (mightXp: amount - vitalityXp, vitalityXp: vitalityXp);
}

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

num _scaleStat(num value, num multiplier) => math.max(0, (value * multiplier).floor());

num _damageRangeMultipliers(GameDatabase db, PlayerSave save) {
  final levelMult = mightDamageMultiplier(save);
  final styleMult = 1 + attackStyleDamageBonusPercent(normalizeAttackStyle(save.attackStyle)) / 100;
  final spellMult = activeSpellDamageRangeMultiplier(db, save);
  final potion = save.activePotionEffect;
  final potionBonus = potion?.damageBonusPercent;
  final potionMult =
      potionBonus != null && potionBonus > 0 && potion?.scope == 'one_combat_encounter'
      ? 1 + potionBonus / 100
      : 1;
  return levelMult * styleMult * spellMult * potionMult;
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

/// Mother Squid fishing combat: (2000 × Fishing ATR% + Fishing Level) ± 10%.
DamageRange fishingCombatDamageRange(GameDatabase db, PlayerSave save) {
  final atr = equippedActionTimeReductionPercent(db, save, fishingSkillId);
  final level = getSkillProgress(save, fishingSkillId).level;
  final base = 2000 * (atr / 100) + level;
  final min = math.max(1, (base * 0.9).floor());
  final max = math.max(min, (base * 1.1).floor());
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

  // Gloves with Min Damage (Pirate Hook / Dragon Gloves) raise minimum only.
  final glovesMinBonus = _equippedRows(db, save).fold<num>(0, (sum, row) {
    if (row.raw['Slot ID'] != 'SLOT-0007') return sum;
    final bonus = row.raw['Min Damage'];
    return bonus is num ? sum + bonus : sum;
  });
  base = DamageRange(min: base.min + glovesMinBonus, max: base.max);

  return _scaleDamageRange(base.min, base.max, combined);
}

/// Off-hand dagger damage range, or null when no dagger is equipped there.
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
  final gear = _equippedRows(
    db,
    save,
  ).fold<num>(0, (sum, row) => sum + jsNumber(row.raw['Damage Reduction'] ?? 0));
  return gear + attackStyleDamageReduction(normalizeAttackStyle(save.attackStyle));
}

num playerMaxHp(GameDatabase db, PlayerSave save) {
  final base = configNumber(db, 'starting_max_hp', 1000);
  final bonus = _equippedRows(
    db,
    save,
  ).fold<num>(0, (sum, row) => sum + jsNumber(row.raw['HP Bonus'] ?? 0));
  final levelMult = vitalityHpMultiplier(save);
  final raceMult = raceMaxHpMultiplier(db, save);
  return math.max(1, _scaleStat(base + bonus, levelMult * raceMult));
}

/// Max HP from base + Vitality + race only — equipment HP bonuses are ignored.
num playerBaseMaxHp(GameDatabase db, PlayerSave save) {
  final base = configNumber(db, 'starting_max_hp', 1000);
  final levelMult = vitalityHpMultiplier(save);
  final raceMult = raceMaxHpMultiplier(db, save);
  return math.max(1, _scaleStat(base, levelMult * raceMult));
}

num rollDamage(num min, num max, RandomFn random) {
  final lo = math.min(min, max);
  final hi = math.max(min, max);
  return lo + (random() * (hi - lo + 1)).floor();
}

num applyMitigation(num rawDamage, num reduction, num damageFloor) {
  return math.max(damageFloor, rawDamage - math.max(0, reduction));
}

/// @deprecated Use [mightDamageMultiplier] / [vitalityHpMultiplier].
num combatLevelBonusMultiplier(PlayerSave save) => mightDamageMultiplier(save);
