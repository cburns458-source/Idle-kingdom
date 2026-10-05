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
import '../spells/spells.dart';
import '../time.dart';
import '../trackers/trackers.dart';
import 'boss.dart';
import '../skills/skill_actions.dart' show fishingSkillId;
import 'stats.dart';

/// One resolved round of combat.
class CombatRoundResult {
  const CombatRoundResult({
    required this.playerHit,
    required this.playerCrit,
    required this.offhandHit,
    required this.staffHit,
    required this.poisonHit,
    required this.skipNextEnemyAttack,
    required this.enemyHit,
    required this.thornsHit,
    required this.bossSleepRoundsRemaining,
    required this.enemyAsleep,
    required this.enemyRampage,
    required this.bossAddsTriggered,
    required this.bossInkActive,
    required this.bossPendingHp,
    required this.enemyHpAfterPlayer,
    required this.playerHpAfterPlayer,
    required this.enemyHp,
    required this.playerHp,
    required this.outcome,
    required this.lifestealHealed,
  });

  final num playerHit;

  /// True when this round's main-hand hit was a critical strike.
  final bool playerCrit;

  /// Off-hand dagger hit this round, or null when none / skipped.
  final num? offhandHit;

  /// Staff of Sparks extra hit this round, or null when none / skipped.
  final num? staffHit;

  /// Poison tick this round, including 0 when the effect is up but deals nothing.
  final num? poisonHit;

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

  /// True when this round triggered a boss add phase (e.g. squidlings).
  final bool bossAddsTriggered;

  /// True when ink halved player damage this round.
  final bool bossInkActive;

  /// HP to restore on the boss when adds finish. Set when bossAddsTriggered.
  final num? bossPendingHp;

  /// Enemy HP after the player's swing, before the enemy attacks.
  final num enemyHpAfterPlayer;

  /// Player HP after lifesteal, before the enemy attacks.
  final num playerHpAfterPlayer;
  final num enemyHp;
  final num playerHp;

  /// One of `ongoing`, `victory`, `defeat`.
  final String outcome;

  /// Uncapped lifesteal heal from damage dealt this round.
  final num lifestealHealed;

  Map<String, Object?> toJson() => <String, Object?>{
    'playerHit': playerHit,
    'playerCrit': playerCrit,
    'offhandHit': offhandHit,
    'staffHit': staffHit,
    'poisonHit': poisonHit,
    'skipNextEnemyAttack': skipNextEnemyAttack,
    'enemyHit': enemyHit,
    'thornsHit': thornsHit,
    'bossSleepRoundsRemaining': bossSleepRoundsRemaining,
    'enemyAsleep': enemyAsleep,
    'enemyRampage': enemyRampage,
    'bossAddsTriggered': bossAddsTriggered,
    'bossInkActive': bossInkActive,
    'bossPendingHp': bossPendingHp,
    'enemyHpAfterPlayer': enemyHpAfterPlayer,
    'playerHpAfterPlayer': playerHpAfterPlayer,
    'enemyHp': enemyHp,
    'playerHp': playerHp,
    'outcome': outcome,
    'lifestealHealed': lifestealHealed,
  };

  /// Persistable mid-round snapshot for the enemy/outcome phase.
  CombatPendingRound toPendingRound() => CombatPendingRound(
    playerHit: playerHit,
    playerCrit: playerCrit,
    offhandHit: offhandHit,
    staffHit: staffHit,
    poisonHit: poisonHit,
    skipNextEnemyAttack: skipNextEnemyAttack,
    enemyHit: enemyHit,
    thornsHit: thornsHit,
    bossSleepRoundsRemaining: bossSleepRoundsRemaining,
    enemyAsleep: enemyAsleep,
    enemyRampage: enemyRampage,
    bossAddsTriggered: bossAddsTriggered,
    bossInkActive: bossInkActive,
    bossPendingHp: bossPendingHp,
    enemyHpAfterPlayer: enemyHpAfterPlayer,
    playerHpAfterPlayer: playerHpAfterPlayer,
    enemyHp: enemyHp,
    playerHp: playerHp,
    outcome: outcome,
    lifestealHealed: lifestealHealed,
  );
}

class CombatVictoryResult {
  const CombatVictoryResult({
    required this.save,
    required this.xpGained,
    required this.xpSkillId,
    required this.xpAwards,
    required this.goldGained,
    required this.loot,
    this.cosmeticsGranted = const <ActionCosmeticGrant>[],
    required this.foodConsumed,
    required this.foodHealed,
    required this.foodName,
  });

  final PlayerSave save;
  final num xpGained;

