import 'dart:math' as math;

import 'package:ik_content/ik_content.dart';

import '../config.dart';
import '../equipment/loadout.dart';
import '../equipment/specialist.dart';
import '../js_compat.dart';
import '../projects/enchantments.dart';
import '../rng/mulberry32.dart';
import '../save/generated/save_models.dart';
import '../spells/spells.dart';
import 'xp.dart';

/// Level 1 = 40%, +0.5% per skill level (89.5% at level 100).
/// Plus +1% for each level above the action's proficiency level.
num gatheringSuccessChancePercent(num level, [num proficiencyLevel = 1]) {
  return _successChancePercent(level, proficiencyLevel, 40);
}

/// Standard production copy of the gathering curve with a +10% base
/// (level 1 = 50%, 99.5% at level 100, same above-proficiency bonus).
num productionSuccessChancePercent(num level, [num proficiencyLevel = 1]) {
  return _successChancePercent(level, proficiencyLevel, 50);
}

num _successChancePercent(num level, num proficiencyLevel, num baseAtLevel1) {
  final lvl = math.max(1, level.floor());
  final proficiency = math.max(1, proficiencyLevel.floor());
  final base = baseAtLevel1 + 0.5 * (lvl - 1);
  final aboveProficiency = math.max(0, lvl - proficiency);
  return math.min(100, base + aboveProficiency);
}

/// False means the action yields no loot and no XP.
bool rollGatheringSuccess(num level, RandomFn random, [num proficiencyLevel = 1]) {
  return random() * 100 < gatheringSuccessChancePercent(level, proficiencyLevel);
}

/// False means the craft botches: materials spent, no output/XP.
bool rollProductionSuccess(num level, RandomFn random, [num proficiencyLevel = 1]) {
  return random() * 100 < productionSuccessChancePercent(level, proficiencyLevel);
}

num gatheringDurationMs(GameDatabase db, PlayerSave save, ActionRow action) {
  final baseSeconds = jsNumber(action.raw['Base Duration Seconds'] ?? 0);
  final proficiency = jsNumber(action.raw['Proficiency Level'] ?? 1);
  final skill = getSkillProgress(save, jsString(action.raw['Relevant Skill ID']));
  final multiplier = skill.level < proficiency
      ? configNumber(db, 'gathering_below_proficiency_duration_multiplier', 2)
      : 1;
  final skillId = jsString(action.raw['Relevant Skill ID']);
  final actionTimeReduction = equippedActionTimeReductionPercentForAction(db, save, action);
  final reductionFactor = math.max(0.01, 1 - actionTimeReduction / 100);
  final enchantFactor = equippedEnchantmentGatheringMultiplier(db, save, skillId);
  final spellFactor = activeSpellGatheringDurationMultiplier(db, save);
  return math.max(
    0,
    baseSeconds * multiplier * reductionFactor * enchantFactor * spellFactor * 1000,
  );
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
