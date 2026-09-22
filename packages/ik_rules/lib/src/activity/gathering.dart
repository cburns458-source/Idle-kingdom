import 'dart:math' as math;

import 'package:ik_content/ik_content.dart';

import '../config.dart';
import '../equipment/loadout.dart';
import '../equipment/specialist.dart';
import '../js_compat.dart';
import '../projects/enchantments.dart';
import '../rng/mulberry32.dart';
import '../save/generated/save_models.dart';
import 'xp.dart';

/// Level 1 = 40%, +0.5% per skill level (89.5% at level 100).
/// Plus +1% for each level above the action's proficiency level.
///
/// A standard production craft rolls against this same curve, reading the
/// recipe's proficiency level in place of the action's.
num gatheringSuccessChancePercent(num level, [num proficiencyLevel = 1]) {
  final lvl = math.max(1, level.floor());
  final proficiency = math.max(1, proficiencyLevel.floor());
  final base = 40 + 0.5 * (lvl - 1);
  final aboveProficiency = math.max(0, lvl - proficiency);
  return math.min(100, base + aboveProficiency);
}

/// False means the action yields no loot and no XP.
bool rollGatheringSuccess(num level, RandomFn random, [num proficiencyLevel = 1]) {
  return random() * 100 < gatheringSuccessChancePercent(level, proficiencyLevel);
}

num gatheringDurationMs(GameDatabase db, PlayerSave save, ActionRow action) {
  final baseSeconds = jsNumber(action.raw['Base Duration Seconds'] ?? 0);
  final proficiency = jsNumber(action.raw['Proficiency Level'] ?? 1);
  final skill = getSkillProgress(save, jsString(action.raw['Relevant Skill ID']));
  final multiplier = skill.level < proficiency
      ? configNumber(db, 'gathering_below_proficiency_duration_multiplier', 2)
      : 1;
  final actionTimeReduction = equippedActionTimeReductionPercent(
    db,
    save,
    jsString(action.raw['Relevant Skill ID']),
  );
  final reductionFactor = math.max(0.01, 1 - actionTimeReduction / 100);
  final enchantFactor = equippedEnchantmentGatheringMultiplier(db, save);
  return math.max(0, baseSeconds * multiplier * reductionFactor * enchantFactor * 1000);
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
