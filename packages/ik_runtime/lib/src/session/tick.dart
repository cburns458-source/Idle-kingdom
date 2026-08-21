import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'events.dart';

const String _combatSkillId = 'SKL-0001';

class SessionTickResult {
  const SessionTickResult({required this.save, required this.changed, required this.events});

  final PlayerSave save;

  /// False when nothing was due, which is the common case between frames.
  final bool changed;

  final List<SessionEvent> events;

  Map<String, Object?> toJson() => <String, Object?>{
    'save': save.toJson(),
    'changed': changed,
    'events': events.map((event) => event.toJson()).toList(),
  };
}

/// Collects the events of one tick and tracks whether the save moved.
class _TickOutput {
  /// [started] is the save the tick was handed, which is not always the one it
  /// begins working from: clearing a legacy activity transition already moved the
  /// save, and that has to count as a change so the client stores it.
  _TickOutput(PlayerSave save, [PlayerSave? started]) : _save = save, _started = started ?? save;

  PlayerSave _save;
  final PlayerSave _started;
  final List<SessionEvent> _events = <SessionEvent>[];

  PlayerSave get current => _save;

  void set(PlayerSave save) => _save = save;

  void emit(SessionEvent event) => _events.add(event);

  /// Credits activity time at the current location and reports any spawn.
  void creditCritterTime(num elapsedMs, num nowMs, RandomFn random) {
    final result = applyActivityTimeTowardCritters(
      _save,
      _save.currentLocationId,
      elapsedMs,
      nowMs,
      random,
    );
    _save = result.save;
    final spawned = result.spawned;
    if (spawned != null) {
      emit(CritterSpawnedEvent(critterId: spawned.id, displayName: spawned.displayName));
    }
  }

  SessionTickResult result() => SessionTickResult(
    save: _save,
    changed: !identical(_save, _started) || _events.isNotEmpty,
    events: _events,
  );
}

ActionRow? _actionById(GameDatabase db, String? actionId) {
  if (isBlank(actionId)) return null;
  return db.actions.firstWhereOrNull((row) => row.raw['Action ID'] == actionId);
}

/// Rolls the next action for a still-valid activity, or stops the activity.
///
/// Every catch-up point in a tick ends this way, so the "requirements slipped
/// while you were mid-action" path stays in one place.
void _continueActivity(
  GameDatabase db,
  _TickOutput out,
  String activityId,
  num nowMs,
  RandomFn random,
  String stoppedReason,
) {
  if (!activityStillValid(db, out.current, activityId)) {
    out.set(clearActivitySave(out.current, nowMs));
    out.emit(ActivityStoppedEvent(stoppedReason));
    return;
  }
  final generated = generateNextAction(db, out.current, activityId, random, nowMs);
  if (generated == null) {
    out.set(clearActivitySave(out.current, nowMs));
    out.emit(const ActivityStoppedEvent('No actions remain for this activity.'));
    return;
  }
  out.set(generated.save);
}

/// The XP / loot / gold line for a won fight.
ActionRewardBundle _victoryRewardBundle(
  GameDatabase db,
  PlayerSave before,
  PlayerSave after,
  EnemyRow enemy,
  num xpGained,
  List<LootGrant> loot,
  num goldGained,
  num nowMs,
) {
  final levelBefore = getSkillProgress(before, _combatSkillId).level;
  final levelAfter = getSkillProgress(after, _combatSkillId).level;
  final summary = summarizeXpReward(
    db,
    after,
    _combatSkillId,
    xpGained,
    levelAfter > levelBefore ? levelAfter : null,
  );
  return ActionRewardBundle(
    id: 'combat-${jsString(enemy.raw['Enemy ID'])}-${jsNumberToString(nowMs)}',
    xpRewards: summary != null ? <ActionXpRewardSummary>[summary] : const <ActionXpRewardSummary>[],
    loot: loot,
    goldGained: goldGained,
  );
}

