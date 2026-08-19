import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../activity/held_action.dart';
import '../activity/rewards.dart';
import '../activity/xp.dart';
import '../bounties/progress.dart';
import '../config.dart';
import '../js_compat.dart';
import '../potions/effects.dart';
import '../projects/enchantments.dart';
import '../quests/progress.dart';
import '../races/races.dart';
import '../rng/mulberry32.dart';
import '../cosmetics/cosmetics.dart';
import '../save/generated/save_models.dart';
import '../time.dart';
import 'food.dart';
import 'stats.dart';

/// One resolved round of combat.
class CombatRoundResult {
  const CombatRoundResult({
    required this.playerHit,
    required this.playerCrit,
    required this.offhandHit,
    required this.enemyHit,
    required this.thornsHit,
    required this.enemyHp,
    required this.playerHp,
    required this.outcome,
  });

  final num playerHit;

  /// True when this round's main-hand hit was a critical strike.
  final bool playerCrit;

  /// Off-hand dagger hit this round, or null when none / skipped.
  final num? offhandHit;
  final num? enemyHit;

  /// Damage reflected back at the enemy this round via armor enchantments (e.g. Thorns).
  final num thornsHit;
  final num enemyHp;
  final num playerHp;

  /// One of `ongoing`, `victory`, `defeat`.
  final String outcome;

  Map<String, Object?> toJson() => <String, Object?>{
    'playerHit': playerHit,
    'playerCrit': playerCrit,
    'offhandHit': offhandHit,
    'enemyHit': enemyHit,
    'thornsHit': thornsHit,
    'enemyHp': enemyHp,
    'playerHp': playerHp,
    'outcome': outcome,
  };
}

class CombatVictoryResult {
  const CombatVictoryResult({
    required this.save,
    required this.xpGained,
    required this.goldGained,
    required this.loot,
    required this.foodConsumed,
    required this.foodHealed,
    required this.foodName,
  });

  final PlayerSave save;
  final num xpGained;
  final num goldGained;
  final List<LootGrant> loot;
  final bool foodConsumed;
  final num foodHealed;
  final String? foodName;
}

EnemyRow? getEnemy(GameDatabase db, String enemyId) {
  return db.enemies.firstWhereOrNull((row) => row.raw['Enemy ID'] == enemyId);
}

EnemyRow? enemyForAction(GameDatabase db, ActionRow action) {
  final targetId = action.raw['Target ID'];
  if (action.raw['Category'] != 'Combat' || targetId is! String || targetId.isEmpty) {
    return null;
  }
  return getEnemy(db, targetId);
}

PlayerSave beginCombatSave(
  GameDatabase db,
  PlayerSave save,
  ActionRow action,
  EnemyRow enemy,
  String nowIso,
) {
  final potion = tryConsumePotionForScope(db, save, 'one_combat_encounter');
  final enemyMaxHp = jsNumber(enemy.raw['Maximum HP']);
  final poisonDamage = potionEnemyMaxHpDamage(enemyMaxHp, potion.effect);
  return potion.save.copyWith(
    currentActionId: action.raw['Action ID'] as String?,
    actionStartedAt: nowIso,
    actionDurationMs: null,
    combatEnemyId: enemy.raw['Enemy ID'] as String?,
    combatEnemyHp: math.max(0, enemyMaxHp - poisonDamage),
    combatRoundStartedAt: nowIso,
    activePotionEffect: potion.effect,
    deathPauseUntil: null,
  );
}

PlayerSave clearCombatSave(PlayerSave save) {
  return save.copyWith(
    combatEnemyId: null,
    combatEnemyHp: null,
    combatRoundStartedAt: null,
    activePotionEffect: save.activePotionEffect?.scope == 'one_combat_encounter'
        ? null
        : save.activePotionEffect,
  );
}

