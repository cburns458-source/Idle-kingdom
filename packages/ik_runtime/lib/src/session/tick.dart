import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'events.dart';

class SessionTickResult {
  const SessionTickResult({
    required this.save,
    required this.changed,
    required this.events,
    this.awayCatchUp,
  });

  final PlayerSave save;

  /// False when nothing was due, which is the common case between frames.
  final bool changed;

  final List<SessionEvent> events;

  /// Set when this tick batch-resolved a long foreground gap instead of
  /// emitting one live step. Omitted from [toJson] so parity fixtures stay
  /// the live-tick shape.
  final UnattendedResult? awayCatchUp;

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
  List<({String skillId, num xp})> xpAwards,
  List<LootGrant> loot,
  num goldGained,
  num nowMs, {
  List<ActionCosmeticGrant> cosmeticsGranted = const <ActionCosmeticGrant>[],
}) {
  final xpRewards = <ActionXpRewardSummary>[];
  for (final award in xpAwards) {
    if (award.xp <= 0) continue;
    final levelBefore = getSkillProgress(before, award.skillId).level;
    final levelAfter = getSkillProgress(after, award.skillId).level;
    final summary = summarizeXpReward(
      db,
      after,
      award.skillId,
      award.xp,
      levelAfter > levelBefore ? levelAfter : null,
    );
    if (summary != null) xpRewards.add(summary);
  }
  return ActionRewardBundle(
    id: 'combat-${jsString(enemy.raw['Enemy ID'])}-${jsNumberToString(nowMs)}',
    xpRewards: xpRewards,
    loot: loot,
    goldGained: goldGained,
    cosmeticsGranted: cosmeticsGranted,
  );
}

void _emitRoundEndAutoEat(_TickOutput out, FoodConsumption food) {
  if (!food.consumed || food.healed == 0) return;
  out.emit(FoodHealedEvent(healed: food.healed, foodName: jsString(food.foodName)));
}

String _roundMessage(EnemyRow enemy, CombatPendingRound round) {
  final inkLabel = round.bossInkActive ? ' Ink clouds your strike!' : '';
  final hitLabel = round.playerCrit
      ? 'crit for ${jsNumberToString(round.playerHit)}'
      : 'hit ${jsNumberToString(round.playerHit)}';
  final offhand = round.offhandHit;
  final offhandLabel = offhand != null && offhand > 0
      ? ' Off-hand hits ${jsNumberToString(offhand)}.'
      : '';
  final sparks = round.staffHit;
  final sparksLabel = sparks != null && sparks > 0
      ? ' Sparks hit ${jsNumberToString(sparks)}.'
      : '';
  final poisonLabel = round.poisonHit != null
      ? ' Poison hits ${jsNumberToString(round.poisonHit!)}.'
      : '';
  final name = jsString(enemy.raw['Display Name']);
  if (round.enemyHit == null) {
    return round.enemyAsleep
        ? 'You $hitLabel.$offhandLabel$sparksLabel$poisonLabel$inkLabel $name sleeps.'
        : 'You $hitLabel.$offhandLabel$sparksLabel$poisonLabel$inkLabel $name is bound and cannot attack.';
  }
  final swing = round.enemyRampage
      ? '$name rampages for ${jsString(round.enemyHit)}'
      : '$name hits ${jsString(round.enemyHit)}';
  return round.thornsHit > 0
      ? 'You $hitLabel.$offhandLabel$sparksLabel$poisonLabel$inkLabel $swing. '
            'Thorns reflects ${jsNumberToString(round.thornsHit)}.'
      : 'You $hitLabel.$offhandLabel$sparksLabel$poisonLabel$inkLabel $swing.';
}

void _applyMidRoundEat(GameDatabase db, _TickOutput out) {
  final fed = consumeFoodAfterVictory(db, out.current);
  out.set(fed.save.copyWith(combatEatUntil: null));
  _emitRoundEndAutoEat(out, fed);
}

void _startNextCombatRound(GameDatabase db, _TickOutput out, num atMs) {
  out.set(openCombatRoundClock(db, out.current, atMs));
}

