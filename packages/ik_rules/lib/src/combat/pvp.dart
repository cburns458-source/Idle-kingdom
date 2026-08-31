import 'dart:math' as math;

import 'package:ik_content/ik_content.dart';

import '../config.dart';
import '../projects/enchantments.dart';
import '../rng/mulberry32.dart';
import '../save/generated/save_models.dart';
import 'stats.dart';

class PvpRoundResult {
  const PvpRoundResult({
    required this.youHit,
    required this.youCrit,
    required this.youOffhand,
    required this.themHit,
    required this.themCrit,
    required this.themOffhand,
    required this.youThorns,
    required this.themThorns,
    required this.youHp,
    required this.themHp,
    required this.outcome,
  });

  final num youHit;
  final bool youCrit;
  final num? youOffhand;
  final num? themHit;
  final bool themCrit;
  final num? themOffhand;
  final num youThorns;
  final num themThorns;
  final num youHp;
  final num themHp;

  /// One of `ongoing`, `win`, `loss`.
  final String outcome;

  Map<String, Object?> toJson() => <String, Object?>{
    'youHit': youHit,
    'youCrit': youCrit,
    'youOffhand': youOffhand,
    'themHit': themHit,
    'themCrit': themCrit,
    'themOffhand': themOffhand,
    'youThorns': youThorns,
    'themThorns': themThorns,
    'youHp': youHp,
    'themHp': themHp,
    'outcome': outcome,
  };
}

class PvpFightResult {
  const PvpFightResult({
    required this.rounds,
    required this.outcome,
    required this.youMaxHp,
    required this.themMaxHp,
  });

  final List<PvpRoundResult> rounds;
  final String outcome;
  final num youMaxHp;
  final num themMaxHp;

  Map<String, Object?> toJson() => <String, Object?>{
    'rounds': rounds.map((round) => round.toJson()).toList(),
    'outcome': outcome,
    'youMaxHp': youMaxHp,
    'themMaxHp': themMaxHp,
  };
}

class _StrikeResult {
  const _StrikeResult({
    required this.hit,
    required this.crit,
    required this.offhand,
    required this.hp,
    required this.dealt,
  });

  final num hit;
  final bool crit;
  final num? offhand;
  final num hp;
  final num dealt;
}

const int _maxPvpRounds = 2000;

_StrikeResult _strike(
  GameDatabase db,
  PlayerSave attacker,
  num defenderHp,
  num defenderDr,
  num floor,
  RandomFn random,
) {
  final range = playerDamageRange(db, attacker);
  var hit = rollDamage(range.min, range.max, random);
  var crit = false;
  final critChance = equippedEnchantmentCritChancePercent(db, attacker);
  if (critChance > 0 && random() * 100 < critChance) {
    crit = true;
    hit = math.max(1, (hit * criticalStrikeDamageMultiplier()).floor());
  }
  hit = applyMitigation(hit, defenderDr, floor);
  var hp = math.max(0, defenderHp - hit);
  num? offhand;
  if (hp > 0) {
    final offhandRange = playerOffhandDamageRange(db, attacker);
    if (offhandRange != null) {
      offhand = applyMitigation(
        rollDamage(offhandRange.min, offhandRange.max, random),
        defenderDr,
        floor,
      );
      hp = math.max(0, hp - offhand);
    }
  }
  return _StrikeResult(hit: hit, crit: crit, offhand: offhand, hp: hp, dealt: hit + (offhand ?? 0));
}

num _thornsFrom(num dealt, num percent) {
  if (percent <= 0 || dealt <= 0) return 0;
  return (dealt * percent / 100).round();
}

/// Why a fight is refused when the player has not published a loadout.
const String pvpEquipmentRequired = 'Save equipment first.';

/// Keeps snapshot gear and copies live combat, race, and look onto it.
PlayerSave overlayPvpLiveStats(PlayerSave snapshot, PlayerSave live) {
  return snapshot.copyWith(
    skills: live.skills,
    raceId: live.raceId,
    appearance: live.appearance,
    characterName: live.characterName,
  );
}

/// Saved loadout plus the live character: gear from [loadout], combat and race
/// from [live]. Full HP, no potions.
PlayerSave composePvpFighter(GameDatabase db, PlayerSave live, PlayerSave loadout) {
  return preparePvpFighter(db, live.copyWith(equipment: loadout.equipment));
}

