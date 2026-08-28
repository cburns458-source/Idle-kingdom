import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../achievements/progress.dart';
import '../activity/held_action.dart';
import '../activity/rewards.dart';
import '../activity/xp.dart';
import '../equipment/loadout.dart';
import '../equipment/vitals.dart';
import '../npcs/knowledge.dart';
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
import 'boss.dart';
import 'food.dart';
import 'stats.dart';

/// One resolved round of combat.
class CombatRoundResult {
  const CombatRoundResult({
    required this.playerHit,
    required this.playerCrit,
    required this.offhandHit,
    required this.staffHit,
    required this.skipNextEnemyAttack,
    required this.enemyHit,
    required this.thornsHit,
    required this.bossSleepRoundsRemaining,
    required this.enemyAsleep,
    required this.enemyRampage,
    required this.enemyHp,
    required this.playerHp,
    required this.outcome,
  });

  final num playerHit;

  /// True when this round's main-hand hit was a critical strike.
  final bool playerCrit;

  /// Off-hand dagger hit this round, or null when none / skipped.
  final num? offhandHit;

  /// Staff of Sparks extra hit this round, or null when none / skipped.
  final num? staffHit;

  /// Persist Binding: skip the enemy's next attack.
  final bool skipNextEnemyAttack;
  final num? enemyHit;

  /// Damage reflected back at the enemy this round via armor enchantments (e.g. Thorns).
  final num thornsHit;

  /// Remaining boss sleep rounds after this one, or null when the enemy is not a boss.
  final num? bossSleepRoundsRemaining;

  /// True when this enemy started the round asleep.
  final bool enemyAsleep;

  /// True when the enemy's landing swing was a rampage hit.
  final bool enemyRampage;
  final num enemyHp;
  final num playerHp;

  /// One of `ongoing`, `victory`, `defeat`.
  final String outcome;