/// Both sides attack at round end; outcomes follow in the same beat.
void _applyDueCombatRound(
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
  if (round.lifestealHealed > 0) {
    out.set(recordLifestealRoundHeal(out.current, round.lifestealHealed));
  }
  var afterRound = out.current.copyWith(
    combatEnemyHp: round.enemyHp,
    currentHp: round.playerHp,
    combatPlayerSwingApplied: true,
    combatPendingRound: round.toPendingRound(),
    combatBossInkActive: round.bossInkActive,
  );
  if ((round.enemyHit ?? 0) > 0) {
    afterRound = notePlayerDamaged(afterRound, roundEnd);
  }
  out.set(afterRound);
  final enemyId = jsString(enemy.raw['Enemy ID']);
  final enemyName = jsString(enemy.raw['Display Name']);
  out.emit(
    CombatRoundEvent(
      enemyId: enemyId,
      enemyName: enemyName,
      playerHit: round.playerHit,
      playerCrit: round.playerCrit,
      offhandHit: round.offhandHit,
      staffHit: round.staffHit,
      poisonHit: round.poisonHit,
      enemyHit: round.enemyHit,
      thornsHit: round.thornsHit,
      outcome: round.outcome,
      bossInkActive: round.bossInkActive,
    ),
  );
  _applyDueCombatOutcome(db, out, activityId, enemy, action, roundEnd, roundMs, random);
}

