import '../combat/stats.dart' show mightSkillId, vitalitySkillId;
import '../save/generated/save_models.dart';

num totalSkillXp(PlayerSave save) => save.skills.fold<num>(0, (sum, skill) => sum + skill.xp);

/// Sum of all skill levels; each skill starts at 1.
num totalLevel(PlayerSave save) => save.skills.fold<num>(0, (sum, skill) => sum + skill.level);

/// Whether this character has never raised Might or Vitality past where they started.
bool isPacifistSave(PlayerSave save) {
  var mightOk = true;
  var vitalityOk = true;
  for (final skill in save.skills) {
    if (skill.skillId == mightSkillId) mightOk = skill.level <= 1;
    if (skill.skillId == vitalitySkillId) vitalityOk = skill.level <= 1;
  }
  return mightOk && vitalityOk;
}
