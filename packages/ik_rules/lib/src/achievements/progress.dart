import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../activity/xp.dart';
import '../critters/critters.dart';
import '../equipment/loadout.dart';
import '../js_compat.dart';
import '../save/generated/save_models.dart';
import '../skills/totals.dart';
import '../tags.dart';
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
  final locationId = save.currentLocationId;
  if (locationId.isNotEmpty) {
    next = addLifetimeStat(next, 'project_${projectId}_at_$locationId', crafts);
  }
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
  final locationId = save.currentLocationId;
  if (locationId.isNotEmpty) {
    next = addLifetimeStat(next, 'output_${outputItemId}_at_$locationId', quantity);
  }
  final item = db.items.firstWhereOrNull((row) => jsString(row.raw['Item ID']) == outputItemId);
  if (jsString(item?.raw['Category']) == 'Potion') {
    next = addLifetimeStat(next, 'potions_created', quantity);
  }
  return next;
}

PlayerSave recordFoodConsumed(PlayerSave save, String itemId) =>
    addLifetimeStat(save, 'consumed_$itemId');

PlayerSave recordGatheredDrops(
  PlayerSave save,
  Iterable<String> itemIds,
  String locationId,
  String? weaponId,
) {
  final wield = weaponId != null && weaponId.isNotEmpty ? weaponId : 'none';
  var next = save;
  for (final itemId in itemIds) {
    next = addLifetimeStat(next, 'gathered_${itemId}_at_${locationId}_wield_$wield');
  }
  return next;
}

PlayerSave recordItemsSoldAtLocation(
  PlayerSave save,
  Iterable<({String itemId, num quantity})> items,
  String locationId,
) {
  var next = save;
  for (final item in items) {
    final qty = math.max(0, jsNumber(item.quantity));
    if (qty <= 0) continue;
    next = addLifetimeStat(next, 'sold_${item.itemId}_at_$locationId', qty);
  }
  return next;
}

bool itemHasClassLabel(GameDatabase db, String itemId, String label) {
  final wanted = label.trim().toLowerCase();
  if (wanted.isEmpty) return false;
  if (itemHasCapability(db, itemId, wanted)) return true;
  final item = db.items.firstWhereOrNull((row) => jsString(row.raw['Item ID']) == itemId);
  return capabilityTags(item?.raw['Functional / Source Tags']).contains(wanted);
}

List<String> classLabelsFromAchievements(GameDatabase db) {
  final labels = <String>{};
  for (final row in achievementRows(db)) {
    if (jsString(row['Check Type']) != 'kill_enemy_class') continue;
    final parsed = _parseKillEnemyClass(
      row['Target ID'] is String ? row['Target ID'] as String : null,
    );
    if (parsed == null) continue;
    labels.addAll(parsed.classes);
  }
  return labels.toList();
}

List<String> classLabelsOnItem(GameDatabase db, String itemId) {
  return classLabelsFromAchievements(db)
      .where((label) => itemHasClassLabel(db, itemId, label))
      .toList();
}

PlayerSave recordEnemyKill(GameDatabase db, PlayerSave save, String enemyId) {
  var next = addLifetimeStat(save, 'killed_$enemyId');
  final weaponId = save.equipment.slots[weaponToolSlotId]?.itemId;
  if (weaponId == null) return next;
  for (final label in classLabelsOnItem(db, weaponId)) {
    next = addLifetimeStat(next, 'killed_${enemyId}_class_$label');
  }
  return next;
}

({String id, String locationId})? _parseAtLocation(String? target) {
  if (target == null) return null;
  final at = target.indexOf('@');
  if (at <= 0 || at == target.length - 1) return null;
  return (id: target.substring(0, at), locationId: target.substring(at + 1));
}

({String itemId, String locationId, String weaponId})? _parseGatherDrop(String? target) {
  if (target == null) return null;
  final parts = target.split('+wield:');
  if (parts.length != 2) return null;
  final parsed = _parseAtLocation(parts[0]);
  if (parsed == null || parts[1].isEmpty) return null;
  return (itemId: parsed.id, locationId: parsed.locationId, weaponId: parts[1]);
}

({String enemyId, List<String> classes})? _parseKillEnemyClass(String? target) {
  if (target == null) return null;
  final parts = target.split('+class:');
  if (parts.length != 2) return null;
  final classes = parts[1]
      .split('|')
      .map((part) => part.trim().toLowerCase())
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts[0].isEmpty || classes.isEmpty) return null;
  return (enemyId: parts[0], classes: classes);
}

Set<String> _equippedItemIds(PlayerSave save) {
  return save.equipment.slots.values.map((stack) => stack?.itemId).whereType<String>().toSet();
}

bool _holdsEquipSet(PlayerSave save, String? target) {
  if (target == null || target.isEmpty) return false;
  final needed = target.split(',').map((part) => part.trim()).where((part) => part.isNotEmpty);
  if (needed.isEmpty) return false;
  final worn = _equippedItemIds(save);
  return needed.every(worn.contains);
}

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
    case 'output_at_location':
      final outputAt = _parseAtLocation(target is String ? target : null);
      return outputAt != null &&
          _lifetimeCount(values, 'output_${outputAt.id}_at_${outputAt.locationId}') >= count;
    case 'project_at_location':
      final projectAt = _parseAtLocation(target is String ? target : null);
      return projectAt != null &&
          _lifetimeCount(values, 'project_${projectAt.id}_at_${projectAt.locationId}') >= count;
    case 'gather_drop':
      final gathered = _parseGatherDrop(target is String ? target : null);
      return gathered != null &&
          _lifetimeCount(
                values,
                'gathered_${gathered.itemId}_at_${gathered.locationId}_wield_${gathered.weaponId}',
              ) >=
              count;
    case 'sold_at_location':
      final sold = _parseAtLocation(target is String ? target : null);
      return sold != null &&
          _lifetimeCount(values, 'sold_${sold.id}_at_${sold.locationId}') >= count;
    case 'kill_enemy':
      return target is String && _lifetimeCount(values, 'killed_$target') >= count;
    case 'kill_enemy_class':
      final killClass = _parseKillEnemyClass(target is String ? target : null);
      if (killClass == null) return false;
      return killClass.classes.any(
        (label) => _lifetimeCount(values, 'killed_${killClass.enemyId}_class_$label') >= count,
      );
    case 'equip_set':
      return _holdsEquipSet(save, target is String ? target : null);
    case 'equip_quiver_bow':
      if (target is! String || target.isEmpty) return false;
      if (!_equippedItemIds(save).contains(target)) return false;
      final weaponId = save.equipment.slots[weaponToolSlotId]?.itemId;
      return weaponId != null && itemHasCapability(db, weaponId, 'bow_combat_xp');
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