/// Victory, defeat, or next round from a pending clash.
void _applyDueCombatOutcome(
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
  final round = before.combatPendingRound;
  if (round == null) {
    out.set(
      before.copyWith(
        combatPlayerSwingApplied: false,
        combatPendingRound: null,
        combatRoundStartedAt: isoFromMs(roundEnd),
      ),
    );
    return;
  }

  final enemyId = jsString(enemy.raw['Enemy ID']);
  final enemyName = jsString(enemy.raw['Display Name']);

  if (round.outcome == 'victory') {
    if (isSquidlingVictory(before, enemy)) {
      final squidlingResult = applySquidlingVictory(
        db,
        before.copyWith(combatEnemyHp: 0, currentHp: round.playerHp),
        enemy,
        isoFromMs(roundEnd),
      );
      out.set(squidlingResult.save);
      out.creditCritterTime(roundMs, roundEnd, random);
      out.emit(MessageEvent(squidlingResult.message, topic: 'combat-outcome'));
      if (squidlingResult.xpGained > 0) {
        out.emit(
          RewardsEvent(
            _victoryRewardBundle(
              db,
              before,
              out.current,
              enemy,
              [(skillId: squidlingResult.xpSkillId, xp: squidlingResult.xpGained)],
              const <LootGrant>[],
              0,
              roundEnd,
            ),
          ),
        );
      }
      if (!squidlingResult.bossResumed) {
        out.emit(EnemyDefeatedEvent(enemyId: enemyId, enemyName: enemyName));
        _continueActivity(
          db,
          out,
          activityId,
          roundEnd,
          random,
          'Defeated enemy · activity stopped.',
        );
      }
      return;
    }

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
          victory.xpAwards,
          victory.loot,
          victory.goldGained,
          roundEnd,
          cosmeticsGranted: victory.cosmeticsGranted,
        ),
      ),
    );
    out.emit(
      MessageEvent(
        round.thornsHit > 0
            ? 'Thorns reflects ${jsNumberToString(round.thornsHit)} and defeats $enemyName!'
            : round.playerCrit
            ? 'Critical hit! Defeated $enemyName'
            : 'Defeated $enemyName',
        topic: 'combat-outcome',
      ),
    );
    out.emit(EnemyDefeatedEvent(enemyId: enemyId, enemyName: enemyName));
    _continueActivity(db, out, activityId, roundEnd, random, 'Defeated enemy · activity stopped.');
    return;
  }

  if (round.outcome == 'defeat') {
    out.set(applyCombatDefeat(db, before.copyWith(currentHp: 0), roundEnd));
    out.creditCritterTime(roundMs, roundEnd, random);
    out.emit(PlayerDefeatedEvent(enemyId: enemyId, enemyName: enemyName));
    out.emit(MessageEvent('Defeated by $enemyName. Recovering…', topic: 'combat-outcome'));
    return;
  }

  if (round.bossAddsTriggered && round.bossPendingHp != null) {
    final profile = bossProfile(enemy);
    if (profile?.squidlingEnemyId != null) {
      final addsStarted = beginBossAddsEncounter(
        db,
        before.copyWith(currentHp: round.playerHp, combatBossInkActive: round.bossInkActive),
        enemy,
        profile!,
        round.bossPendingHp!,
        isoFromMs(roundEnd),
      );
      out.set(addsStarted);
      out.creditCritterTime(roundMs, roundEnd, random);
      out.emit(
        MessageEvent(
          '$enemyName releases squidlings! Defeat them to continue.',
          topic: 'combat-phase',
        ),
      );
      return;
    }
  }

  out.set(
    before.copyWith(
      currentHp: round.playerHp,
      combatEnemyHp: round.enemyHp,
      combatSkipEnemyAttack: round.skipNextEnemyAttack,
      combatBossSleepRoundsRemaining: round.bossSleepRoundsRemaining,
      combatBossInkActive: round.bossInkActive,
    ),
  );
  out.creditCritterTime(roundMs, roundEnd, random);
  _startNextCombatRound(db, out, roundEnd);
  out.emit(MessageEvent(_roundMessage(enemy, round), topic: 'combat-swing'));
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

  // Death recovery does not require a running activity. Travel / stop used to
  // wipe deathPauseUntil at 0 HP; stand those saves back up too.
  if (isNotBlank(out.current.deathPauseUntil) ||
      (out.current.currentHp <= 0 && isBlank(out.current.combatEnemyId))) {
    if (isDeathPaused(out.current, nowMs)) return out.result();
    final pauseEnded = isNotBlank(out.current.deathPauseUntil)
        ? jsDateParse(out.current.deathPauseUntil)
        : nowMs;
    out.set(applyDeathRecovery(db, out.current));
    out.emit(const RecoveredEvent());
    final recoveredActivityId = out.current.currentActivityId;
    if (isNotBlank(recoveredActivityId)) {
      _continueActivity(
        db,
        out,
        recoveredActivityId!,
        pauseEnded,
        random,
        'Activity stopped after defeat — requirements no longer met.',
      );
    }
    return out.result();
  }

  final activityId = out.current.currentActivityId;
  if (isBlank(activityId)) return out.result();

  if (isNotBlank(out.current.combatEatUntil) && isBlank(out.current.combatRoundStartedAt)) {
    final eatUntil = jsDateParse(out.current.combatEatUntil);
    if (eatUntil > nowMs) return out.result();
    final continueActivityAfterEat = out.current.combatContinueActivityAfterEat;
    out.set(out.current.copyWith(combatEatUntil: null, combatContinueActivityAfterEat: false));
    if (continueActivityAfterEat) {
      _continueActivity(
        db,
        out,
        activityId!,
        eatUntil,
        random,
        'Defeated enemy · activity stopped.',
      );
      return out.result();
    }
    if (isNotBlank(out.current.combatEnemyId)) {
      out.set(openCombatRoundClock(db, out.current, eatUntil));
    }
    return out.result();
  }

  if (isNotBlank(out.current.combatEnemyId) && isNotBlank(out.current.combatRoundStartedAt)) {
    final roundStart = jsDateParse(out.current.combatRoundStartedAt);
    final roundMs = configNumber(db, 'combat_round_duration', 6) * 1000;
    final playerAt = roundStart + configNumber(db, 'combat_player_attack_at', 6) * 1000;
    final enemyAt = roundStart + configNumber(db, 'combat_enemy_attack_at', 6) * 1000;
    final roundEnd = roundStart + roundMs;
    final eatUntil = isNotBlank(out.current.combatEatUntil)
        ? jsDateParse(out.current.combatEatUntil)
        : double.nan;

    final enemy = getEnemy(db, out.current.combatEnemyId!);
    final action = _actionById(db, out.current.currentActionId);
    if (enemy == null || action == null || out.current.combatEnemyHp == null) {
      out.set(clearActivitySave(out.current, math.min(playerAt, nowMs)));
      return out.result();
    }

    if (eatUntil.toDouble().isFinite && eatUntil <= nowMs) {
      _applyMidRoundEat(db, out);
      return out.result();
    }

    final attackAt = math.min(playerAt, enemyAt);
    if (!out.current.combatPlayerSwingApplied && attackAt <= nowMs) {
      _applyDueCombatRound(
        db,
        out,
        activityId!,
        enemy,
        action,
        math.max(attackAt, roundEnd),
        roundMs,
        random,
      );
      return out.result();
    }

    // Leftover split-swing saves: finish the pending outcome at round end.
    if (out.current.combatPlayerSwingApplied && roundEnd <= nowMs) {
      _applyDueCombatOutcome(db, out, activityId!, enemy, action, roundEnd, roundMs, random);
      return out.result();
    }

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

    final finished = completeProductionCraft(db, out.current, due, random);
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
    if (finished.failed) {
      out.emit(
        MessageEvent('Ruined the ${finished.outputName} — materials lost.', topic: 'general'),
      );
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

    final finished = completeGatheringAction(db, out.current, action, random, due);
    out.set(finished.save);
    out.creditCritterTime(actionState.durationMs, due, random);
    out.emit(
      RewardsEvent(
        ActionRewardBundle(
          id: '${finished.result.actionId}-${jsNumberToString(due)}',
          xpRewards: finished.result.xpRewards,
          loot: finished.result.loot,
          goldGained: finished.result.goldGained,
          cosmeticsGranted: finished.result.cosmeticsGranted,
        ),
        damageTaken: finished.result.damageTaken,
        foodHealed: finished.result.foodHealed,
        showZeroDamageHit: finished.result.showZeroDamageHit,
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
  final waitUntil = bossRespawnWaitUntilMs(db, out.current, activityId);
  if (waitUntil != null && waitUntil > nowMs) return out.result();
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
