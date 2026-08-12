import '../save/generated/save_models.dart';

num totalSkillXp(PlayerSave save) => save.skills.fold<num>(0, (sum, skill) => sum + skill.xp);

/// Sum of all skill levels; each skill starts at 1.
num totalLevel(PlayerSave save) => save.skills.fold<num>(0, (sum, skill) => sum + skill.level);