  /// Primary skill for the XP toast (Fishing for Mother Squid; Might otherwise).
  final String xpSkillId;

  /// Every skill that received XP this victory (style split may list two).
  final List<({String skillId, num xp})> xpAwards;
  final num goldGained;
  final List<LootGrant> loot;
  final List<ActionCosmeticGrant> cosmeticsGranted;
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
  final enemyMaxHp = enemyEncounterMaxHp(db, potion.save, enemy);
  return potion.save.copyWith(
    currentActionId: action.raw['Action ID'] as String?,
    actionStartedAt: nowIso,
    actionDurationMs: null,
    combatEnemyId: enemy.raw['Enemy ID'] as String?,
    combatEnemyHp: enemyMaxHp,
    combatRoundStartedAt: nowIso,
    combatPlayerSwingApplied: false,
    combatPendingRound: null,
    combatEatUntil: null,
    combatContinueActivityAfterEat: false,
    combatSkipEnemyAttack: false,
    combatBossSleepRoundsRemaining: bossProfile(enemy)?.sleepStart,
    combatBossPendingId: null,
    combatBossPendingHp: null,
    combatBossAddsRemaining: null,
    combatBossAddsTriggered: false,
    combatBossInkActive: false,
    activePotionEffect: potion.effect ?? potion.save.activePotionEffect,
    deathPauseUntil: null,
  );
}

