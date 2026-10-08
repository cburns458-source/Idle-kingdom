import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../achievements/progress.dart';
import '../activity/engine.dart';
import '../activity/transition.dart';
import '../combat/boss.dart';
import '../combat/boss_phase.dart';
import '../combat/engine.dart';
import '../combat/food.dart';
import '../config.dart';
import '../critters/critters.dart';
import '../js_compat.dart';
import '../production/engine.dart';
import '../rng/mulberry32.dart';
import '../save/generated/save_models.dart';
import '../save/play_time.dart';
import '../vitals/regen.dart';
import '../time.dart';
import 'summary.dart';

/// Safety valve on the combat/gathering catch-up loop (one discrete round/action
/// per step). Sized relative to config so it can never fall short of the
/// advertised unattended cap for the fastest possible tick (today, combat
/// rounds), with a generous margin for shorter future ticks. If it's ever
/// exhausted anyway, [resolveUnattendedProgress] only advances the save's
/// catch-up anchor as far as the simulation actually got, so the remainder is
/// caught up on the next load instead of being silently lost.
num _maxUnattendedSteps(GameDatabase db) {
  final capMs = unattendedCapMs(db);
  final roundMs = math.max(1, configNumber(db, 'combat_round_duration', 6) * 1000);
  final minimumTickMs = math.min(roundMs, 1000);
  return math.max(20000, (capMs / minimumTickMs).ceil() + 1000);
}

/// Next discrete combat clock edge: mid-round eat or end-of-round clash.
num? _nextCombatDueMs(GameDatabase db, PlayerSave save) {
  if (isNotBlank(save.combatEatUntil) && isBlank(save.combatRoundStartedAt)) {
    final eatUntil = jsDateParse(save.combatEatUntil);
    return eatUntil.toDouble().isFinite ? eatUntil : null;
  }
  if (isBlank(save.combatEnemyId) || isBlank(save.combatRoundStartedAt)) return null;
  final roundStart = jsDateParse(save.combatRoundStartedAt);
  if (!roundStart.toDouble().isFinite) return null;
  final playerAt = roundStart + configNumber(db, 'combat_player_attack_at', 6) * 1000;
  final enemyAt = roundStart + configNumber(db, 'combat_enemy_attack_at', 6) * 1000;
  final roundEnd = roundStart + math.max(1, configNumber(db, 'combat_round_duration', 6) * 1000);
  final attackAt = save.combatPlayerSwingApplied ? roundEnd : math.min(playerAt, enemyAt);
  if (isNotBlank(save.combatEatUntil)) {
    final eatUntil = jsDateParse(save.combatEatUntil);
    if (eatUntil.toDouble().isFinite && eatUntil <= attackAt) return eatUntil;
  }
  return attackAt;
}

PlayerSave _continueAfterCombat(GameDatabase db, PlayerSave save, num atMs, RandomFn random) {
  final activityId = save.currentActivityId;
  if (activityId == null || !activityStillValid(db, save, activityId)) {
    return clearActivitySave(save, atMs);
  }
  final generated = generateNextAction(db, save, activityId, random, atMs);
  return generated != null ? generated.save : save;
}

