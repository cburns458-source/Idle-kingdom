import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../achievements/progress.dart';
import '../combat/boss.dart';
import '../combat/engine.dart';
import '../combat/food.dart';
import '../equipment/loadout.dart';
import '../log/milestones.dart';
import '../js_compat.dart';
import '../potions/effects.dart';
import '../production/engine.dart';
import '../production/recipes.dart';
import '../quests/progress.dart';
import '../quests/quests.dart';
import '../rng/mulberry32.dart';
import '../save/generated/save_models.dart';
import '../time.dart';
import '../trackers/trackers.dart';
import 'bonus_xp.dart';
import 'gathering.dart';
import 'held_action.dart';
import 'pools.dart';
import 'requirements.dart';
import 'reward_summary.dart';
import 'rewards.dart';
import 'types.dart';
import 'xp.dart';

const String comingSoonReason = 'Coming soon.';

ActivityRow? getActivity(GameDatabase db, String activityId) {
  return db.activities.firstWhereOrNull((row) => row.raw['Activity ID'] == activityId);
}

bool activityIsComingSoon(ActivityRow? activity) {
  if (activity == null) return false;
  return jsString(activity.raw['Notes'])
      .split(';')
      .map((token) => token.trim().toLowerCase())
      .contains('coming_soon');
}

/// Earliest time the next pool action can start, or null when nothing is waiting.
num? bossRespawnWaitUntilMs(GameDatabase db, PlayerSave save, String activityId) {
  final poolId = getActivity(db, activityId)?.raw['Pool ID'];
  if (poolId is! String || poolId.isEmpty) return null;

  final heldId = heldActionIdFor(save, activityId);
  ActionRow? held;
  if (heldId != null) {
    held = db.actions.firstWhereOrNull((row) => row.raw['Action ID'] == heldId);
    if (held != null && !isSelectableAction(held)) held = null;
  }
  final candidates = held != null
      ? <ActionRow>[held]
      : eligiblePoolEntries(db, poolId).map((entry) => entry.action).toList();
  if (candidates.isEmpty) return null;

  num? wait;
  for (final action in candidates) {
    if (action.raw['Category'] != 'Combat') return null;
    final enemy = enemyForAction(db, action);
    if (enemy == null || !isBossEnemy(enemy)) return null;
    final until = bossRespawnUntilMs(save, jsString(enemy.raw['Enemy ID']));
    if (until == null) return null;
    wait = wait == null || until < wait ? until : wait;
  }
  return wait;
}

ActivityStartResult validateActivityStart(GameDatabase db, PlayerSave save, String activityId) {
  final activity = getActivity(db, activityId);
  if (activity == null) return const ActivityStartResult.failed('Unknown activity.');
  if (activity.raw['Location ID'] != save.currentLocationId) {
    return const ActivityStartResult.failed(
      'Travel to this location before starting the activity.',
    );
  }
  if (activityIsComingSoon(activity)) {
    return const ActivityStartResult.failed(comingSoonReason);
  }
  final activityReqFailures = unmetHardRequirements(
    db,
    save,
    requirementsForEntity(db, 'Activity', activityId),
  );
  if (activityReqFailures.isNotEmpty) {
    return ActivityStartResult.failed(activityReqFailures.first);
  }

  if (isStandardProductionActivity(db, activity)) {
    if (recipesForActivity(db, save, activityId).isEmpty) {
      return const ActivityStartResult.failed(
        'No known recipes are available at this station yet.',
      );
    }
    return const ActivityStartResult.ok();
  }

  final poolId = activity.raw['Pool ID'];
  if (poolId is! String || poolId.isEmpty) {
    return const ActivityStartResult.failed('This activity is not available yet.');
  }

  final eligible = eligiblePoolEntries(db, poolId);
  if (eligible.isEmpty) {
    return const ActivityStartResult.failed('No actions are ready for this activity yet.');
  }

  for (final candidate in eligible) {
    final failures = unmetHardRequirements(
      db,
      save,
      requirementsForEntity(db, 'Action', jsString(candidate.action.raw['Action ID'])),
    );
    if (failures.isNotEmpty) return ActivityStartResult.failed(failures.first);
    final notes = candidate.action.raw['Notes'];
    final notesText = notes is String ? notes : '';
    if (RegExp(r'RequiresLockpick', caseSensitive: false).hasMatch(notesText)) {
      final tool = slotStack(save, weaponToolSlotId);
      if (tool == null || tool.quantity <= 0 || tool.itemId != lockpickItemId) {
        return const ActivityStartResult.failed('Equip lockpicks in the Weapon/Tool slot first.');
      }
    }
  }

  return const ActivityStartResult.ok();
}