CombatRoundResult resolveCombatRound(
  GameDatabase db,
  PlayerSave save,
  EnemyRow enemy,
  num enemyHp,
  RandomFn random,
) {
  final floor = configNumber(db, 'damage_floor', 1);
  final playerRange = playerDamageRange(db, save);
  var playerHit = rollDamage(playerRange.min, playerRange.max, random);
  var playerCrit = false;
  final critChance = equippedEnchantmentCritChancePercent(db, save);
  if (critChance > 0 && random() * 100 < critChance) {
    playerCrit = true;
    playerHit = math.max(1, (playerHit * criticalStrikeDamageMultiplier()).floor());
  }
  var nextEnemyHp = math.max(0, enemyHp - playerHit);

  // Off-hand dagger swings after the main-hand hit if the enemy is still up.
  // Off-hand cannot crit; shared enchant/spell bonuses are already in its range.
  num? offhandHit;
  if (nextEnemyHp > 0) {
    final offhandRange = playerOffhandDamageRange(db, save);
    if (offhandRange != null) {
      offhandHit = rollDamage(offhandRange.min, offhandRange.max, random);
      nextEnemyHp = math.max(0, nextEnemyHp - offhandHit);
    }
  }

  if (nextEnemyHp <= 0) {
    return CombatRoundResult(
      playerHit: playerHit,
      playerCrit: playerCrit,
      offhandHit: offhandHit,
      enemyHit: null,
      thornsHit: 0,
      enemyHp: 0,
      playerHp: save.currentHp,
      outcome: 'victory',
    );
  }

  final enemyRaw = rollDamage(
    jsNumber(enemy.raw['Min Damage']),
    jsNumber(enemy.raw['Max Damage']),
    random,
  );
  final enemyHit = applyMitigation(enemyRaw, playerDamageReduction(db, save), floor);
  final playerHp = math.max(0, save.currentHp - enemyHit);

  final thornsPercent = equippedEnchantmentThornsPercent(db, save);
  final thornsHit = thornsPercent > 0 ? (enemyHit * thornsPercent / 100).round() : 0;
  if (thornsHit > 0) {
    nextEnemyHp = math.max(0, nextEnemyHp - thornsHit);
  }

  return CombatRoundResult(
    playerHit: playerHit,
    playerCrit: playerCrit,
    offhandHit: offhandHit,
    enemyHit: enemyHit,
    thornsHit: thornsHit,
    enemyHp: nextEnemyHp,
    playerHp: playerHp,
    // Simultaneous kills favor defeat: the enemy's own hit must land before Thorns reflects it.
    outcome: playerHp <= 0
        ? 'defeat'
        : nextEnemyHp <= 0
        ? 'victory'
        : 'ongoing',
  );
}

CombatVictoryResult applyCombatVictory(
  GameDatabase db,
  PlayerSave save,
  ActionRow action,
  EnemyRow enemy,
  RandomFn random,
  num nowMs,
) {
  final maxHp = playerMaxHp(db, save);
  var next = save.copyWith(maxHp: maxHp, currentHp: math.min(save.currentHp, maxHp));

  final xpAmount = jsNumber(enemy.raw['Combat XP'] ?? action.raw['XP Reward'] ?? 0);
  next = applyXp(next, db, combatSkillId, xpAmount).save;

  final minGold = jsNumber(enemy.raw['Minimum Gold'] ?? 0);
  final maxGold = jsNumber(enemy.raw['Maximum Gold'] ?? minGold);
  final goldRoll = maxGold > minGold
      ? minGold + (random() * (maxGold - minGold + 1)).floor()
      : minGold;

  // Use action reward table / drop chance (aligned with enemy table in data).
  final rewarded = resolveActionRewards(db, next, action, random);
  next = rewarded.save;
  var goldGained = rewarded.goldGained;
  if (goldRoll > 0) {
    final racedGold = applyRaceGoldGain(db, save, goldRoll);
    next = next.copyWith(gold: next.gold + racedGold);
    goldGained += racedGold;
  }

  next = next.copyWith(
    statistics: PlayerStatistics(
      values: <String, num>{
        ...next.statistics.values,
        'monsters_killed': (next.statistics.values['monsters_killed'] ?? 0) + 1,
        'gold_earned': (next.statistics.values['gold_earned'] ?? 0) + goldGained,
      },
    ),
  );

  final food = tryConsumeFoodAfterVictory(db, next);
  next = clearCombatSave(food.save);
  next = applyQuestDefeatProgress(db, next, jsString(enemy.raw['Enemy ID']), 1);
  next = applyBountyDefeatProgress(next, jsString(enemy.raw['Enemy ID']), 1, nowMs);
  next = withoutHeldAction(next, save.currentActivityId);

  return CombatVictoryResult(
    save: next,
    xpGained: xpAmount,
    goldGained: goldGained,
    loot: rewarded.loot,
    foodConsumed: food.consumed,
    foodHealed: food.healed,
    foodName: food.foodName,
  );
}

PlayerSave applyCombatDefeat(GameDatabase db, PlayerSave save, num nowMs) {
  final pauseSec = configNumber(db, 'death_pause', 30);
  final maxHp = playerMaxHp(db, save);
  return withoutHeldAction(
    clearCombatSave(
      revokeCosmetic(
        save.copyWith(
          maxHp: maxHp,
          currentHp: maxHp,
          deathPauseUntil: isoFromMs(nowMs + pauseSec * 1000),
          hasEverDied: true,
          currentActionId: null,
          actionStartedAt: null,
          actionDurationMs: null,
        ),
        starterTitleCosmeticId,
      ),
    ),
    save.currentActivityId,
  );
}

bool isDeathPaused(PlayerSave save, num nowMs) {
  if (isBlank(save.deathPauseUntil)) return false;
  return jsDateParse(save.deathPauseUntil) > nowMs;
}

num deathPauseRemainingMs(PlayerSave save, num nowMs) {
  if (isBlank(save.deathPauseUntil)) return 0;
  return math.max(0, jsDateParse(save.deathPauseUntil) - nowMs);
}
