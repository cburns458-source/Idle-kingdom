import 'dart:math' as math;

import 'package:ik_content/ik_content.dart';

import '../config.dart';
import '../equipment/loadout.dart';
import '../equipment/specialist.dart';
import '../js_compat.dart';
import '../projects/enchantments.dart';
import '../save/generated/save_models.dart';
import 'xp.dart';

num gatheringDurationMs(GameDatabase db, PlayerSave save, ActionRow action) {
  final baseSeconds = jsNumber(action.raw['Base Duration Seconds'] ?? 0);
  final proficiency = jsNumber(action.raw['Proficiency Level'] ?? 1);
  final skill = getSkillProgress(save, jsString(action.raw['Relevant Skill ID']));
  final multiplier = skill.level < proficiency
      ? configNumber(db, 'gathering_below_proficiency_duration_multiplier', 2)
      : 1;
  final actionTimeReduction = equippedActionTimeReductionPercent(db, save);
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
  return applyQuiverHuntingXp(afterProficiency, save, jsString(action.raw['Relevant Skill ID']));
}