PlayerSave beginActivitySave(PlayerSave save, String activityId, String nowIso) {
  if (isDeathPaused(save, jsDateParse(nowIso))) return save;
  return clearProductionSave(
    clearCombatSave(
      save.copyWith(
        currentActivityId: activityId,
        activityStartedAt: nowIso,
        currentActionId: null,
        actionStartedAt: null,
        actionDurationMs: null,
        deathPauseUntil: null,
        activityTransition: null,
      ),
    ),
  );
}

PlayerSave clearActivitySave(PlayerSave save, num nowMs) {
  if (isDeathPaused(save, nowMs)) return save;
  return clearProductionSave(
    clearCombatSave(
      save.copyWith(
        currentActivityId: null,
        activityStartedAt: null,
        currentActionId: null,
        actionStartedAt: null,
        actionDurationMs: null,
        deathPauseUntil: null,
        activityTransition: null,
      ),
    ),
  );
}

/// The action a pool activity just rolled, plus the save that started it.
class GeneratedAction {
  const GeneratedAction({required this.save, required this.action, required this.state});

  final PlayerSave save;
  final ActionRow action;

  /// Null for combat actions, which track their own round state in the save.
  final ActiveActionState? state;
}

GeneratedAction? generateNextAction(
  GameDatabase db,
  PlayerSave save,
  String activityId,
  RandomFn random,
  num nowMs,
) {
  final poolId = getActivity(db, activityId)?.raw['Pool ID'];
  if (poolId is! String || poolId.isEmpty) return null;

  final heldId = heldActionIdFor(save, activityId);
  final eligible = eligiblePoolEntries(db, poolId);
  ActionRow? action;
  if (heldId != null) {
    action = db.actions.firstWhereOrNull((row) => row.raw['Action ID'] == heldId);
    if (action != null && !isSelectableAction(action)) action = null;
    if (action != null && !eligible.any((pair) => pair.action.raw['Action ID'] == heldId)) {
      action = null;
    }
  }
  action ??= pickWeightedAction(eligible, random);
  if (action == null) return null;
  final actionId = jsString(action.raw['Action ID']);

  final startedAt = isoFromMs(nowMs);

  if (action.raw['Category'] == 'Combat') {
    final enemy = enemyForAction(db, action);
    if (enemy == null) return null;
    final withActivity = save.copyWith(
      currentActivityId: activityId,
      activityStartedAt: save.activityStartedAt ?? startedAt,
      currentActionId: null,
      actionStartedAt: null,
      actionDurationMs: null,
    );
    if (isBossEnemy(enemy) && !isBossRespawnReady(save, jsString(enemy.raw['Enemy ID']), nowMs)) {
      return GeneratedAction(action: action, state: null, save: clearCombatSave(withActivity));
    }
    return GeneratedAction(
      action: action,
      state: null,
      save: withHeldAction(
        beginCombatSave(db, withActivity, action, enemy, startedAt),
        activityId,
        actionId,
      ),
    );
  }

  final durationMs = gatheringDurationMs(db, save, action);
  final next = clearCombatSave(
    save.copyWith(
      currentActivityId: activityId,
      currentActionId: actionId,
      actionStartedAt: startedAt,
      actionDurationMs: durationMs,
    ),
  );
  return GeneratedAction(
    action: action,
    state: ActiveActionState(actionId: actionId, startedAtMs: nowMs, durationMs: durationMs),
    save: withHeldAction(
      tryConsumePotionForScope(db, next, 'one_action').save,
      activityId,
      actionId,
    ),
  );
}

