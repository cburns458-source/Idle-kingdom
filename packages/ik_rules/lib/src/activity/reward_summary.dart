import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../save/generated/save_models.dart';
import 'xp.dart';

/// One skill's XP line in the action reward UI.
class ActionXpRewardSummary {
  const ActionXpRewardSummary({
    required this.skillId,
    required this.skillName,
    required this.skillKey,
    required this.xp,
    required this.level,
    required this.leveledUp,
  });

  final String skillId;
  final String skillName;
  final String skillKey;
  final num xp;
  final num level;
  final bool leveledUp;

  Map<String, Object?> toJson() => <String, Object?>{
    'skillId': skillId,
    'skillName': skillName,
    'skillKey': skillKey,
    'xp': xp,
    'level': level,
    'leveledUp': leveledUp,
  };
}

ActionXpRewardSummary? summarizeXpReward(
  GameDatabase db,
  PlayerSave saveAfter,
  String skillId,
  num xp,
  num? leveledUpTo,
) {
  if (xp <= 0) return null;
  final skill = db.skills.firstWhereOrNull((row) => row.raw['Skill ID'] == skillId);
  final displayName = skill?.raw['Display Name'];
  final internalKey = skill?.raw['Internal Key'];
  return ActionXpRewardSummary(
    skillId: skillId,
    skillName: displayName is String ? displayName : 'Skill',
    skillKey: internalKey is String ? internalKey : skillId,
    xp: xp,
    level: leveledUpTo ?? getSkillProgress(saveAfter, skillId).level,
    leveledUp: leveledUpTo != null,
  );
}
