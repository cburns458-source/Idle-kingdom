import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../achievements/progress.dart';
import '../combat/boss.dart';
import '../combat/engine.dart';
import '../log/milestones.dart';
import '../js_compat.dart';
import '../potions/effects.dart';
import '../production/engine.dart';
import '../production/recipes.dart';
import '../quests/progress.dart';
import '../rng/mulberry32.dart';
import '../save/generated/save_models.dart';
import '../time.dart';
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

GatheringCompletion completeGatheringAction(
  GameDatabase db,
  PlayerSave save,
  ActionRow action,
  RandomFn random,
) {
  final skillId = jsString(action.raw['Relevant Skill ID']);
  final rewarded = resolveActionRewards(db, save, action, random);
  final xpAmount = gatheringXpReward(db, save, action);
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

  // Qualifying bow-based Hunting Actions also grant Combat XP (10% of the
  // Hunting XP just awarded) when a bow is the equipped Weapon/Tool.
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