String _roundMessage(EnemyRow enemy, CombatRoundResult round) {
  final hitLabel = round.playerCrit
      ? 'crit for ${jsNumberToString(round.playerHit)}'
      : 'hit ${jsNumberToString(round.playerHit)}';
  final offhand = round.offhandHit;
  final offhandLabel = offhand != null && offhand > 0
      ? ' Off-hand hits ${jsNumberToString(offhand)}.'
      : '';
  final name = jsString(enemy.raw['Display Name']);
  // `enemyHit` is null when the enemy never swung, which prints as `null`.
  final enemyHit = jsString(round.enemyHit);
  return round.thornsHit > 0
      ? 'You $hitLabel.$offhandLabel $name hits $enemyHit. '
            'Thorns reflects ${jsNumberToString(round.thornsHit)}.'
      : 'You $hitLabel.$offhandLabel $name hits $enemyHit.';
}

void _resolveDueCombatRound(
  GameDatabase db,
  _TickOutput out,
  String activityId,
  EnemyRow enemy,
  ActionRow action,
  num roundEnd,
  num roundMs,
  RandomFn random,
) {
  final before = out.current;
  final round = resolveCombatRound(db, before, enemy, before.combatEnemyHp!, random);
  final enemyId = jsString(enemy.raw['Enemy ID']);
  final enemyName = jsString(enemy.raw['Display Name']);
  out.emit(
    CombatRoundEvent(
      enemyId: enemyId,
      enemyName: enemyName,
      playerHit: round.playerHit,
      playerCrit: round.playerCrit,
      offhandHit: round.offhandHit,
      enemyHit: round.enemyHit,
      thornsHit: round.thornsHit,
      outcome: round.outcome,
    ),
  );

  if (round.outcome == 'victory') {
    final victory = applyCombatVictory(
      db,
      before.copyWith(combatEnemyHp: 0, currentHp: round.playerHp),
      action,
      enemy,
      random,
      roundEnd,
    );
    out.set(victory.save);
    out.creditCritterTime(roundMs, roundEnd, random);
    out.emit(
      RewardsEvent(
        _victoryRewardBundle(
          db,
          before,
          out.current,
          enemy,
          victory.xpGained,
          victory.loot,
          victory.goldGained,
          roundEnd,
        ),
      ),
    );
    out.emit(
      MessageEvent(
        victory.foodConsumed
            ? 'Ate ${jsString(victory.foodName)} (${victory.foodHealed > 0 ? '+' : ''}${jsNumberToString(victory.foodHealed)} HP)'
            : round.thornsHit > 0
            ? 'Thorns reflects ${jsNumberToString(round.thornsHit)} and defeats $enemyName!'
            : round.playerCrit
            ? 'Critical hit! Defeated $enemyName'
            : 'Defeated $enemyName',
      ),
    );
    if (victory.foodConsumed && victory.foodHealed != 0) {
      out.emit(FoodHealedEvent(healed: victory.foodHealed, foodName: jsString(victory.foodName)));
    }
    out.emit(EnemyDefeatedEvent(enemyId: enemyId, enemyName: enemyName));
    _continueActivity(
      db,
      out,
      activityId,
      roundEnd,
      random,
      'Defeated $enemyName · activity stopped.',
    );
    return;
  }

  if (round.outcome == 'defeat') {
    out.set(applyCombatDefeat(db, before.copyWith(currentHp: 0), roundEnd));
    out.creditCritterTime(roundMs, roundEnd, random);
    out.emit(PlayerDefeatedEvent(enemyId: enemyId, enemyName: enemyName));
    out.emit(MessageEvent('Defeated by $enemyName. Recovering…'));
    return;
  }

  out.set(
    before.copyWith(
      currentHp: round.playerHp,
      combatEnemyHp: round.enemyHp,
      combatRoundStartedAt: isoFromMs(roundEnd),
    ),
  );
  out.creditCritterTime(roundMs, roundEnd, random);
  out.emit(MessageEvent(_roundMessage(enemy, round)));
}

