import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../config.dart';
import '../js_compat.dart';
import '../save/generated/save_models.dart';
import '../skills/totals.dart';

const num religionChooseTotalLevel = 100;
const String religionChangeGoldPerTotalLevelKey = 'religion_change_gold_per_total_level';
const String religionChangeCooldownMsKey = 'religion_change_cooldown_ms';
const String religionChooseLocationIdKey = 'religion_choose_location_id';
const String templeLocationIdFallback = 'LOC-0036';

/// PLACEHOLDER: Economy will replace this linear per-total-level gold cost.
const num religionChangeGoldPerTotalLevelFallback = 10;
const num religionChangeCooldownMsFallback = 7 * 24 * 60 * 60 * 1000;

/// Faiths in display order.
///
/// `mergeSort` rather than `List.sort`, because rows that tie on both keys must
/// keep their database order the way JavaScript's stable sort leaves them.
List<ReligionRow> religions(GameDatabase db) {
  final rows = [...db.religions];
  mergeSort<ReligionRow>(
    rows,
    compare: (a, b) => jsCompareThen(
      jsNumber(a.raw['Sort Order'] ?? 0) - jsNumber(b.raw['Sort Order'] ?? 0),
      () => jsLocaleCompare(jsString(a.raw['Display Name']), jsString(b.raw['Display Name'])),
    ),
  );
  return rows;
}

ReligionRow? religionById(GameDatabase db, String? religionId) {
  if (isBlank(religionId)) return null;
  return db.religions.firstWhereOrNull((row) => row.raw['Religion ID'] == religionId);
}

String? religionDisplayName(GameDatabase db, String? religionId) {
  final displayName = religionById(db, religionId)?.raw['Display Name'];
  return displayName is String ? displayName : null;
}

List<ReligionBonusRow> religionBonusesFor(GameDatabase db, String? religionId) {
  if (isBlank(religionId)) return const <ReligionBonusRow>[];
  return db.religionBonuses
      .where((row) => row.raw['Religion ID'] == religionId && row.raw['Status'] != 'Needs Data')
      .toList();
}

num _matchingBonusPercent(
  Iterable<Map<String, Object?>> bonuses,
  String bonusType, [
  String? referenceId,
]) {
  num total = 0;
  for (final bonus in bonuses) {
    if (bonus['Bonus Type'] != bonusType) continue;
    final rowReference = bonus['Reference ID'];
    if (referenceId != null && rowReference != referenceId) continue;
    if (referenceId == null && rowReference != null) continue;
    final value = jsNumber(bonus['Bonus Value'] ?? 0);
    if (value.isFinite) total += value;
  }
  return total;
}

num _totalReligionBonusPercent(
  GameDatabase db,
  String? religionId,
  String bonusType, [
  String? referenceId,
]) {
  return _matchingBonusPercent(
    religionBonusesFor(db, religionId).map((row) => row.raw),
    bonusType,
    referenceId,
  );
}

/// Race bonus fallback, inlined so this module does not import `races.dart`.
num _totalRaceBonusPercent(
  GameDatabase db,
  String? raceId,
  String bonusType, [
  String? referenceId,
]) {
  if (isBlank(raceId)) return 0;
  final bonuses = db.raceBonuses
      .where((row) => row.raw['Race ID'] == raceId && row.raw['Status'] != 'Needs Data')
      .map((row) => row.raw);
  return _matchingBonusPercent(bonuses, bonusType, referenceId);
}

num religionSkillDropChanceBonusPercent(GameDatabase db, PlayerSave save, String skillId) {
  return _totalReligionBonusPercent(db, save.religionId, 'skill_drop_chance_percent', skillId);
}

num religionMaxHpMultiplier(GameDatabase db, PlayerSave save) {
  return 1 + _totalReligionBonusPercent(db, save.religionId, 'max_hp_percent') / 100;
}

num religionGoldGainMultiplier(GameDatabase db, PlayerSave save) {
  return 1 + _totalReligionBonusPercent(db, save.religionId, 'gold_gain_percent') / 100;
}