/// Same wording as the live tick's combat-round message event.
String _combatRoundMessage(EnemyRow enemy, CombatPendingRound round) {
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

String _combatVictoryMessage(EnemyRow enemy, CombatPendingRound round) {
  final enemyName = jsString(enemy.raw['Display Name']);
  if (round.thornsHit > 0) {
    return 'Thorns reflects ${jsNumberToString(round.thornsHit)} and defeats $enemyName!';
  }
  if (round.playerCrit) return 'Critical hit! Defeated $enemyName';
  return 'Defeated $enemyName';
}

class UnattendedResult {
  const UnattendedResult({
    required this.save,
    required this.changed,
    required this.messages,
    required this.gatheringActions,
    required this.craftsCompleted,
    required this.combatVictories,
    required this.combatDeaths,
    required this.crittersSpawned,
    required this.effectiveElapsedMs,
  });

  final PlayerSave save;
  final bool changed;
  final List<String> messages;
  final num gatheringActions;
  final num craftsCompleted;
  final num combatVictories;
  final num combatDeaths;
  final num crittersSpawned;
  final num effectiveElapsedMs;

  /// True when catch-up finished at least one gather, craft, fight, or spawn.
  bool get hasCreditedWork =>
      gatheringActions + craftsCompleted + combatVictories + combatDeaths + crittersSpawned > 0;

  Map<String, Object?> toJson() => <String, Object?>{
    'save': save.toJson(),
    'changed': changed,
    'messages': messages,
    'gatheringActions': gatheringActions,
    'craftsCompleted': craftsCompleted,
    'combatVictories': combatVictories,
    'combatDeaths': combatDeaths,
    'crittersSpawned': crittersSpawned,
    'effectiveElapsedMs': effectiveElapsedMs,
  };
}

num unattendedCapMs(GameDatabase db) {
  return math.max(0, configNumber(db, 'unattended_cap', 24) * 3600000);
}

PlayerSave stampUnattendedProgressAt(PlayerSave save, num nowMs) {
  return save.copyWith(unattendedProgressAt: isoFromMs(nowMs));
}

/// The anchor the catch-up window starts from, falling back to the clock when the
/// save carries no usable timestamp.
num _anchorMs(PlayerSave save, num nowMs) {
  final raw = isNotBlank(save.unattendedProgressAt)
      ? jsDateParse(save.unattendedProgressAt)
      : double.nan;
  return raw.isFinite ? raw : nowMs;
}

/// Catch up Gathering, Combat, and Standard Production for time away, using the
/// same engines as live play and the configured unattended cap.
UnattendedResult resolveUnattendedProgress(
  GameDatabase db,
  PlayerSave save,
  num nowMs,
  RandomFn random,
) {
  final capMs = unattendedCapMs(db);
  final anchor = _anchorMs(save, nowMs);
  final endMs = math.min(nowMs, anchor + capMs);
  final effectiveElapsedMs = math.max(0, endMs - anchor);

  var current = resolveActivityTransitions(db, save, endMs, random);
  final messages = <String>[];
  num gatheringActions = 0;
  num craftsCompleted = 0;
  num combatVictories = 0;
  num combatDeaths = 0;
  num crittersSpawned = 0;
  num steps = 0;
  final maxSteps = _maxUnattendedSteps(db);
  // Tracks how far the combat/gathering simulation's own clock has actually
  // advanced, so we can tell "ran out of step budget mid-catch-up" apart from
  // "genuinely nothing more to simulate in this window."
  num lastResolvedMs = anchor;
  var hitStepLimit = false;

  void pushCritterSpawn(CritterDef? spawned) {
    if (spawned == null) return;
    crittersSpawned += 1;
    messages.add('A ${spawned.displayName} appeared while you were away.');
  }

  final production = resolveProductionProgress(db, current, endMs, random);
  if (production.blockedByInventory) {
    messages.add('Crafting paused: inventory is full.');
  }
  if (production.craftsCompleted > 0 || production.activityMs > 0) {
    current = production.save;
    craftsCompleted = production.craftsCompleted;
    messages.addAll(production.messages.take(6));
    if (production.messages.length > 6) {
      messages.add('…and ${production.messages.length - 6} more crafts.');
    }
    if (production.activityMs > 0) {
      final critter = applyActivityTimeTowardCritters(
        current,
        current.currentLocationId,
        production.activityMs,
        endMs,
        random,
      );
      current = critter.save;
      pushCritterSpawn(critter.spawned);
      current = applyNaturalHpRegen(
        db,
        current,
        production.activityMs,
        anchor + production.activityMs,
      ).save;
      lastResolvedMs = anchor + production.activityMs;
    }
  }

  while (true) {
    if (steps >= maxSteps) {
      hitStepLimit = true;
      break;
    }
    steps += 1;

    // Death pause: wait out remaining pause, then stand up even with no activity.
    final pauseLeft = deathPauseRemainingMs(current, endMs);
    if (isNotBlank(current.deathPauseUntil) && pauseLeft > 0) {
      break;
    }
    if ((isNotBlank(current.deathPauseUntil) && pauseLeft <= 0) ||
        (current.currentHp <= 0 && isBlank(current.combatEnemyId))) {
      final pauseEnded = isNotBlank(current.deathPauseUntil)
          ? jsDateParse(current.deathPauseUntil)
          : endMs;
      final resumed = applyDeathRecovery(db, current);
      messages.add('Recovered from defeat while away.');
      lastResolvedMs = math.max(pauseEnded, anchor);
      final activityId = resumed.currentActivityId;
      if (isBlank(activityId)) {
        current = resumed;
        break;
      }
      if (!activityStillValid(db, resumed, activityId!)) {
        current = clearActivitySave(resumed, pauseEnded);
        messages.add('Activity stopped after defeat — requirements no longer met.');
        break;
      }
      final resumeAt = math.max(pauseEnded, anchor);
      final generated = generateNextAction(db, resumed, activityId, random, resumeAt);
      current = generated != null ? generated.save : resumed;
      lastResolvedMs = resumeAt;
      continue;
    }

    if (isBlank(current.currentActivityId)) break;
    // Production is batch-resolved above against the capped clock.
    if (isNotBlank(current.productionRecipeId)) break;

    // Combat phases + inter-round eat — same edges as live tick rules.
    final combatDue = _nextCombatDueMs(db, current);
    if (combatDue != null) {
      if (combatDue > endMs) break;

      if (isNotBlank(current.combatEatUntil) && isBlank(current.combatRoundStartedAt)) {
        final continueActivityAfterEat = current.combatContinueActivityAfterEat;
        current = current.copyWith(combatEatUntil: null, combatContinueActivityAfterEat: false);
        if (continueActivityAfterEat) {
          final activityId = current.currentActivityId!;
          if (!activityStillValid(db, current, activityId)) {
            current = clearActivitySave(current, combatDue);
            messages.add('Defeated enemy · activity stopped.');
            break;
          }
          final generated = generateNextAction(db, current, activityId, random, combatDue);
          current = generated != null ? generated.save : current;
          lastResolvedMs = combatDue;
          continue;
        }
        if (isNotBlank(current.combatEnemyId)) {
          current = openCombatRoundClock(db, current, combatDue);
        }
        lastResolvedMs = combatDue;
        continue;
      }

      if (isNotBlank(current.combatEatUntil) && isNotBlank(current.combatRoundStartedAt)) {
        final fed = consumeFoodAfterVictory(db, current);
        current = fed.save.copyWith(combatEatUntil: null);
        lastResolvedMs = combatDue;
        continue;
      }

      final roundStart = jsDateParse(current.combatRoundStartedAt);
      final roundMs = configNumber(db, 'combat_round_duration', 6) * 1000;
      final playerAt = roundStart + configNumber(db, 'combat_player_attack_at', 6) * 1000;
      final enemyAt = roundStart + configNumber(db, 'combat_enemy_attack_at', 6) * 1000;
      final roundEnd = math.max(enemyAt, roundStart + roundMs);

      final enemy = getEnemy(db, current.combatEnemyId!);
      final action = isNotBlank(current.currentActionId)
          ? db.actions.firstWhereOrNull((row) => row.raw['Action ID'] == current.currentActionId)
          : null;
      if (enemy == null || action == null || current.combatEnemyHp == null) {
        current = clearActivitySave(current, math.min(playerAt, combatDue));
        break;
      }

      // End-of-round clash: both sides, then outcome in the same step.
      if (!current.combatPlayerSwingApplied) {
        final round = resolveCombatRound(db, current, enemy, current.combatEnemyHp!, random);
        if (round.lifestealHealed > 0) {
          current = recordLifestealRoundHeal(current, round.lifestealHealed);
        }
        var afterRound = current.copyWith(
          combatEnemyHp: round.enemyHp,
          currentHp: round.playerHp,
          combatPlayerSwingApplied: true,
          combatPendingRound: round.toPendingRound(),
          combatBossInkActive: round.bossInkActive,
        );
        if ((round.enemyHit ?? 0) > 0) {
          afterRound = notePlayerDamaged(afterRound, roundEnd);
        }
        current = afterRound;
      }

      // Outcome phase (also finishes leftover split-swing saves).
      final pending = current.combatPendingRound;
      if (pending == null) {
        current = current.copyWith(
          combatPlayerSwingApplied: false,
          combatPendingRound: null,
          combatRoundStartedAt: isoFromMs(roundEnd),
        );
        lastResolvedMs = combatDue;
        continue;
      }

      if (pending.outcome == 'victory') {
        if (isSquidlingVictory(current, enemy)) {
          final squidlingResult = applySquidlingVictory(
            db,
            current.copyWith(combatEnemyHp: 0, currentHp: pending.playerHp),
            enemy,
            isoFromMs(roundEnd),
          );
          var next = squidlingResult.save;
          final critter = applyActivityTimeTowardCritters(
            next,
            next.currentLocationId,
            roundMs,
            roundEnd,
            random,
          );
          next = critter.save;
          pushCritterSpawn(critter.spawned);
          if (!isIncompleteCombatAwayLine(squidlingResult.message, 'combat-phase')) {
            messages.add(squidlingResult.message);
          }
          if (squidlingResult.bossResumed) {
            current = next;
            lastResolvedMs = combatDue;
            continue;
          }
          combatVictories += 1;
          current = _continueAfterCombat(db, next, roundEnd, random);
          lastResolvedMs = combatDue;
          continue;
        }

        final victory = applyCombatVictory(
          db,
          current.copyWith(combatEnemyHp: 0, currentHp: pending.playerHp),
          action,
          enemy,
          random,
          // Credit the kill to the hour it happened in, not to the hour the
          // player happens to come back in.
          roundEnd,
        );
        combatVictories += 1;
        var next = victory.save;
        final critter = applyActivityTimeTowardCritters(
          next,
          next.currentLocationId,
          roundMs,
          roundEnd,
          random,
        );
        next = critter.save;
        pushCritterSpawn(critter.spawned);
        messages.add(_combatVictoryMessage(enemy, pending));
        current = _continueAfterCombat(db, next, roundEnd, random);
        lastResolvedMs = combatDue;
        continue;
      }

      if (pending.outcome == 'defeat') {
        combatDeaths += 1;
        var defeated = applyCombatDefeat(db, current.copyWith(currentHp: 0), roundEnd);
        final critter = applyActivityTimeTowardCritters(
          defeated,
          defeated.currentLocationId,
          roundMs,
          roundEnd,
          random,
        );
        defeated = critter.save;
        pushCritterSpawn(critter.spawned);
        current = defeated;
        lastResolvedMs = combatDue;
        messages.add('Defeated by ${jsString(enemy.raw['Display Name'])}. Recovering…');
        continue;
      }

      var continued = current.copyWith(
        currentHp: pending.playerHp,
        combatEnemyHp: pending.enemyHp,
        combatSkipEnemyAttack: pending.skipNextEnemyAttack,
        combatBossSleepRoundsRemaining: pending.bossSleepRoundsRemaining,
        combatBossInkActive: pending.bossInkActive,
      );

      if (pending.bossAddsTriggered && pending.bossPendingHp != null) {
        final profile = bossProfile(enemy);
        if (profile?.squidlingEnemyId != null) {
          continued = beginBossAddsEncounter(
            db,
            continued,
            enemy,
            profile!,
            pending.bossPendingHp!,
            isoFromMs(roundEnd),
          );
          // Mid-fight phase chatter — keep out of the away summary.
          final phaseLine =
              '${jsString(enemy.raw['Display Name'])} releases squidlings! Defeat them to continue.';
          if (!isIncompleteCombatAwayLine(phaseLine, 'combat-phase')) {
            messages.add(phaseLine);
          }
          final critter = applyActivityTimeTowardCritters(
            continued,
            continued.currentLocationId,
            roundMs,
            roundEnd,
            random,
          );
          continued = critter.save;
          pushCritterSpawn(critter.spawned);
          current = continued;
          lastResolvedMs = combatDue;
          continue;
        }
      }

      final critter = applyActivityTimeTowardCritters(
        continued,
        continued.currentLocationId,
        roundMs,
        roundEnd,
        random,
      );
      continued = critter.save;
      pushCritterSpawn(critter.spawned);
      final swingLine = _combatRoundMessage(enemy, pending);
      if (!isIncompleteCombatAwayLine(swingLine, 'combat-swing')) {
        messages.add(swingLine);
      }
      current = openCombatRoundClock(db, continued, roundEnd);
      lastResolvedMs = combatDue;
      continue;
    }

    // Gathering action in progress.
    final actionState = restoreActiveActionState(current);
    if (actionState != null) {
      final due = actionState.startedAtMs + actionState.durationMs;
      if (due > endMs) break;

      final action = db.actions.firstWhereOrNull(
        (row) => row.raw['Action ID'] == actionState.actionId,
      );
      if (action == null) {
        current = clearActivitySave(current, due);
        break;
      }

      final completed = completeGatheringAction(db, current, action, random, due);
      gatheringActions += 1;
      // Clear completed action fields before generating the next one.
      var next = clearCombatSave(
        completed.save.copyWith(
          currentActionId: null,
          actionStartedAt: null,
          actionDurationMs: null,
        ),
      );
      final critter = applyActivityTimeTowardCritters(
        next,
        next.currentLocationId,
        actionState.durationMs,
        due,
        random,
      );
      next = critter.save;
      pushCritterSpawn(critter.spawned);
      next = applyNaturalHpRegen(db, next, actionState.durationMs, due).save;

      final activityId = current.currentActivityId!;
      if (!activityStillValid(db, next, activityId)) {
        current = clearActivitySave(next, due);
        messages.add('Activity stopped — requirements no longer met.');
        break;
      }
      final generated = generateNextAction(db, next, activityId, random, due);
      current = generated != null ? generated.save : next;
      lastResolvedMs = due;
      continue;
    }

    // Activity running but no action yet — generate one at the sim clock.
    if (isNotBlank(current.currentActivityId) && isBlank(current.productionRecipeId)) {
      final activityId = current.currentActivityId!;
      if (!activityStillValid(db, current, activityId)) {
        current = clearActivitySave(current, endMs);
        messages.add('Activity stopped — requirements no longer met.');
        break;
      }
      final waitUntil = bossRespawnWaitUntilMs(db, current, activityId);
      final startAt = waitUntil ?? endMs;
      if (startAt > endMs) break;
      final generated = generateNextAction(db, current, activityId, random, startAt);
      if (generated == null) break;
      // If generation only stamps "now" without being due, avoid looping forever:
      // only accept if something actionable was created.
      if (generated.save.currentActionId == current.currentActionId &&
          generated.save.combatEnemyId == current.combatEnemyId) {
        break;
      }
      current = generated.save;
      lastResolvedMs = startAt;
      continue;
    }

    break;
  }

  if (gatheringActions > 0) {
    messages.insert(
      0,
      'Gathered through ${jsNumberToString(gatheringActions)} '
      'action${gatheringActions == 1 ? '' : 's'} while away.',
    );
  }
  if (combatVictories > 0) {
    messages.insert(
      0,
      'Won ${jsNumberToString(combatVictories)} '
      'fight${combatVictories == 1 ? '' : 's'} while away.',
    );
  }
  if (craftsCompleted > 0 && !messages.any((line) => line.contains('Crafted'))) {
    messages.insert(
      0,
      'Completed ${jsNumberToString(craftsCompleted)} '
      'craft${craftsCompleted == 1 ? '' : 's'} while away.',
    );
  }

  // Normally we're fully caught up to `endMs` (which is already <= nowMs), so
  // it's safe to stamp `nowMs`. But if the combat/gathering loop ran out of step
  // budget while there was still more due within the window, only advance the
  // anchor as far as the simulation actually got — the remainder will be caught
  // up on the next load instead of being lost.
  // Regen runs even mid-combat once the 60s no-damage gate has passed.
  current = applyNaturalHpRegen(db, current, endMs - lastResolvedMs, endMs).save;

  final stampAt = hitStepLimit ? math.min(nowMs, lastResolvedMs) : nowMs;
  final stamped = accruePlayTime(stampUnattendedProgressAt(current, stampAt), effectiveElapsedMs);
  const deep = DeepCollectionEquality();
  final changed =
      !identical(stamped, save) &&
      (gatheringActions > 0 ||
          craftsCompleted > 0 ||
          combatVictories > 0 ||
          combatDeaths > 0 ||
          crittersSpawned > 0 ||
          stamped.unattendedProgressAt != save.unattendedProgressAt ||
          stamped.playTimeMs != save.playTimeMs ||
          stamped.currentActionId != save.currentActionId ||
          stamped.combatEnemyHp != save.combatEnemyHp ||
          stamped.currentHp != save.currentHp ||
          stamped.gold != save.gold ||
          stamped.deathPauseUntil != save.deathPauseUntil ||
          stamped.productionQuantityRemaining != save.productionQuantityRemaining ||
          !deep.equals(
            _jsonList(stamped.inventory, (stack) => stack.toJson()),
            _jsonList(save.inventory, (stack) => stack.toJson()),
          ) ||
          !deep.equals(
            _jsonList(stamped.skills, (skill) => skill.toJson()),
            _jsonList(save.skills, (skill) => skill.toJson()),
          ) ||
          !deep.equals(
            _jsonList(stamped.activeCritterSpawns, (spawn) => spawn.toJson()),
            _jsonList(save.activeCritterSpawns, (spawn) => spawn.toJson()),
          ) ||
          !deep.equals(stamped.critterProgressMs, save.critterProgressMs));

  return UnattendedResult(
    save: stamped,
    changed: changed,
    messages: messages,
    gatheringActions: gatheringActions,
    craftsCompleted: craftsCompleted,
    combatVictories: combatVictories,
    combatDeaths: combatDeaths,
    crittersSpawned: crittersSpawned,
    effectiveElapsedMs: effectiveElapsedMs,
  );
}

/// Stands in for the `JSON.stringify` comparisons the change check uses; the
/// generated models define no `==`, so their JSON form is what can be compared.
List<Map<String, Object?>> _jsonList<T>(List<T> entries, Map<String, Object?> Function(T) toJson) {
  return entries.map(toJson).toList();
}