/// A finished gathering action: the updated save and what it paid out.
class GatheringCompletion {
  const GatheringCompletion({required this.save, required this.result});

  final PlayerSave save;
  final ActionCompletionResult result;
}

num lockpickBreakChancePercent(num thieveryLevel) {
  final level = thieveryLevel.floor() < 1 ? 1 : thieveryLevel.floor();
  final chance = 50 + (level - 1) * 0.5;
  return chance > 100 ? 100 : chance;
}

({PlayerSave save, bool broke}) _maybeBreakLockpick(
  PlayerSave save,
  RandomFn random,
  num thieveryLevel,
) {
  final chance = lockpickBreakChancePercent(thieveryLevel);
  if (random() * 100 >= chance) return (save: save, broke: false);
  return (save: _consumeLockpick(save), broke: true);
}

GatheringCompletion completeGatheringAction(
  GameDatabase db,
  PlayerSave save,
  ActionRow action,
  RandomFn random,
  num nowMs,
) {
  final notes = action.raw['Notes'];
  final notesText = notes is String ? notes : '';
  final now = nowMs;
  final requiresLockpick = RegExp(r'RequiresLockpick', caseSensitive: false).hasMatch(notesText);
  final isThievery = RegExp(r'Thievery', caseSensitive: false).hasMatch(notesText);
  final skillId = jsString(action.raw['Relevant Skill ID']);
  final thieveryLevel = getSkillProgress(save, 'SKL-0015').level;

  ActionCompletionResult emptyResult() => ActionCompletionResult(
    actionId: jsString(action.raw['Action ID']),
    actionName: jsString(action.raw['Display Name']),
    skillId: skillId,
    xpGained: 0,
    bonusXp: const <BonusXpGrant>[],
    xpRewards: const <ActionXpRewardSummary>[],
    goldGained: 0,
    loot: const <LootGrant>[],
    leveledUpTo: null,
  );

  if (requiresLockpick) {
    final tool = slotStack(save, weaponToolSlotId);
    if (tool == null || tool.quantity <= 0 || tool.itemId != lockpickItemId) {
      return GatheringCompletion(
        save: withoutHeldAction(save, save.currentActivityId),
        result: emptyResult(),
      );
    }
  }

  GatheringCompletion awardXpOnly(
    PlayerSave base, {
    num damageTaken = 0,
    num foodHealed = 0,
    bool showZeroDamageHit = false,
    bool thieveryFailed = false,
    bool lockpickBroke = false,
  }) {
    final xpAmount = gatheringXpReward(db, base, action);
    var next = clearActivePotionEffect(base);
    final xpApplied = applyXp(next, db, skillId, xpAmount);
    next = xpApplied.save;
    var leveledUpTo = xpApplied.leveledUpTo;
    final bonusXp = <BonusXpGrant>[];
    final xpRewards = <ActionXpRewardSummary>[];
    final primaryReward = summarizeXpReward(db, next, skillId, xpAmount, xpApplied.leveledUpTo);
    if (primaryReward != null) xpRewards.add(primaryReward);

    void applyBonusXp(String bonusSkillId, num amount) {
      if (amount <= 0) return;
      final applied = applyXp(next, db, bonusSkillId, amount);
      next = applied.save;
      bonusXp.add(BonusXpGrant(skillId: bonusSkillId, xp: amount));
      final reward = summarizeXpReward(db, next, bonusSkillId, amount, applied.leveledUpTo);
      if (reward != null) xpRewards.add(reward);
      if (applied.leveledUpTo != null) leveledUpTo = applied.leveledUpTo;
    }

    final bonus = bonusSkillXpForAction(jsString(action.raw['Action ID']));
    if (bonus != null && bonus.xp > 0) {
      applyBonusXp(bonus.skillId, gatheringXpReward(db, save, action, bonus.xp));
    }
    final bowBonus = bowHuntingCombatXpBonus(db, save, skillId, xpAmount);
    if (bowBonus != null) applyBonusXp(bowBonus.skillId, bowBonus.xp);

    next = addLifetimeStat(next, gatheringActionsStat);
    next = applyQuestActionProgress(db, next, jsString(action.raw['Action ID']));
    next = applyQuestAutoCompleteOnAction(db, next).save;
    final source = lootSourceForAction(action);
    next = creditLootTracker(next, source.kind, source.sourceId, const <LootGrant>[], 0, now);
    next = creditXpAwards(next, [
      for (final reward in xpRewards) (skillId: reward.skillId, xp: reward.xp),
    ], now);

    return GatheringCompletion(
      save: withoutHeldAction(next, save.currentActivityId),
      result: ActionCompletionResult(
        actionId: jsString(action.raw['Action ID']),
        actionName: jsString(action.raw['Display Name']),
        skillId: skillId,
        xpGained: xpAmount,
        bonusXp: bonusXp,
        xpRewards: xpRewards,
        goldGained: 0,
        loot: const <LootGrant>[],
        leveledUpTo: leveledUpTo,
        damageTaken: damageTaken,
        foodHealed: foodHealed,
        showZeroDamageHit: showZeroDamageHit,
        thieveryFailed: thieveryFailed,
        lockpickBroke: lockpickBroke,
      ),
    );
  }

  final failChanceMatch = RegExp(r'FailChance:(\d+)', caseSensitive: false).firstMatch(notesText);
  if (isThievery &&
      failChanceMatch != null &&
      !RegExp(r'NoConsequences', caseSensitive: false).hasMatch(notesText)) {
    final failChance = num.parse(failChanceMatch.group(1)!);
    if (random() * 100 < failChance) {
      final damagePercent =
          num.tryParse(
            RegExp(
                  r'FailDamagePercent:(\d+)',
                  caseSensitive: false,
                ).firstMatch(notesText)?.group(1) ??
                '',
          ) ??
          10;
      final damage = (save.maxHp * damagePercent / 100).floor();
      final appliedDamage = damage < 1 ? 1 : damage;
      final nextHp = save.currentHp - appliedDamage;
      var next = save.copyWith(currentHp: nextHp);
      var lockpickBroke = false;
      if (requiresLockpick) {
        final rolled = _maybeBreakLockpick(next, random, thieveryLevel);
        next = rolled.save;
        lockpickBroke = rolled.broke;
      }
      num foodHealed = 0;
      if (nextHp <= 0) {
        next = applyCombatDefeat(db, next, now);
      } else {
        final fed = consumeFoodAfterVictory(db, next);
        next = fed.save;
        foodHealed = fed.healed;
      }
      return awardXpOnly(
        next,
        damageTaken: appliedDamage,
        foodHealed: foodHealed,
        // Real fail damage uses the floater amount; zero-hit is for lockpick success.
        showZeroDamageHit: false,
        thieveryFailed: true,
        lockpickBroke: lockpickBroke,
      );
    }
  }

  var working = save;
  var lockpickBroke = false;
  if (requiresLockpick) {
    final rolled = _maybeBreakLockpick(working, random, thieveryLevel);
    working = rolled.save;
    lockpickBroke = rolled.broke;
    if (lockpickBroke) {
      num foodHealed = 0;
      if (isThievery) {
        final fed = consumeFoodAfterVictory(db, working);
        working = fed.save;
        foodHealed = fed.healed;
      }
      return awardXpOnly(
        working,
        foodHealed: foodHealed,
        showZeroDamageHit: true,
        lockpickBroke: true,
      );
    }
  }

  final rewarded = resolveActionRewards(db, working, action, random);
  final xpAmount = gatheringXpReward(db, working, action);
  final xpApplied = applyXp(clearActivePotionEffect(rewarded.save), db, skillId, xpAmount);
  var next = xpApplied.save;
  var leveledUpTo = xpApplied.leveledUpTo;

  final bonusXp = <BonusXpGrant>[];
  final xpRewards = <ActionXpRewardSummary>[];
  final primaryReward = summarizeXpReward(db, next, skillId, xpAmount, xpApplied.leveledUpTo);
  if (primaryReward != null) xpRewards.add(primaryReward);

  void applyBonusXp(String bonusSkillId, num amount) {
    if (amount <= 0) return;
    final applied = applyXp(next, db, bonusSkillId, amount);
    next = applied.save;
    bonusXp.add(BonusXpGrant(skillId: bonusSkillId, xp: amount));
    final reward = summarizeXpReward(db, next, bonusSkillId, amount, applied.leveledUpTo);
    if (reward != null) xpRewards.add(reward);
    if (applied.leveledUpTo != null) leveledUpTo = applied.leveledUpTo;
  }

  final bonus = bonusSkillXpForAction(jsString(action.raw['Action ID']));
  if (bonus != null && bonus.xp > 0) {
    applyBonusXp(bonus.skillId, gatheringXpReward(db, save, action, bonus.xp));
  }
  final bowBonus = bowHuntingCombatXpBonus(db, save, skillId, xpAmount);
  if (bowBonus != null) applyBonusXp(bowBonus.skillId, bowBonus.xp);

  next = addLifetimeStat(next, gatheringActionsStat);
  if (rewarded.loot.isNotEmpty) {
    next = recordGatheredDrops(
      next,
      rewarded.loot.map((drop) => drop.itemId),
      save.currentLocationId,
      save.equipment.slots[weaponToolSlotId]?.itemId,
    );
  }
  next = applyQuestActionProgress(db, next, jsString(action.raw['Action ID']));
  next = applyQuestAutoCompleteOnAction(db, next).save;
  final source = lootSourceForAction(action);
  next = creditLootTracker(
    next,
    source.kind,
    source.sourceId,
    rewarded.loot,
    rewarded.goldGained,
    now,
  );
  next = creditXpAwards(next, [
    for (final reward in xpRewards) (skillId: reward.skillId, xp: reward.xp),
  ], now);
  num foodHealed = 0;
  if (isThievery) {
    final fed = consumeFoodAfterVictory(db, next);
    next = fed.save;
    foodHealed = fed.healed;
  }

  return GatheringCompletion(
    save: withoutHeldAction(next, save.currentActivityId),
    result: ActionCompletionResult(
      actionId: jsString(action.raw['Action ID']),
      actionName: jsString(action.raw['Display Name']),
      skillId: skillId,
      xpGained: xpAmount,
      bonusXp: bonusXp,
      xpRewards: xpRewards,
      goldGained: rewarded.goldGained,
      loot: rewarded.loot,
      leveledUpTo: leveledUpTo,
      damageTaken: 0,
      foodHealed: foodHealed,
      showZeroDamageHit: requiresLockpick,
      thieveryFailed: false,
      lockpickBroke: false,
    ),
  );
}

PlayerSave _consumeLockpick(PlayerSave save) {
  final tool = slotStack(save, weaponToolSlotId);
  if (tool == null || tool.itemId != lockpickItemId || tool.quantity <= 0) return save;
  final nextQty = tool.quantity - 1;
  return save.copyWith(
    equipment: EquipmentLoadout(
      slots: <String, EquippedStack?>{
        ...save.equipment.slots,
        weaponToolSlotId: nextQty > 0 ? tool.copyWith(quantity: nextQty) : null,
      },
    ),
  );
}

bool activityStillValid(GameDatabase db, PlayerSave save, String activityId) {
  return validateActivityStart(db, save, activityId).ok;
}

ActiveActionState? restoreActiveActionState(PlayerSave save) {
  if (isBlank(save.currentActionId) ||
      isBlank(save.actionStartedAt) ||
      save.actionDurationMs == null) {
    return null;
  }
  return ActiveActionState(
    actionId: save.currentActionId!,
    startedAtMs: jsDateParse(save.actionStartedAt),
    durationMs: save.actionDurationMs!,
  );
}