PlayerSave clearCombatSave(PlayerSave save) {
  return save.copyWith(
    combatEnemyId: null,
    combatEnemyHp: null,
    combatRoundStartedAt: null,
    combatManualEatRoundStartedAt: null,
    combatPlayerSwingApplied: false,
    combatPendingRound: null,
    combatEatUntil: null,
    combatContinueActivityAfterEat: false,
    combatSkipEnemyAttack: false,
    combatBossSleepRoundsRemaining: null,
    combatBossPendingId: null,
    combatBossPendingHp: null,
    combatBossAddsRemaining: null,
    combatBossAddsTriggered: false,
    combatBossInkActive: false,
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
  final enemyMaxHp = enemyEncounterMaxHp(db, save, enemy);
  final fishingMode = () {
    if (isBossAddFight(save) && save.combatBossPendingId != null) {
      return bossProfile(getEnemy(db, save.combatBossPendingId!))?.damageMode == 'fishing';
    }
    return profile?.damageMode == 'fishing';
  }();

  var bossInkActive = false;
  if (profile?.inkAt != null &&
      !isBossAddFight(save) &&
      enemyHp <= enemyMaxHp * profile!.inkAt! &&
      random() < profile.inkChance) {
    bossInkActive = true;
  }

  num playerHit = 0;
  var playerCrit = false;
  num? staffHit;
  num? offhandHit;
  num? poisonHit;
  final lockpickCombat = equippedWeaponIsLockpick(save);

  if (!lockpickCombat) {
    if (fishingMode) {
      final fishingRange = fishingCombatDamageRange(db, save);
      playerHit = rollDamage(fishingRange.min, fishingRange.max, random);
      if (bossInkActive) playerHit = math.max(1, (playerHit / 2).floor());
      playerHit = applySleepIncoming(playerHit, asleep);
    } else {
      final playerRange = playerDamageRange(db, save);
      playerHit = rollDamage(playerRange.min, playerRange.max, random);
      final critChance = equippedEnchantmentCritChancePercent(db, save);
      if (critChance > 0 && random() * 100 < critChance) {
        playerCrit = true;
        playerHit = math.max(1, (playerHit * criticalStrikeDamageMultiplier()).floor());
      }
      if (bossInkActive) playerHit = math.max(1, (playerHit / 2).floor());
      playerHit = applySleepIncoming(playerHit, asleep);
    }
    playerHit = applyEnemyDamageResistance(playerHit, enemy, floor);
  }

  var nextEnemyHp = math.max(0, enemyHp - playerHit);
  final weaponId = save.equipment.slots[weaponToolSlotId]?.itemId;

  // Double Shot: 50% chance for a second main-hand bow hit (no extra enemy swing).
  if (!lockpickCombat &&
      !fishingMode &&
      nextEnemyHp > 0 &&
      equippedEnchantmentHasDoubleShot(db, save) &&
      random() < 0.5) {
    final playerRange = playerDamageRange(db, save);
    var secondHit = rollDamage(playerRange.min, playerRange.max, random);
    final critChance = equippedEnchantmentCritChancePercent(db, save);
    if (critChance > 0 && random() * 100 < critChance) {
      playerCrit = true;
      secondHit = math.max(1, (secondHit * criticalStrikeDamageMultiplier()).floor());
    }
    if (bossInkActive) secondHit = math.max(1, (secondHit / 2).floor());
    secondHit = applySleepIncoming(secondHit, asleep);
    secondHit = applyEnemyDamageResistance(secondHit, enemy, floor);
    playerHit += secondHit;
    nextEnemyHp = math.max(0, nextEnemyHp - secondHit);
  }

  if (!lockpickCombat &&
      !fishingMode &&
      nextEnemyHp > 0 &&
      isNotBlank(weaponId) &&
      itemHasCapability(db, weaponId!, 'staff_sparks')) {
    final sparks = staffSparksDamageRange(getSkillProgress(save, arcanaSkillId).level);
    staffHit = applyEnemyDamageResistance(
      applySleepIncoming(rollDamage(sparks.min, sparks.max, random), asleep),
      enemy,
      floor,
    );
    nextEnemyHp = math.max(0, nextEnemyHp - staffHit);
  }

  // Lockpicks deal no main-hand damage; an off-hand dagger can still swing.
  if (!fishingMode && nextEnemyHp > 0) {
    final offhandRange = playerOffhandDamageRange(db, save);
    if (offhandRange != null) {
      offhandHit = applySleepIncoming(
        rollDamage(offhandRange.min, offhandRange.max, random),
        asleep,
      );
      if (bossInkActive) offhandHit = math.max(1, (offhandHit / 2).floor());
      offhandHit = applyEnemyDamageResistance(offhandHit, enemy, floor);
      nextEnemyHp = math.max(0, nextEnemyHp - offhandHit);
    }
  }

  final poisonPercent = save.activePotionEffect?.enemyMaxHpDamagePercent;
  if (poisonPercent != null && poisonPercent > 0) {
    if (lockpickCombat || nextEnemyHp <= 0) {
      poisonHit = 0;
    } else {
      final afterPoison = applyPotionEnemyRoundDamage(
        nextEnemyHp,
        enemyMaxHp,
        save.activePotionEffect,
      );
      poisonHit = nextEnemyHp - afterPoison;
      nextEnemyHp = afterPoison;
    }
  }

  var skipNextEnemyAttack = false;
  if (!lockpickCombat &&
      nextEnemyHp > 0 &&
      isNotBlank(weaponId) &&
      itemHasCapability(db, weaponId!, 'staff_binding')) {
    skipNextEnemyAttack = random() < 0.5;
  }

  num? nextSleep = profile == null ? null : (save.combatBossSleepRoundsRemaining ?? 0);
  if (nextSleep != null && nextSleep > 0) nextSleep = nextSleep - 1;
  if (profile != null && nextEnemyHp <= enemyMaxHp * profile.wakeHpRatio) {
    nextSleep = 0;
  }

  var bossAddsTriggered = false;
  num? bossPendingHp;
  if (profile?.squidlingsAt != null &&
      profile!.squidlingEnemyId != null &&
      !save.combatBossAddsTriggered &&
      !isBossAddFight(save) &&
      nextEnemyHp <= enemyMaxHp * profile.squidlingsAt!) {
    bossAddsTriggered = true;
    bossPendingHp = nextEnemyHp;
  }

  final damageDealt = playerHit + (offhandHit ?? 0) + (staffHit ?? 0);
  final lifestealHealed = lifestealHealAmount(db, save, damageDealt);
  final hpAfterLifesteal = _applyLifestealHeal(db, save, save.currentHp, damageDealt);
  final enemyHpAfterPlayer = nextEnemyHp;
  final playerHpAfterPlayer = hpAfterLifesteal;

  if (nextEnemyHp <= 0 && !bossAddsTriggered) {
    return CombatRoundResult(
      playerHit: playerHit,
      playerCrit: playerCrit,
      offhandHit: offhandHit,
      staffHit: staffHit,
      poisonHit: poisonHit,
      skipNextEnemyAttack: false,
      enemyHit: null,
      thornsHit: 0,
      bossSleepRoundsRemaining: nextSleep,
      enemyAsleep: asleep,
      enemyRampage: false,
      bossAddsTriggered: false,
      bossInkActive: bossInkActive,
      bossPendingHp: null,
      enemyHpAfterPlayer: enemyHpAfterPlayer,
      playerHpAfterPlayer: playerHpAfterPlayer,
      enemyHp: 0,
      playerHp: hpAfterLifesteal,
      outcome: 'victory',
      lifestealHealed: lifestealHealed,
    );
  }

  if (bossAddsTriggered) {
    return CombatRoundResult(
      playerHit: playerHit,
      playerCrit: playerCrit,
      offhandHit: offhandHit,
      staffHit: staffHit,
      poisonHit: poisonHit,
      skipNextEnemyAttack: false,
      enemyHit: null,
      thornsHit: 0,
      bossSleepRoundsRemaining: nextSleep,
      enemyAsleep: asleep,
      enemyRampage: false,
      bossAddsTriggered: true,
      bossInkActive: bossInkActive,
      bossPendingHp: bossPendingHp,
      enemyHpAfterPlayer: enemyHpAfterPlayer,
      playerHpAfterPlayer: playerHpAfterPlayer,
      enemyHp: bossPendingHp ?? nextEnemyHp,
      playerHp: hpAfterLifesteal,
      outcome: 'ongoing',
      lifestealHealed: lifestealHealed,
    );
  }

  if (save.combatSkipEnemyAttack || asleep) {
    return CombatRoundResult(
      playerHit: playerHit,
      playerCrit: playerCrit,
      offhandHit: offhandHit,
      staffHit: staffHit,
      poisonHit: poisonHit,
      skipNextEnemyAttack: skipNextEnemyAttack,
      enemyHit: null,
      thornsHit: 0,
      bossSleepRoundsRemaining: nextSleep,
      enemyAsleep: asleep,
      enemyRampage: false,
      bossAddsTriggered: false,
      bossInkActive: bossInkActive,
      bossPendingHp: null,
      enemyHpAfterPlayer: enemyHpAfterPlayer,
      playerHpAfterPlayer: playerHpAfterPlayer,
      enemyHp: nextEnemyHp,
      playerHp: hpAfterLifesteal,
      outcome: 'ongoing',
      lifestealHealed: lifestealHealed,
    );
  }

  final rampage = profile != null && nextEnemyHp <= enemyMaxHp * profile.rampageHpRatio;
  final enemyRange = enemyEncounterDamageRange(db, save, enemy);
  var enemyRaw = rollDamage(enemyRange.min, enemyRange.max, random);
  if (rampage) enemyRaw *= 2;
  final enemyHit = applyMitigation(enemyRaw, playerDamageReduction(db, save), floor);
  final playerHp = math.max(0, hpAfterLifesteal - enemyHit);

  final thornsPercent = equippedEnchantmentThornsPercent(db, save);
  num thornsHit = thornsPercent > 0 ? (enemyHit * thornsPercent / 100).round() : 0;
  thornsHit = applySleepIncoming(thornsHit, asleep);
  if (lockpickCombat) thornsHit = 0;
  thornsHit = applyEnemyDamageResistance(thornsHit, enemy, floor);
  if (thornsHit > 0) {
    nextEnemyHp = math.max(0, nextEnemyHp - thornsHit);
  }

  return CombatRoundResult(
    playerHit: playerHit,
    playerCrit: playerCrit,
    offhandHit: offhandHit,
    staffHit: staffHit,
    poisonHit: poisonHit,
    skipNextEnemyAttack: skipNextEnemyAttack,
    enemyHit: enemyHit,
    thornsHit: thornsHit,
    bossSleepRoundsRemaining: nextSleep,
    enemyAsleep: asleep,
    enemyRampage: rampage,
    bossAddsTriggered: false,
    bossInkActive: bossInkActive,
    bossPendingHp: null,
    enemyHpAfterPlayer: enemyHpAfterPlayer,
    playerHpAfterPlayer: playerHpAfterPlayer,
    enemyHp: nextEnemyHp,
    playerHp: playerHp,
    outcome: playerHp <= 0
        ? 'defeat'
        : nextEnemyHp <= 0
        ? 'victory'
        : 'ongoing',
    lifestealHealed: lifestealHealed,
  );
}

/// Raw lifesteal heal from damage dealt this round (before HP clamp).
num lifestealHealAmount(GameDatabase db, PlayerSave save, num damageDealt) {
  final percent = activeSpellLifestealPercent(db, save);
  if (percent <= 0 || damageDealt <= 0) return 0;
  return (damageDealt * percent / 100).floor();
}

/// Heal from Lifesteal spells based on damage dealt this round, clamped to max HP.
num _applyLifestealHeal(GameDatabase db, PlayerSave save, num currentHp, num damageDealt) {
  final heal = lifestealHealAmount(db, save, damageDealt);
  if (heal <= 0) return currentHp;
  return math.min(playerMaxHp(db, save), currentHp + heal);
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

  final xpAmount = enemyCombatXp(enemy);
  // Prefer fishing-mode bosses and Fishing-tagged fight actions (Mother Squid /
  // Squidling fallthrough). Ordinary fights split XP across Might / Vitality.
  final fishingMode =
      bossProfile(enemy)?.damageMode == 'fishing' || action.relevantSkillId == fishingSkillId;
  final xpAwards = <({String skillId, num xp})>[];
  var xpSkillId = mightSkillId;
  if (fishingMode) {
    xpSkillId = fishingSkillId;
    if (xpAmount > 0) {
      next = applyXp(next, db, fishingSkillId, xpAmount).save;
      xpAwards.add((skillId: fishingSkillId, xp: xpAmount));
    }
  } else {
    final split = splitCombatVictoryXp(xpAmount, normalizeAttackStyle(save.attackStyle));
    if (split.mightXp > 0) {
      next = applyXp(next, db, mightSkillId, split.mightXp).save;
      xpAwards.add((skillId: mightSkillId, xp: split.mightXp));
      xpSkillId = mightSkillId;
    }
    if (split.vitalityXp > 0) {
      next = applyXp(next, db, vitalitySkillId, split.vitalityXp).save;
      xpAwards.add((skillId: vitalitySkillId, xp: split.vitalityXp));
      if (split.mightXp <= 0) xpSkillId = vitalitySkillId;
    }
  }

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
  // Hoard: chance to double all gold from this victory (after race multipliers).
  final hoardChance = activeSpellGoldDoubleChancePercent(db, next);
  if (hoardChance > 0 && goldGained > 0 && random() * 100 < hoardChance) {
    next = next.copyWith(gold: next.gold + goldGained);
    goldGained *= 2;
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
  if (isBossEnemy(enemy)) {
    next = next.copyWith(
      statistics: PlayerStatistics(
        values: <String, num>{
          ...next.statistics.values,
          'bosses_killed': (next.statistics.values['bosses_killed'] ?? 0) + 1,
        },
      ),
    );
  }

  // Auto-eat happens at the end of an ongoing combat round, not on a kill.
  next = withBossRespawn(tickPotionAction(clearCombatSave(next)), enemy, nowMs);
  next = applyQuestDefeatProgress(db, next, jsString(enemy.raw['Enemy ID']), 1);
  next = applyBountyDefeatProgress(next, jsString(enemy.raw['Enemy ID']), 1, nowMs);
  next = withoutHeldAction(next, save.currentActivityId);
  next = creditLootTracker(
    next,
    'enemy',
    jsString(enemy.raw['Enemy ID']),
    rewarded.loot,
    goldGained,
    nowMs,
  );
  next = creditXpAwards(next, xpAwards, nowMs);

  return CombatVictoryResult(
    save: next,
    xpGained: xpAmount,
    xpSkillId: xpSkillId,
    xpAwards: xpAwards,
    goldGained: goldGained,
    loot: rewarded.loot,
    cosmeticsGranted: rewarded.cosmeticsGranted,
    foodConsumed: false,
    foodHealed: 0,
    foodName: null,
  );
}

PlayerSave applyCombatDefeat(GameDatabase db, PlayerSave save, num nowMs) {
  final pauseSec = configNumber(db, 'death_pause', 30);
  final maxHp = playerMaxHp(db, save);
  return withoutHeldAction(
    tickPotionAction(
      clearCombatSave(
        revokeCosmetic(
          save.copyWith(
            maxHp: maxHp,
            currentHp: 0,
            deathPauseUntil: isoFromMs(nowMs + pauseSec * 1000),
            hasEverDied: true,
            currentActionId: null,
            actionStartedAt: null,
            actionDurationMs: null,
          ),
          starterTitleCosmeticId,
        ),
      ),
    ),
    save.currentActivityId,
  );
}

/// HP restored when the death pause ends.
num deathRecoveryHp(num maxHp) => math.max(1, (maxHp * 0.5).floor());

/// Clears the death pause and restores half of current max HP.
PlayerSave applyDeathRecovery(GameDatabase db, PlayerSave save) {
  final maxHp = playerMaxHp(db, save);
  return save.copyWith(maxHp: maxHp, currentHp: deathRecoveryHp(maxHp), deathPauseUntil: null);
}

/// Shown whenever an action is refused because the death pause is still running.
const String recoveringBlockedReason = 'You need to recover before you can do that.';

bool isDeathPaused(PlayerSave save, num nowMs) {
  if (isBlank(save.deathPauseUntil)) return false;
  return jsDateParse(save.deathPauseUntil) > nowMs;
}

num deathPauseRemainingMs(PlayerSave save, num nowMs) {
  if (isBlank(save.deathPauseUntil)) return 0;
  return math.max(0, jsDateParse(save.deathPauseUntil) - nowMs);
}
