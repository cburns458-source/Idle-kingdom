import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../save/generated/save_models.dart';

SkillProgress getSkillProgress(PlayerSave save, String skillId) {
  final existing = save.skills.firstWhereOrNull((skill) => skill.skillId == skillId);
  return existing ?? SkillProgress(skillId: skillId, level: 1, xp: 0);
}

num levelForTotalXp(GameDatabase db, num totalXp) {
  num level = 1;
  for (final row in db.xpCurve) {
    if (totalXp >= row.totalXpAtLevel) {
      level = row.level;
    } else {
      break;
    }
  }
  return level;
}

class ApplyXpResult {
  const ApplyXpResult({required this.save, this.leveledUpTo});

  final PlayerSave save;
  final num? leveledUpTo;
}

ApplyXpResult applyXp(PlayerSave save, GameDatabase db, String skillId, num xpAmount) {
  if (xpAmount <= 0) return ApplyXpResult(save: save);

  final skills = [...save.skills];
  var index = skills.indexWhere((skill) => skill.skillId == skillId);
  if (index < 0) {
    skills.add(SkillProgress(skillId: skillId, level: 1, xp: 0));
    index = skills.length - 1;
  }

  final previous = skills[index];
  final xp = previous.xp + xpAmount;
  final level = levelForTotalXp(db, xp);
  skills[index] = previous.copyWith(xp: xp, level: level);

  return ApplyXpResult(
    save: save.copyWith(skills: skills),
    leveledUpTo: level > previous.level ? level : null,
  );
}

class RaiseSkillResult {
  const RaiseSkillResult({required this.save, required this.raised});

  final PlayerSave save;
  final bool raised;
}

/// Raises a skill to at least [minLevel] by total XP; a no-op when already there.
RaiseSkillResult raiseSkillToMinimumLevel(
  PlayerSave save,
  GameDatabase db,
  String skillId,
  num minLevel,
) {
  if (minLevel <= 1) return RaiseSkillResult(save: save, raised: false);
  final current = getSkillProgress(save, skillId);
  if (current.level >= minLevel) return RaiseSkillResult(save: save, raised: false);

  final curveRow = db.xpCurve.firstWhereOrNull((row) => row.level == minLevel);
  if (curveRow == null) return RaiseSkillResult(save: save, raised: false);
  final xpAtLevel = curveRow.totalXpAtLevel;

  final skills = [...save.skills];
  var index = skills.indexWhere((skill) => skill.skillId == skillId);
  if (index < 0) {
    skills.add(SkillProgress(skillId: skillId, level: 1, xp: 0));
    index = skills.length - 1;
  }

  final xp = math.max(skills[index].xp, xpAtLevel);
  final level = levelForTotalXp(db, xp);
  skills[index] = skills[index].copyWith(xp: xp, level: level);

  return RaiseSkillResult(
    save: save.copyWith(skills: skills),
    raised: level >= minLevel && current.level < minLevel,
  );
}