/// Snapshot PvP: the given save, at full HP, with potions stripped.
PlayerSave preparePvpFighter(GameDatabase db, PlayerSave save) {
  final maxHp = playerMaxHp(db, save);
  return save.copyWith(
    maxHp: maxHp,
    currentHp: maxHp,
    activePotionEffect: null,
    combatEnemyId: null,
    combatEnemyHp: null,
    combatRoundStartedAt: null,
    combatSkipEnemyAttack: false,
    combatBossSleepRoundsRemaining: null,
    combatBossPendingId: null,
    combatBossPendingHp: null,
    combatBossAddsRemaining: null,
    combatBossAddsTriggered: false,
    combatBossInkActive: false,
  );
}

PvpRoundResult resolvePvpRound(
  GameDatabase db,
  PlayerSave you,
  PlayerSave them,
  num youHp,
  num themHp,
  RandomFn random,
) {
  final floor = configNumber(db, 'damage_floor', 1);
  final youDr = playerDamageReduction(db, you);
  final themDr = playerDamageReduction(db, them);

  final yourSwing = _strike(db, you, themHp, themDr, floor, random);
  var nextThemHp = yourSwing.hp;
  final themThorns = _thornsFrom(yourSwing.dealt, equippedEnchantmentThornsPercent(db, them));
  var nextYouHp = math.max(0, youHp - themThorns);

  if (nextYouHp <= 0) {
    return PvpRoundResult(
      youHit: yourSwing.hit,
      youCrit: yourSwing.crit,
      youOffhand: yourSwing.offhand,
      themHit: null,
      themCrit: false,
      themOffhand: null,
      youThorns: 0,
      themThorns: themThorns,
      youHp: 0,
      themHp: nextThemHp,
      outcome: 'loss',
    );
  }
  if (nextThemHp <= 0) {
    return PvpRoundResult(
      youHit: yourSwing.hit,
      youCrit: yourSwing.crit,
      youOffhand: yourSwing.offhand,
      themHit: null,
      themCrit: false,
      themOffhand: null,
      youThorns: 0,
      themThorns: themThorns,
      youHp: nextYouHp,
      themHp: 0,
      outcome: 'win',
    );
  }

  final theirSwing = _strike(db, them, nextYouHp, youDr, floor, random);
  nextYouHp = theirSwing.hp;
  final youThorns = _thornsFrom(theirSwing.dealt, equippedEnchantmentThornsPercent(db, you));
  if (youThorns > 0) {
    nextThemHp = math.max(0, nextThemHp - youThorns);
  }

  return PvpRoundResult(
    youHit: yourSwing.hit,
    youCrit: yourSwing.crit,
    youOffhand: yourSwing.offhand,
    themHit: theirSwing.hit,
    themCrit: theirSwing.crit,
    themOffhand: theirSwing.offhand,
    youThorns: youThorns,
    themThorns: themThorns,
    youHp: nextYouHp,
    themHp: nextThemHp,
    outcome: nextYouHp <= 0
        ? 'loss'
        : nextThemHp <= 0
        ? 'win'
        : 'ongoing',
  );
}

PvpFightResult simulatePvpFight(
  GameDatabase db,
  PlayerSave youSave,
  PlayerSave themSave,
  RandomFn random,
) {
  final you = preparePvpFighter(db, youSave);
  final them = preparePvpFighter(db, themSave);
  final youMaxHp = you.currentHp;
  final themMaxHp = them.currentHp;
  final rounds = <PvpRoundResult>[];
  var youHp = youMaxHp;
  var themHp = themMaxHp;
  var outcome = 'loss';

  for (var i = 0; i < _maxPvpRounds; i++) {
    final round = resolvePvpRound(db, you, them, youHp, themHp, random);
    rounds.add(round);
    youHp = round.youHp;
    themHp = round.themHp;
    if (round.outcome != 'ongoing') {
      outcome = round.outcome;
      break;
    }
  }

  return PvpFightResult(rounds: rounds, outcome: outcome, youMaxHp: youMaxHp, themMaxHp: themMaxHp);
}