/// Faith bonus if a faith is chosen, otherwise the race bonus. Never both.
num alignmentSkillDropChanceBonusPercent(GameDatabase db, PlayerSave save, String skillId) {
  if (isNotBlank(save.religionId)) {
    return religionSkillDropChanceBonusPercent(db, save, skillId);
  }
  return _totalRaceBonusPercent(db, save.raceId, 'skill_drop_chance_percent', skillId);
}

num alignmentMaxHpMultiplier(GameDatabase db, PlayerSave save) {
  if (isNotBlank(save.religionId)) return religionMaxHpMultiplier(db, save);
  return 1 + _totalRaceBonusPercent(db, save.raceId, 'max_hp_percent') / 100;
}

num alignmentGoldGainMultiplier(GameDatabase db, PlayerSave save) {
  if (isNotBlank(save.religionId)) return religionGoldGainMultiplier(db, save);
  return 1 + _totalRaceBonusPercent(db, save.raceId, 'gold_gain_percent') / 100;
}

num applyAlignmentGoldGain(GameDatabase db, PlayerSave save, num baseGold) {
  final amount = math.max(0, jsNumberOrZero(baseGold));
  if (amount <= 0) return 0;
  return (amount * alignmentGoldGainMultiplier(db, save)).floor();
}

List<String> religionBonusSummaryLines(GameDatabase db, String religionId) {
  final lines = <String>[];
  for (final bonus in religionBonusesFor(db, religionId)) {
    final value = jsNumber(bonus.raw['Bonus Value'] ?? 0);
    if (!value.isFinite || value == 0) continue;
    final amount = jsNumberToString(value);
    final bonusType = bonus.raw['Bonus Type'];
    final reference = bonus.raw['Reference ID'];
    if (bonusType == 'skill_drop_chance_percent' && reference is String && reference.isNotEmpty) {
      final displayName = db.skills
          .firstWhereOrNull((row) => row.raw['Skill ID'] == reference)
          ?.raw['Display Name'];
      lines.add('+$amount% ${displayName is String ? displayName : 'skill'} drop chance');
      continue;
    }
    if (bonusType == 'max_hp_percent') {
      lines.add('+$amount% maximum HP');
      continue;
    }
    if (bonusType == 'gold_gain_percent') {
      lines.add('+$amount% gold from enemies and actions');
    }
  }
  return lines;
}

String religionChooseLocationId(GameDatabase db) {
  return configString(db, religionChooseLocationIdKey, templeLocationIdFallback);
}

num religionChangeCooldownMs(GameDatabase db) {
  return configNumber(db, religionChangeCooldownMsKey, religionChangeCooldownMsFallback);
}

bool religionChooseUnlocked(PlayerSave save) {
  return totalLevel(save) >= religionChooseTotalLevel;
}

/// PLACEHOLDER linear formula for Economy to replace.
///
/// First pick (no current faith) is free; later changes cost
/// `religion_change_gold_per_total_level × total level`, floored.
num religionChangeGoldCost(GameDatabase db, PlayerSave save) {
  if (isBlank(save.religionId)) return 0;
  final perLevel = configNumber(
    db,
    religionChangeGoldPerTotalLevelKey,
    religionChangeGoldPerTotalLevelFallback,
  );
  return math.max(0, (perLevel * totalLevel(save)).floor());
}

num? religionChangeReadyAt(GameDatabase db, PlayerSave save) {
  final stamp = save.religionChangedAt;
  if (stamp == null) return null;
  final at = jsNumber(stamp);
  if (!at.isFinite) return null;
  return at + religionChangeCooldownMs(db);
}

String? religionIdForTitleCosmetic(GameDatabase db, String? cosmeticId) {
  if (isBlank(cosmeticId)) return null;
  final row = db.religions.firstWhereOrNull(
    (entry) => entry.raw['Title Cosmetic ID'] == cosmeticId,
  );
  final id = row?.raw['Religion ID'];
  return id is String ? id : null;
}

/// Faith titles stay owned after a switch but can only be equipped while following that faith.
bool isFaithTitleLocked(GameDatabase db, PlayerSave save, String? cosmeticId) {
  final faithId = religionIdForTitleCosmetic(db, cosmeticId);
  if (faithId == null) return false;
  return save.religionId != faithId;
}
