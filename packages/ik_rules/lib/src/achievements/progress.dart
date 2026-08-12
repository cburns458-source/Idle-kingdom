import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../activity/xp.dart';
import '../js_compat.dart';
import '../save/generated/save_models.dart';
import '../skills/totals.dart';
import '../time.dart';

/// The Achievements and Statistics tables stay untyped rows: nothing reads them
/// by column except this module and the panels that list them.
List<Map<String, Object?>> achievementRows(GameDatabase db) => db.achievements;

List<Map<String, Object?>> statisticRows(GameDatabase db) => db.statistics;

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
    final skillId = achievement['Target Skill ID'];
    final required = achievement['Required Level'];
    if (skillId is! String || skillId.isEmpty || required is! num) continue;
    if (getSkillProgress(save, skillId).level >= required) {
      achievements = _upsertAchievement(
        achievements,
        jsString(achievement['Achievement ID']),
        unlockedAt,
      );
    }
  }

  return save.copyWith(
    statistics: PlayerStatistics(values: values),
    achievements: achievements,
  );
}
