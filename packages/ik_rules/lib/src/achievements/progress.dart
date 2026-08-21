import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../activity/xp.dart';
import '../critters/critters.dart';
import '../js_compat.dart';
import '../save/generated/save_models.dart';
import '../skills/totals.dart';
import '../time.dart';

/// The Achievements and Statistics tables stay untyped rows: nothing reads them
/// by column except this module and the panels that list them.
List<Map<String, Object?>> achievementRows(GameDatabase db) => db.achievements;

List<Map<String, Object?>> statisticRows(GameDatabase db) => db.statistics;

/// Achievements in this category are re-checked every sync and can be lost.
///
/// A skill milestone is a thing the player did once, so it is theirs forever. A
/// collection is a statement about the collection as it stands now, which stops
/// being true the moment the world grows a new critter.
const String revocableAchievementCategory = 'Collections';

const String critterCollectorAchievementId = 'ACH-0015';

const List<String> achievementDifficulties = <String>['Easy', 'Medium', 'Hard'];

PlayerSave addLifetimeStat(PlayerSave save, String key, [num amount = 1]) {
  final current = jsNumber(save.statistics.values[key] ?? 0);
  return save.copyWith(
    statistics: PlayerStatistics(
      values: <String, num>{...save.statistics.values, key: current + amount},
    ),
  );
}

bool isSpellProject(Map<String, Object?> project) {
  final key = jsString(project['Internal Key']);
  final name = jsString(project['Display Name']).toLowerCase();
  return key.contains('_spell') || (name.contains('spell') && !name.contains('enchant'));
}

PlayerSave recordProjectMilestones(GameDatabase db, PlayerSave save, String projectId, num crafts) {
  final project = db.projects.firstWhereOrNull(
    (row) => jsString(row.raw['Project ID']) == projectId,
  );
  var next = addLifetimeStat(save, 'project_$projectId', crafts);
  final outputId = jsString(project?.raw['Output Item / Target ID']);
  if (outputId.startsWith('ENCH-')) {
    next = addLifetimeStat(next, 'items_enchanted', crafts);
  }
  if (project != null && isSpellProject(project.raw)) {
    next = addLifetimeStat(next, 'spell_projects', crafts);
  }
  return next;
}

PlayerSave recordProductionMilestones(
  GameDatabase db,
  PlayerSave save,
  String outputItemId,
  num quantity,
) {
  var next = addLifetimeStat(save, 'output_$outputItemId', quantity);
  final item = db.items.firstWhereOrNull((row) => jsString(row.raw['Item ID']) == outputItemId);
  if (jsString(item?.raw['Category']) == 'Potion') {
    next = addLifetimeStat(next, 'potions_created', quantity);
  }
  return next;
}

PlayerSave recordFoodConsumed(PlayerSave save, String itemId) =>
    addLifetimeStat(save, 'consumed_$itemId');

List<AchievementProgress> _upsertAchievement(
  List<AchievementProgress> list,
  String achievementId,
  String unlockedAt,
) {
  final existing = list.firstWhereOrNull((row) => row.achievementId == achievementId);
  if (existing != null && existing.unlocked) return list;
  return <AchievementProgress>[
    ...list.where((row) => row.achievementId != achievementId),
    AchievementProgress(achievementId: achievementId, unlocked: true, unlockedAt: unlockedAt),
  ];
}

List<AchievementProgress> _revokeAchievement(List<AchievementProgress> list, String achievementId) {
  final existing = list.firstWhereOrNull((row) => row.achievementId == achievementId);
  if (existing == null) return list;
  return list.where((row) => row.achievementId != achievementId).toList();
}

/// Whether the collection holds at least one of every critter that exists.
bool hasEveryCritter(PlayerSave save) {
  if (critterDefs.isEmpty) return false;
  return critterDefs.every((critter) => collectionCount(save, critter.id) > 0);
}

/// Whether a save currently qualifies for a category that can be lost again.
bool _holdsRevocableAchievement(PlayerSave save, String achievementId) {
  return achievementId == critterCollectorAchievementId && hasEveryCritter(save);
}

num _lifetimeCount(Map<String, num> values, String key) => jsNumber(values[key] ?? 0);

bool _holdsMilestone(
  GameDatabase db,
  PlayerSave save,
  Map<String, Object?> achievement,
  Map<String, num> values,
) {
  final check = jsString(achievement['Check Type']);
  final target = achievement['Target ID'];
  final count = jsNumber(achievement['Required Count'] ?? 1);
  final required = achievement['Required Level'];
  switch (check) {
    case 'project':
      return target is String && _lifetimeCount(values, 'project_$target') >= count;
    case 'consume':
      return target is String && _lifetimeCount(values, 'consumed_$target') >= count;
    case 'output_item':
      return target is String && _lifetimeCount(values, 'output_$target') >= count;
    case 'enchant':
      return _lifetimeCount(values, 'items_enchanted') >= count;
    case 'potion':
      return _lifetimeCount(values, 'potions_created') >= count;
    case 'spell_projects':
      return _lifetimeCount(values, 'spell_projects') >= count;
    case 'gold':
      return _lifetimeCount(values, 'gold_earned') >= count;
    case 'skill_all':
      if (required is! num) return false;
      return db.skills.every((skill) => getSkillProgress(save, skill.skillId).level >= required);
    default:
      final skillId = achievement['Target Skill ID'];
      if (skillId is! String || skillId.isEmpty || required is! num) return false;
      return getSkillProgress(save, skillId).level >= required;
  }
}

/// Refreshes the lifetime totals and unlocks any skill-level achievement the
/// player now qualifies for.
PlayerSave syncProgressionMeta(GameDatabase db, PlayerSave save, num nowMs) {
  final crittersCollected = save.critterCollections.fold<num>(
    0,
    (sum, row) => sum + math.max(0, row.count),
  );
  final values = <String, num>{
    ...save.statistics.values,
    'total_level': totalLevel(save),
    'total_experience': totalSkillXp(save),
    'gold_earned': jsNumber(save.statistics.values['gold_earned'] ?? 0),
    'monsters_killed': jsNumber(save.statistics.values['monsters_killed'] ?? 0),
    'critters_collected': crittersCollected,
    'bounties_completed': jsNumber(save.statistics.values['bounties_completed'] ?? 0),
  };

  var achievements = save.achievements;
  final unlockedAt = isoFromMs(nowMs);
  for (final achievement in achievementRows(db)) {
    final achievementId = jsString(achievement['Achievement ID']);
    if (achievement['Category'] == revocableAchievementCategory) {
      achievements = _holdsRevocableAchievement(save, achievementId)
          ? _upsertAchievement(achievements, achievementId, unlockedAt)
          : _revokeAchievement(achievements, achievementId);
      continue;
    }
    if (_holdsMilestone(db, save, achievement, values)) {
      achievements = _upsertAchievement(achievements, achievementId, unlockedAt);
    }
  }

  return save.copyWith(
    statistics: PlayerStatistics(values: values),
    achievements: achievements,
  );
}
