import '../combat/stats.dart' show combatSkillId;
import '../save/generated/save_models.dart';

num totalSkillXp(PlayerSave save) => save.skills.fold<num>(0, (sum, skill) => sum + skill.xp);

/// Sum of all skill levels; each skill starts at 1.
num totalLevel(PlayerSave save) => save.skills.fold<num>(0, (sum, skill) => sum + skill.level);

/// Whether this character has never raised Combat past where it started.
///
/// A save with no Combat row at all counts: the skill only appears once it has
/// been touched, and an untouched Combat is the whole point.
bool isPacifistSave(PlayerSave save) {
  for (final skill in save.skills) {
    if (skill.skillId == combatSkillId) return skill.level <= 1;
  }
  return true;
}
