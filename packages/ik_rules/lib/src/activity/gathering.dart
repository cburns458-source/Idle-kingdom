import 'dart:math' as math;

import 'package:ik_content/ik_content.dart';

import '../config.dart';
import '../equipment/specialist.dart';
import '../js_compat.dart';
import '../projects/enchantments.dart';
import '../rng/mulberry32.dart';
import '../save/generated/save_models.dart';
import '../spells/spells.dart';
import 'xp.dart';

/// Gathering: base = 80 − (proficiency ~/ 4) (lvl 1 → 80%, lvl 40 → 70%, lvl 88 → 58%).
/// Then −0.75%/level below proficiency, +1%/level above. Clamped 0–100.
/// Optional flat success-chance bonus from gear is applied by callers.
num gatheringSuccessChancePercent(
  num level, [
  num proficiencyLevel = 1,
  num successChanceBonusPercent = 0,
]) {
  final proficiency = math.max(1, proficiencyLevel.floor());
  final base = 80 - (proficiency ~/ 4);
  return _successChancePercent(level, proficiency, base, successChanceBonusPercent);
}

/// Production: base 70%. −0.75%/level below proficiency, +1%/level above.
/// Clamped 0–100. Optional flat success-chance bonus from gear is applied by callers.
num productionSuccessChancePercent(
  num level, [
  num proficiencyLevel = 1,
  num successChanceBonusPercent = 0,
]) {
  return _successChancePercent(level, proficiencyLevel, 70, successChanceBonusPercent);
}

num _successChancePercent(
  num level,
  num proficiencyLevel,
  num baseAtProficiency, [
  num successChanceBonusPercent = 0,
]) {
  final lvl = math.max(1, level.floor());
  final proficiency = math.max(1, proficiencyLevel.floor());
  final delta = lvl - proficiency;
  final chance =
      (delta < 0 ? baseAtProficiency + delta * 0.75 : baseAtProficiency + delta) +
      math.max(0, successChanceBonusPercent);
  return math.max(0, math.min(100, chance));
}

/// False means the action yields no loot and no XP.
bool rollGatheringSuccess(
  num level,
  RandomFn random, [
  num proficiencyLevel = 1,
  num successChanceBonusPercent = 0,
]) {
  return random() * 100 <
      gatheringSuccessChancePercent(level, proficiencyLevel, successChanceBonusPercent);
}

/// False means the craft botches: materials spent, no output/XP.
bool rollProductionSuccess(
  num level,
  RandomFn random, [
  num proficiencyLevel = 1,
  num successChanceBonusPercent = 0,
]) {
  return random() * 100 <
      productionSuccessChancePercent(level, proficiencyLevel, successChanceBonusPercent);
}

num gatheringDurationMs(GameDatabase db, PlayerSave save, ActionRow action) {
  final baseSeconds = jsNumber(action.raw['Base Duration Seconds'] ?? 0);
  final proficiency = jsNumber(action.raw['Proficiency Level'] ?? 1);
  final skill = getSkillProgress(save, jsString(action.raw['Relevant Skill ID']));
  final multiplier = skill.level < proficiency
      ? configNumber(db, 'gathering_below_proficiency_duration_multiplier', 2)
      : 1;
  final skillId = jsString(action.raw['Relevant Skill ID']);
  final enchantFactor = equippedEnchantmentGatheringMultiplier(db, save, skillId);
  final spellFactor = activeSpellGatheringDurationMultiplier(db, save);
  return math.max(0, baseSeconds * multiplier * enchantFactor * spellFactor * 1000);
}

bool isBelowProficiency(PlayerSave save, ActionRow action) {
  final proficiency = jsNumber(action.raw['Proficiency Level'] ?? 1);
  final skill = getSkillProgress(save, jsString(action.raw['Relevant Skill ID']));
  return skill.level < proficiency;
}

/// XP granted for a gathering action (halved when below proficiency).
num gatheringXpReward(GameDatabase db, PlayerSave save, ActionRow action, [num? baseXp]) {
  final amount = math.max(0, jsNumberOrZero(baseXp ?? jsNumber(action.raw['XP Reward'] ?? 0)));
  if (amount <= 0) return 0;
  final afterProficiency = !isBelowProficiency(save, action)
      ? amount.floor()
      : (amount * configNumber(db, 'gathering_below_proficiency_xp_multiplier', 0.5)).floor();
  return applyQuiverHuntingXp(
    db,
    afterProficiency,
    save,
    jsString(action.raw['Relevant Skill ID']),
  );
}