  Map<String, Object?> toJson() => <String, Object?>{
    'playerHit': playerHit,
    'playerCrit': playerCrit,
    'offhandHit': offhandHit,
    'staffHit': staffHit,
    'skipNextEnemyAttack': skipNextEnemyAttack,
    'enemyHit': enemyHit,
    'thornsHit': thornsHit,
    'bossSleepRoundsRemaining': bossSleepRoundsRemaining,
    'enemyAsleep': enemyAsleep,
    'enemyRampage': enemyRampage,
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
  return potion.save.copyWith(
    currentActionId: action.raw['Action ID'] as String?,
    actionStartedAt: nowIso,
    actionDurationMs: null,
    combatEnemyId: enemy.raw['Enemy ID'] as String?,
    combatEnemyHp: enemyMaxHp,
    combatRoundStartedAt: nowIso,
    combatSkipEnemyAttack: false,
    combatBossSleepRoundsRemaining: bossProfile(enemy)?.sleepStart,
    activePotionEffect: potion.effect,
    deathPauseUntil: null,
  );
}

PlayerSave clearCombatSave(PlayerSave save) {
  return save.copyWith(
    combatEnemyId: null,
    combatEnemyHp: null,
    combatRoundStartedAt: null,
    combatSkipEnemyAttack: false,
    combatBossSleepRoundsRemaining: null,
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
  final profile = bossProfile(enemy);
  final asleep = (save.combatBossSleepRoundsRemaining ?? 0) > 0;
  final playerRange = playerDamageRange(db, save);
  var playerHit = rollDamage(playerRange.min, playerRange.max, random);
  var playerCrit = false;
  final critChance = equippedEnchantmentCritChancePercent(db, save);
  if (critChance > 0 && random() * 100 < critChance) {
    playerCrit = true;
    playerHit = math.max(1, (playerHit * criticalStrikeDamageMultiplier()).floor());
  }
  playerHit = applySleepIncoming(playerHit, asleep);
  var nextEnemyHp = math.max(0, enemyHp - playerHit);
  final weaponId = save.equipment.slots[weaponToolSlotId]?.itemId;

  // Staff of Sparks: a second blue hit after the main swing if the enemy is still up.
  // No crit and no Strength / combat / potion / race multipliers — Arcana level only.
  num? staffHit;
  if (nextEnemyHp > 0 && isNotBlank(weaponId) && itemHasCapability(db, weaponId!, 'staff_sparks')) {
    final sparks = staffSparksDamageRange(getSkillProgress(save, arcanaSkillId).level);
    staffHit = applySleepIncoming(rollDamage(sparks.min, sparks.max, random), asleep);
    nextEnemyHp = math.max(0, nextEnemyHp - staffHit);
  }

  // Off-hand dagger swings after the main-hand hit if the enemy is still up.
  // Two-handers never keep an off-hand dagger, so this stays null for staves.
  // Off-hand cannot crit; shared enchant/spell bonuses are already in its range.
  num? offhandHit;
  if (nextEnemyHp > 0) {
    final offhandRange = playerOffhandDamageRange(db, save);
    if (offhandRange != null) {
      offhandHit = applySleepIncoming(
        rollDamage(offhandRange.min, offhandRange.max, random),
        asleep,
      );
      nextEnemyHp = math.max(0, nextEnemyHp - offhandHit);
    }
  }

  if (nextEnemyHp > 0) {
    nextEnemyHp = applyPotionEnemyRoundDamage(
      nextEnemyHp,
      jsNumber(enemy.raw['Maximum HP']),
      save.activePotionEffect,
    );
  }

  // Binding procs on this hit: they still attack this round, then skip the next.
  var skipNextEnemyAttack = false;
  if (nextEnemyHp > 0 &&
      isNotBlank(weaponId) &&
      itemHasCapability(db, weaponId!, 'staff_binding')) {
    skipNextEnemyAttack = random() < 0.5;
  }

  num? nextSleep = profile == null ? null : (save.combatBossSleepRoundsRemaining ?? 0);
  if (nextSleep != null && nextSleep > 0) nextSleep = nextSleep - 1;
  if (profile != null && nextEnemyHp <= jsNumber(enemy.raw['Maximum HP']) * profile.wakeHpRatio) {
    nextSleep = 0;
  }

  if (nextEnemyHp <= 0) {
    return CombatRoundResult(
      playerHit: playerHit,
      playerCrit: playerCrit,
      offhandHit: offhandHit,
      staffHit: staffHit,
      skipNextEnemyAttack: false,
      enemyHit: null,
      thornsHit: 0,
      bossSleepRoundsRemaining: nextSleep,
      enemyAsleep: asleep,
      enemyRampage: false,
      enemyHp: 0,
      playerHp: save.currentHp,
      outcome: 'victory',
    );
  }

  if (save.combatSkipEnemyAttack || asleep) {
    return CombatRoundResult(
      playerHit: playerHit,
      playerCrit: playerCrit,
      offhandHit: offhandHit,
      staffHit: staffHit,
      skipNextEnemyAttack: skipNextEnemyAttack,
      enemyHit: null,
      thornsHit: 0,
      bossSleepRoundsRemaining: nextSleep,
      enemyAsleep: asleep,
      enemyRampage: false,
      enemyHp: nextEnemyHp,
      playerHp: save.currentHp,
      outcome: 'ongoing',
    );
  }

  final rampage =
      profile != null && nextEnemyHp <= jsNumber(enemy.raw['Maximum HP']) * profile.rampageHpRatio;
  var enemyRaw = rollDamage(
    jsNumber(enemy.raw['Min Damage']),
    jsNumber(enemy.raw['Max Damage']),
    random,
  );
  if (rampage) enemyRaw *= 2;
  final enemyHit = applyMitigation(enemyRaw, playerDamageReduction(db, save), floor);
  final playerHp = math.max(0, save.currentHp - enemyHit);

  final thornsPercent = equippedEnchantmentThornsPercent(db, save);
  num thornsHit = thornsPercent > 0 ? (enemyHit * thornsPercent / 100).round() : 0;
  thornsHit = applySleepIncoming(thornsHit, asleep);
  if (thornsHit > 0) {
    nextEnemyHp = math.max(0, nextEnemyHp - thornsHit);
  }

  return CombatRoundResult(
    playerHit: playerHit,
    playerCrit: playerCrit,
    offhandHit: offhandHit,
    staffHit: staffHit,
    skipNextEnemyAttack: skipNextEnemyAttack,
    enemyHit: enemyHit,
    thornsHit: thornsHit,
    bossSleepRoundsRemaining: nextSleep,
    enemyAsleep: asleep,
    enemyRampage: rampage,
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
  var next = save.copyWith(
    maxHp: maxHp,
    currentHp: currentHpAfterMaxChange(save.currentHp, save.maxHp, maxHp),
  );

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
  next = recordEnemyKill(db, next, jsString(enemy.raw['Enemy ID']));

  final food = consumeFoodAfterVictory(db, next);
  next = withBossRespawn(clearCombatSave(food.save), enemy, nowMs);
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
