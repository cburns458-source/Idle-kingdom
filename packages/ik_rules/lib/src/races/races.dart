import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../inventory/add_items.dart';
import '../js_compat.dart';
import '../save/generated/save_models.dart';

List<String> _parseIdList(Object? raw) {
  if (raw is! String || raw.trim().isEmpty) return const <String>[];
  return raw
      .split(';')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
}

/// Races in display order.
///
/// `mergeSort` rather than `List.sort`, because rows that tie on both keys must
/// keep their database order the way JavaScript's stable sort leaves them.
List<RaceRow> races(GameDatabase db) {
  final rows = [...db.races];
  mergeSort<RaceRow>(
    rows,
    compare: (a, b) => jsCompareThen(
      jsNumber(a.raw['Sort Order'] ?? 0) - jsNumber(b.raw['Sort Order'] ?? 0),
      () => jsLocaleCompare(jsString(a.raw['Display Name']), jsString(b.raw['Display Name'])),
    ),
  );
  return rows;
}

RaceRow? raceById(GameDatabase db, String? raceId) {
  if (isBlank(raceId)) return null;
  return db.races.firstWhereOrNull((row) => row.raw['Race ID'] == raceId);
}

String? raceDisplayName(GameDatabase db, String? raceId) {
  final displayName = raceById(db, raceId)?.raw['Display Name'];
  return displayName is String ? displayName : null;
}

List<RaceBonusRow> raceBonusesFor(GameDatabase db, String? raceId) {
  if (isBlank(raceId)) return const <RaceBonusRow>[];
  return db.raceBonuses
      .where((row) => row.raw['Race ID'] == raceId && row.raw['Status'] != 'Needs Data')
      .toList();
}

List<RaceStartingItemRow> raceStartingItems(GameDatabase db, String raceId) {
  final rows = db.raceStartingItems.where((row) => row.raw['Race ID'] == raceId).toList();
  mergeSort<RaceStartingItemRow>(
    rows,
    compare: (a, b) => jsCompareThen(
      jsNumber(a.raw['Sort Order'] ?? 0) - jsNumber(b.raw['Sort Order'] ?? 0),
      () => jsLocaleCompare(
        jsString(a.raw['Race Starting Item ID']),
        jsString(b.raw['Race Starting Item ID']),
      ),
    ),
  );
  return rows;
}

/// Sum of matching percent bonuses (e.g. two +5 rows → 10).
num _totalBonusPercent(GameDatabase db, PlayerSave save, String bonusType, [String? referenceId]) {
  num total = 0;
  for (final bonus in raceBonusesFor(db, save.raceId)) {
    if (bonus.raw['Bonus Type'] != bonusType) continue;
    final rowReference = bonus.raw['Reference ID'];
    if (referenceId != null && rowReference != referenceId) continue;
    if (referenceId == null && rowReference != null) continue;
    final value = jsNumber(bonus.raw['Bonus Value'] ?? 0);
    if (value.isFinite) total += value;
  }
  return total;
}

num raceSkillXpMultiplier(GameDatabase db, PlayerSave save, String skillId) {
  return 1 + _totalBonusPercent(db, save, 'skill_xp_percent', skillId) / 100;
}

num raceCombatDamageMultiplier(GameDatabase db, PlayerSave save) {
  return 1 + _totalBonusPercent(db, save, 'combat_damage_percent') / 100;
}

num raceMaxHpMultiplier(GameDatabase db, PlayerSave save) {
  return 1 + _totalBonusPercent(db, save, 'max_hp_percent') / 100;
}

num raceGoldGainMultiplier(GameDatabase db, PlayerSave save) {
  return 1 + _totalBonusPercent(db, save, 'gold_gain_percent') / 100;
}

/// Applies race skill XP percent (floored).
num applyRaceSkillXp(GameDatabase db, PlayerSave save, String skillId, num baseXp) {
  final amount = math.max(0, jsNumberOrZero(baseXp));
  if (amount <= 0) return 0;
  return (amount * raceSkillXpMultiplier(db, save, skillId)).floor();
}

/// Applies race gold percent (floored).
num applyRaceGoldGain(GameDatabase db, PlayerSave save, num baseGold) {
  final amount = math.max(0, jsNumberOrZero(baseGold));
  if (amount <= 0) return 0;
  return (amount * raceGoldGainMultiplier(db, save)).floor();
}

bool raceBypassesForcedHostilityAt(GameDatabase db, PlayerSave save, String locationId) {
  final race = raceById(db, save.raceId);
  if (race == null) return false;
  return _parseIdList(race.raw['Hostility Immunity Location IDs']).contains(locationId);
}

List<String> raceBonusSummaryLines(GameDatabase db, String raceId) {
  final lines = <String>[];
  for (final bonus in raceBonusesFor(db, raceId)) {
    final value = jsNumber(bonus.raw['Bonus Value'] ?? 0);
    if (!value.isFinite || value == 0) continue;
    final amount = jsNumberToString(value);
    final bonusType = bonus.raw['Bonus Type'];
    final reference = bonus.raw['Reference ID'];
    if (bonusType == 'skill_xp_percent' && reference is String && reference.isNotEmpty) {
      final displayName = db.skills
          .firstWhereOrNull((row) => row.raw['Skill ID'] == reference)
          ?.raw['Display Name'];
      lines.add('+$amount% ${displayName is String ? displayName : 'skill'} XP');
      continue;
    }
    if (bonusType == 'max_hp_percent') {
      lines.add('+$amount% maximum HP');
      continue;
    }
    if (bonusType == 'combat_damage_percent') {
      lines.add('+$amount% combat damage');
      continue;
    }
    if (bonusType == 'gold_gain_percent') {
      lines.add('+$amount% gold gains');
    }
  }
  final race = raceById(db, raceId);
  for (final locationId in _parseIdList(race?.raw['Hostility Immunity Location IDs'])) {
    final displayName = db.locations
        .firstWhereOrNull((row) => row.raw['Location ID'] == locationId)
        ?.raw['Display Name'];
    lines.add(
      'Welcome at ${displayName is String ? displayName : locationId} '
      '(no forced hostility)',
    );
  }
  return lines;
}

/// Grants a race's starting item kit.
///
/// Idempotent only in the sense that callers should invoke this when first
/// selecting a race (not on every race change).
PlayerSave grantRaceStartingItems(GameDatabase db, PlayerSave save, String raceId) {
  var next = save;
  for (final row in raceStartingItems(db, raceId)) {
    final qty = math.max(0, jsNumberOrZero(row.raw['Quantity']).floor());
    if (qty <= 0) continue;
    next = addItemToInventory(next, jsString(row.raw['Item ID']), qty);
  }
  return next;
}