/// Advances whatever the save has due at [nowMs]: one combat round, one gathering
/// action, one craft, a death-pause recovery, or the next action for an activity
/// that has none.
///
/// The live client calls this every frame and applies the events it returns; the
/// unattended resolver is the same rules run in a loop over a past window. Time
/// and randomness are parameters, so a tick is reproducible.
SessionTickResult advanceSession(GameDatabase db, PlayerSave save, num nowMs, RandomFn random) {
  final out = _TickOutput(resolveActivityTransitions(db, save, nowMs, random), save);

  final activityId = out.current.currentActivityId;
  if (isBlank(activityId)) return out.result();

  // Death pause blocks everything until it elapses, then play resumes.
  if (isNotBlank(out.current.deathPauseUntil)) {
    if (deathPauseRemainingMs(out.current, nowMs) > 0) return out.result();
    final pauseEnded = jsDateParse(out.current.deathPauseUntil);
    out.set(out.current.copyWith(deathPauseUntil: null));
    _continueActivity(
      db,
      out,
      activityId!,
      pauseEnded,
      random,
      'Activity stopped after defeat — requirements no longer met.',
    );
    out.emit(const RecoveredEvent());
    return out.result();
  }

  if (isNotBlank(out.current.combatEnemyId) && isNotBlank(out.current.combatRoundStartedAt)) {
    final roundMs = configNumber(db, 'combat_round_duration', 4) * 1000;
    final roundEnd = jsDateParse(out.current.combatRoundStartedAt) + roundMs;
    if (roundEnd > nowMs) return out.result();

    final enemy = getEnemy(db, out.current.combatEnemyId!);
    final action = _actionById(db, out.current.currentActionId);
    if (enemy == null || action == null || out.current.combatEnemyHp == null) {
      out.set(clearActivitySave(out.current, roundEnd));
      return out.result();
    }
    _resolveDueCombatRound(db, out, activityId!, enemy, action, roundEnd, roundMs, random);
    return out.result();
  }

  // Standard production resolves one craft at a time against its own timer.
  if (isNotBlank(out.current.productionRecipeId)) {
    final startedAt = out.current.actionStartedAt;
    final durationMs = out.current.actionDurationMs;
    // A zero or unparseable duration is falsy in the original, so the craft waits
    // rather than being treated as instantly due.
    if (isBlank(startedAt) || jsNumberOrZero(durationMs) == 0) return out.result();
    final due = jsDateParse(startedAt) + durationMs!;
    if (due > nowMs) return out.result();

    final finished = completeProductionCraft(db, out.current, due);
    if (finished == null) {
      out.emit(const InventoryFullEvent());
      return out.result();
    }
    out.set(finished.save);
    out.creditCritterTime(durationMs, due, random);
    final output = finished.reward.loot.firstOrNull;
    if (output != null) {
      out.emit(CraftCompletedEvent(itemId: output.itemId, displayName: output.displayName));
    }
    out.emit(RewardsEvent(finished.reward));
    return out.result();
  }

  final actionState = restoreActiveActionState(out.current);
  if (actionState != null) {
    final due = actionState.startedAtMs + actionState.durationMs;
    if (due > nowMs) return out.result();

    final action = _actionById(db, actionState.actionId);
    if (action == null) {
      out.set(clearActivitySave(out.current, due));
      return out.result();
    }

    final finished = completeGatheringAction(db, out.current, action, random);
    out.set(finished.save);
    out.creditCritterTime(actionState.durationMs, due, random);
    out.emit(
      RewardsEvent(
        ActionRewardBundle(
          id: '${finished.result.actionId}-${jsNumberToString(due)}',
          xpRewards: finished.result.xpRewards,
          loot: finished.result.loot,
          goldGained: finished.result.goldGained,
        ),
      ),
    );
    _continueActivity(
      db,
      out,
      activityId!,
      due,
      random,
      'Activity stopped — requirements are no longer met.',
    );
    return out.result();
  }

  // An activity is running with nothing rolled yet. Standard production waits
  // for the player to pick a recipe instead of rolling an action.
  final activity = getActivity(db, activityId!);
  if (activity != null && isStandardProductionActivity(db, activity)) return out.result();
  _continueActivity(
    db,
    out,
    activityId,
    nowMs,
    random,
    'Activity stopped — requirements are no longer met.',
  );
  return out.result();
}
