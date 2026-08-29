import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../activity/requirements.dart';
import '../activity/xp.dart';
import '../js_compat.dart';
import '../production/recipes.dart';
import '../projects/projects.dart';
import '../recipes/knowledge.dart';
import '../save/generated/save_models.dart';

/// Activities, recipes, and projects that become available in a level range.
class SkillUnlockSummary {
  const SkillUnlockSummary({
    required this.unlockedActivities,
    required this.proficientActivities,
    required this.recipes,
    required this.projects,
  });

  final List<String> unlockedActivities;
  final List<String> proficientActivities;
  final List<String> recipes;
  final List<String> projects;

  bool get isEmpty =>
      unlockedActivities.isEmpty &&
      proficientActivities.isEmpty &&
      recipes.isEmpty &&
      projects.isEmpty;

  bool get isNotEmpty => !isEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'unlockedActivities': unlockedActivities,
    'proficientActivities': proficientActivities,
    'recipes': recipes,
    'projects': projects,
  };
}

/// One skill that just rose, plus what that new level opened.
class SkillLevelUpNotice {
  const SkillLevelUpNotice({
    required this.skillId,
    required this.skillName,
    required this.level,
    required this.unlocks,
  });

  final String skillId;
  final String skillName;
  final num level;
  final SkillUnlockSummary unlocks;

  Map<String, Object?> toJson() => <String, Object?>{
    'skillId': skillId,
    'skillName': skillName,
    'level': level,
    'unlocks': unlocks.toJson(),
  };
}

bool _inLevelRange(num value, num fromLevel, num toLevel) {
  return value > fromLevel && value <= toLevel;
}

String _skillName(GameDatabase db, String skillId) {
  final name = db.skills.firstWhereOrNull((skill) => skill.skillId == skillId)?.displayName;
  return name is String && name.isNotEmpty ? name : skillId;
}

String _activityName(ActivityRow activity) {
  final contextual = activity.contextualName?.trim();
  if (contextual != null && contextual.isNotEmpty) return contextual;
  return activity.activityId;
}

List<ActionRow> _actionsForActivity(GameDatabase db, ActivityRow activity) {
  final poolId = activity.poolId;
  if (poolId == null || poolId.isEmpty) return const <ActionRow>[];
  final actionIds = <String>{
    for (final entry in db.poolEntries)
      if (entry.raw['Pool ID'] == poolId) jsString(entry.raw['Action ID']),
  };
  if (actionIds.isEmpty) return const <ActionRow>[];
  return [
    for (final action in db.actions)
      if (actionIds.contains(action.actionId)) action,
  ];
}

List<String> _uniqueSorted(Iterable<String> names) {
  final out = names.where((name) => name.trim().isNotEmpty).toSet().toList();
  mergeSort(out, compare: jsLocaleCompare);
  return out;
}

/// Names unlocked between [fromLevel] (exclusive) and [toLevel] (inclusive).
SkillUnlockSummary skillUnlocksBetween(
  GameDatabase db,
  PlayerSave saveAfter,
  String skillId,
  num fromLevel,
  num toLevel,
) {
  if (toLevel <= fromLevel) {
    return const SkillUnlockSummary(
      unlockedActivities: <String>[],
      proficientActivities: <String>[],
      recipes: <String>[],
      projects: <String>[],
    );
  }

  final unlocked = <String>[];
  final proficient = <String>[];

  for (final activity in db.activities) {
    if (activity.status == 'Needs Data') continue;
    if (!activityVisibleForSave(db, saveAfter, activity.activityId)) continue;
    final name = _activityName(activity);

    for (final requirement in requirementsForEntity(db, 'Activity', activity.activityId)) {
      if (requirement.requirementType != 'Skill Level') continue;
      if ((requirement.operatorValue ?? '').toLowerCase() == 'proficiency') continue;
      if (jsString(requirement.referenceIdValue) != skillId) continue;
      final required = requirement.requiredValue;
      if (required is num && _inLevelRange(required, fromLevel, toLevel)) {
        unlocked.add(name);
      }
    }

    for (final action in _actionsForActivity(db, activity)) {
      if (action.status == 'Needs Data') continue;
      if (action.relevantSkillId != skillId) continue;
      final proficiency = action.proficiencyLevel;
      if (proficiency is num && _inLevelRange(proficiency, fromLevel, toLevel)) {
        proficient.add(name);
      }
    }
  }

  final recipes = <String>[];
  for (final recipe in db.recipes.where(isCompleteRecipe)) {
    if (jsString(recipe.raw['Skill ID']) != skillId) continue;
    if (!knowsRecipe(saveAfter, db, jsString(recipe.raw['Recipe ID']))) continue;
    final proficiency = recipe.raw['Proficiency Level'];
    if (proficiency is num && _inLevelRange(proficiency, fromLevel, toLevel)) {
      recipes.add(jsString(recipe.raw['Display Name']));
    }
  }

  final projects = <String>[];
  for (final project in db.projects.where(isCompleteProject)) {
    if (!meetsProjectKnowledge(db, saveAfter, project)) continue;
    if (!meetsProjectSkills(saveAfter, project)) continue;
    final hit = projectSkillRequirements(project).any(
      (requirement) =>
          requirement.skillId == skillId && _inLevelRange(requirement.level, fromLevel, toLevel),
    );
    if (hit) projects.add(jsString(project.raw['Display Name']));
  }

  final unlockedNames = _uniqueSorted(unlocked);
  final unlockedSet = unlockedNames.toSet();
  final proficientNames = _uniqueSorted(proficient.where((name) => !unlockedSet.contains(name)));

  return SkillUnlockSummary(
    unlockedActivities: unlockedNames,
    proficientActivities: proficientNames,
    recipes: _uniqueSorted(recipes),
    projects: _uniqueSorted(projects),
  );
}

/// Skills that rose from [before] to [after], each with the unlocks in that jump.
List<SkillLevelUpNotice> skillLevelUpsBetween(
  GameDatabase db,
  PlayerSave before,
  PlayerSave after,
) {
  final fromLevels = <String, num>{for (final skill in before.skills) skill.skillId: skill.level};
  final notices = <SkillLevelUpNotice>[];
  final seen = <String>{};
  for (final skill in after.skills) {
    if (!seen.add(skill.skillId)) continue;
    final from = fromLevels[skill.skillId] ?? 1;
    if (skill.level <= from) continue;
    notices.add(
      SkillLevelUpNotice(
        skillId: skill.skillId,
        skillName: _skillName(db, skill.skillId),
        level: skill.level,
        unlocks: skillUnlocksBetween(db, after, skill.skillId, from, skill.level),
      ),
    );
  }
  mergeSort(notices, compare: (a, b) => jsLocaleCompare(a.skillName, b.skillName));
  return notices;
}
