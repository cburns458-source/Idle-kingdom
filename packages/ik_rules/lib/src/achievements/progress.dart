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

List<AchievementProgress> _revokeAchievement(
  List<AchievementProgress> list,
  String achievementId,
) {
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
    final skillId = achievement['Target Skill ID'];
    final required = achievement['Required Level'];
    if (skillId is! String || skillId.isEmpty || required is! num) continue;
    if (getSkillProgress(save, skillId).level >= required) {
      achievements = _upsertAchievement(achievements, achievementId, unlockedAt);
    }
  }

  return save.copyWith(
    statistics: PlayerStatistics(values: values),
    achievements: achievements,
  );
}
