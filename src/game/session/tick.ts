import {
  activityStillValid,
  bossRespawnWaitUntilMs,
  clearActivitySave,
  completeGatheringAction,
  generateNextAction,
  restoreActiveActionState,
} from '../activity/engine'
import { configNumber } from '../activity/gathering'
import type { RandomFn } from '../activity/pools'
import { summarizeXpReward } from '../activity/rewardSummary'
import { resolveActivityTransitions } from '../activity/transition'
import type { ActionRewardBundle } from '../activity/types'
import { getSkillProgress } from '../activity/xp'
import {
  applyCombatDefeat,
  applyCombatVictory,
  applyDeathRecovery,
  getEnemy,
  isDeathPaused,
  openCombatRoundClock,
  resolveCombatRound,
} from '../combat/engine'
import { consumeFoodAfterVictory, type FoodConsumption } from '../combat/food'
import { bossProfile } from '../combat/boss'
import { applySquidlingVictory, beginBossAddsEncounter, isSquidlingVictory } from '../combat/bossPhase'
import { recordLifestealRoundHeal } from '../achievements/progress'
import { applyActivityTimeTowardCritters } from '../critters/critters'
import type { ActionRow, EnemyRow, GameDatabase } from '../data/types'
import { completeProductionCraft } from '../production/engine'
import { isStandardProductionActivity } from '../production/recipes'
import type { PlayerSave } from '../save/types'
import { notePlayerDamaged } from '../vitals/regen'
import type { SessionEvent } from './events'

export interface SessionTickResult {
  save: PlayerSave
  /** False when nothing was due, which is the common case between frames. */
  changed: boolean
  events: SessionEvent[]
}

/** Collects the events of one tick and tracks whether the save moved. */
class TickOutput {
  /**
   * `started` is the save the tick was handed, which is not always the one it
   * begins working from: clearing a legacy activity transition already moved the
   * save, and that has to count as a change so the client stores it.
   */
  constructor(save: PlayerSave, started: PlayerSave = save) {
    this.save = save
    this.started = started
  }

  private save: PlayerSave
  private readonly started: PlayerSave
  private readonly events: SessionEvent[] = []

  get current(): PlayerSave {
    return this.save
  }

  set(save: PlayerSave): void {
    this.save = save
  }

  emit(event: SessionEvent): void {
    this.events.push(event)
  }

  /** Credits activity time at the current location and reports any spawn. */
  creditCritterTime(elapsedMs: number, nowMs: number, random: RandomFn): void {
    const result = applyActivityTimeTowardCritters(
      this.save,
      this.save.currentLocationId,
      elapsedMs,
      nowMs,
      random,
    )
    this.save = result.save
    if (result.spawned) {
      this.emit({
        kind: 'critter-spawned',
        critterId: result.spawned.id,
        displayName: result.spawned.displayName,
      })
    }
  }

  result(): SessionTickResult {
    return {
      save: this.save,
      changed: this.save !== this.started || this.events.length > 0,
      events: this.events,
    }
  }
}

function actionById(db: GameDatabase, actionId: string | null): ActionRow | undefined {
  if (!actionId) return undefined
  return db.Actions.find((row) => row['Action ID'] === actionId)
}

/**
 * Rolls the next action for a still-valid activity, or stops the activity.
 *
 * Every catch-up point in a tick ends this way, so the "requirements slipped
 * while you were mid-action" path stays in one place.
 */
function continueActivity(
  db: GameDatabase,
  out: TickOutput,
  activityId: string,
  nowMs: number,
  random: RandomFn,
  stoppedReason: string,
): void {
  if (!activityStillValid(db, out.current, activityId)) {
    out.set(clearActivitySave(out.current, nowMs))
    out.emit({ kind: 'activity-stopped', reason: stoppedReason })
    return
  }
  const generated = generateNextAction(db, out.current, activityId, random, nowMs)
  if (!generated) {
    out.set(clearActivitySave(out.current, nowMs))
    out.emit({ kind: 'activity-stopped', reason: 'No actions remain for this activity.' })
    return
  }
  out.set(generated.save)
}

/** The XP / loot / gold line for a won fight. */
function victoryRewardBundle(
  db: GameDatabase,
  before: PlayerSave,
  after: PlayerSave,
  enemy: EnemyRow,
  xpAwards: { skillId: string; xp: number }[],
  loot: ActionRewardBundle['loot'],
  goldGained: number,
  nowMs: number,
  cosmeticsGranted: NonNullable<ActionRewardBundle['cosmeticsGranted']> = [],
): ActionRewardBundle {
  const xpRewards = xpAwards.flatMap((award) => {
    if (award.xp <= 0) return []
    const levelBefore = getSkillProgress(before, award.skillId).level
    const levelAfter = getSkillProgress(after, award.skillId).level
    const summary = summarizeXpReward(
      db,
      after,
      award.skillId,
      award.xp,
      levelAfter > levelBefore ? levelAfter : null,
    )
    return summary ? [summary] : []
  })
  return {
    id: `combat-${enemy['Enemy ID']}-${nowMs}`,
    xpRewards,
    loot,
    goldGained,
    ...(cosmeticsGranted.length > 0 ? { cosmeticsGranted } : {}),
  }
}

function emitRoundEndAutoEat(out: TickOutput, food: FoodConsumption): void {
  if (!food.consumed || food.healed === 0) return
  out.emit({
    kind: 'food-healed',
    healed: food.healed,
    foodName: String(food.foodName ?? ''),
  })
}

function roundMessage(
  enemy: EnemyRow,
  round: NonNullable<PlayerSave['combatPendingRound']>,
): string {
  const inkLabel = round.bossInkActive ? ' Ink clouds your strike!' : ''
  const hitLabel = round.playerCrit ? `crit for ${round.playerHit}` : `hit ${round.playerHit}`
  const offhandLabel =
    round.offhandHit != null && round.offhandHit > 0 ? ` Off-hand hits ${round.offhandHit}.` : ''
  const sparksLabel =
    round.staffHit != null && round.staffHit > 0 ? ` Sparks hit ${round.staffHit}.` : ''
  const poisonLabel = round.poisonHit != null ? ` Poison hits ${round.poisonHit}.` : ''
  const name = enemy['Display Name']
  if (round.enemyHit == null) {
    return round.enemyAsleep
      ? `You ${hitLabel}.${offhandLabel}${sparksLabel}${poisonLabel}${inkLabel} ${name} sleeps.`
      : `You ${hitLabel}.${offhandLabel}${sparksLabel}${poisonLabel}${inkLabel} ${name} is bound and cannot attack.`
  }
  const swing = round.enemyRampage
    ? `${name} rampages for ${round.enemyHit}`
    : `${name} hits ${round.enemyHit}`
  return round.thornsHit > 0
    ? `You ${hitLabel}.${offhandLabel}${sparksLabel}${poisonLabel}${inkLabel} ${swing}. Thorns reflects ${round.thornsHit}.`
    : `You ${hitLabel}.${offhandLabel}${sparksLabel}${poisonLabel}${inkLabel} ${swing}.`
}

function applyMidRoundEat(db: GameDatabase, out: TickOutput): void {
  const fed = consumeFoodAfterVictory(db, out.current)
  out.set({
    ...fed.save,
    combatEatUntil: null,
  })
  emitRoundEndAutoEat(out, fed)
}

function startNextCombatRound(db: GameDatabase, out: TickOutput, atMs: number): void {
  out.set({
    ...out.current,
    ...openCombatRoundClock(db, atMs),
  })
}

/** Both sides attack at round end; outcomes follow in the same beat. */
function applyDueCombatRound(
  db: GameDatabase,
  out: TickOutput,
  activityId: string,
  enemy: EnemyRow,
  action: ActionRow,
  roundEnd: number,
  roundMs: number,
  random: RandomFn,
): void {
  const before = out.current
  const round = resolveCombatRound(db, before, enemy, before.combatEnemyHp!, random)
  if (round.lifestealHealed > 0) {
    out.set(recordLifestealRoundHeal(out.current, round.lifestealHealed))
  }
  let afterRound: PlayerSave = {
    ...out.current,
    combatEnemyHp: round.enemyHp,
    currentHp: round.playerHp,
    combatPlayerSwingApplied: true,
    combatPendingRound: round,
    combatBossInkActive: round.bossInkActive,
  }
  if ((round.enemyHit ?? 0) > 0) {
    afterRound = notePlayerDamaged(afterRound, roundEnd)
  }
  out.set(afterRound)
  out.emit({
    kind: 'combat-round',
    enemyId: enemy['Enemy ID'],
    enemyName: enemy['Display Name'],
    playerHit: round.playerHit,
    playerCrit: round.playerCrit,
    offhandHit: round.offhandHit,
    staffHit: round.staffHit,
    poisonHit: round.poisonHit,
    enemyHit: round.enemyHit,
    thornsHit: round.thornsHit,
    outcome: round.outcome,
    bossInkActive: round.bossInkActive,
  })
  applyDueCombatOutcome(db, out, activityId, enemy, action, roundEnd, roundMs, random)
}

/** Victory, defeat, or next round from a pending clash. */
function applyDueCombatOutcome(
  db: GameDatabase,
  out: TickOutput,
  activityId: string,
  enemy: EnemyRow,
  action: ActionRow,
  roundEnd: number,
  roundMs: number,
  random: RandomFn,
): void {
  const before = out.current
  const round = before.combatPendingRound
  if (!round) {
    out.set({
      ...before,
      combatPlayerSwingApplied: false,
      combatPendingRound: null,
      combatRoundStartedAt: new Date(roundEnd).toISOString(),
    })
    return
  }

  if (round.outcome === 'victory') {
    if (isSquidlingVictory(before, enemy)) {
      const squidlingResult = applySquidlingVictory(
        db,
        { ...before, combatEnemyHp: 0, currentHp: round.playerHp },
        enemy,
        new Date(roundEnd).toISOString(),
      )
      out.set(squidlingResult.save)
      out.creditCritterTime(roundMs, roundEnd, random)
      out.emit({ kind: 'message', topic: 'combat-outcome', text: squidlingResult.message })
      if (squidlingResult.xpGained > 0) {
        out.emit({
          kind: 'rewards',
          bundle: victoryRewardBundle(
            db,
            before,
            out.current,
            enemy,
            [{ skillId: squidlingResult.xpSkillId, xp: squidlingResult.xpGained }],
            [],
            0,
            roundEnd,
          ),
        })
      }
      if (!squidlingResult.bossResumed) {
        out.emit({
          kind: 'enemy-defeated',
          enemyId: enemy['Enemy ID'],
          enemyName: enemy['Display Name'],
        })
        continueActivity(
          db,
          out,
          activityId,
          roundEnd,
          random,
          'Defeated enemy · activity stopped.',
        )
      }
      return
    }

    const victory = applyCombatVictory(
      db,
      { ...before, combatEnemyHp: 0, currentHp: round.playerHp },
      action,
      enemy,
      random,
      roundEnd,
    )
    out.set(victory.save)
    out.creditCritterTime(roundMs, roundEnd, random)
    out.emit({
      kind: 'rewards',
      bundle: victoryRewardBundle(
        db,
        before,
        out.current,
        enemy,
        victory.xpAwards,
        victory.loot,
        victory.goldGained,
        roundEnd,
        victory.cosmeticsGranted,
      ),
    })
    out.emit({
      kind: 'message',
      topic: 'combat-outcome',
      text: round.thornsHit > 0
        ? `Thorns reflects ${round.thornsHit} and defeats ${enemy['Display Name']}!`
        : round.playerCrit
          ? `Critical hit! Defeated ${enemy['Display Name']}`
          : `Defeated ${enemy['Display Name']}`,
    })
    out.emit({
      kind: 'enemy-defeated',
      enemyId: enemy['Enemy ID'],
      enemyName: enemy['Display Name'],
    })
    continueActivity(
      db,
      out,
      activityId,
      roundEnd,
      random,
      'Defeated enemy · activity stopped.',
    )
    return
  }

  if (round.outcome === 'defeat') {
    out.set(applyCombatDefeat(db, { ...before, currentHp: 0 }, roundEnd))
    out.creditCritterTime(roundMs, roundEnd, random)
    out.emit({
      kind: 'player-defeated',
      enemyId: enemy['Enemy ID'],
      enemyName: enemy['Display Name'],
    })
    out.emit({
      kind: 'message',
      topic: 'combat-outcome',
      text: `Defeated by ${enemy['Display Name']}. Recovering…`,
    })
    return
  }

  if (round.bossAddsTriggered && round.bossPendingHp != null) {
    const profile = bossProfile(enemy)
    if (profile?.squidlingEnemyId) {
      const addsStarted = beginBossAddsEncounter(
        db,
        {
          ...before,
          currentHp: round.playerHp,
          combatBossInkActive: round.bossInkActive,
        },
        enemy,
        profile,
        round.bossPendingHp,
        new Date(roundEnd).toISOString(),
      )
      out.set(addsStarted)
      out.creditCritterTime(roundMs, roundEnd, random)
      out.emit({
        kind: 'message',
        topic: 'combat-phase',
        text: `${enemy['Display Name']} releases squidlings! Defeat them to continue.`,
      })
      return
    }
  }

  out.set({
    ...before,
    currentHp: round.playerHp,
    combatEnemyHp: round.enemyHp,
    combatSkipEnemyAttack: round.skipNextEnemyAttack,
    combatBossSleepRoundsRemaining: round.bossSleepRoundsRemaining,
    combatBossInkActive: round.bossInkActive,
  })
  out.creditCritterTime(roundMs, roundEnd, random)
  startNextCombatRound(db, out, roundEnd)
  out.emit({ kind: 'message', topic: 'combat-swing', text: roundMessage(enemy, round) })
}

/**
 * Advances whatever the save has due at `nowMs`: one combat round, one gathering
 * action, one craft, a death-pause recovery, or the next action for an activity
 * that has none.
 *
 * The live client calls this every frame and applies the events it returns; the
 * unattended resolver is the same rules run in a loop over a past window. Time
 * and randomness are parameters, so a tick is reproducible.
 */
export function advanceSession(
  db: GameDatabase,
  save: PlayerSave,
  nowMs: number,
  random: RandomFn = Math.random,
): SessionTickResult {
  const out = new TickOutput(resolveActivityTransitions(db, save, nowMs, random), save)

  // Death recovery does not require a running activity. Travel / stop used to
  // wipe deathPauseUntil at 0 HP; stand those saves back up too.
  if (
    out.current.deathPauseUntil ||
    (out.current.currentHp <= 0 && !out.current.combatEnemyId)
  ) {
    if (isDeathPaused(out.current, nowMs)) return out.result()
    const pauseEnded = out.current.deathPauseUntil
      ? Date.parse(out.current.deathPauseUntil)
      : nowMs
    out.set(applyDeathRecovery(db, out.current))
    out.emit({ kind: 'recovered' })
    const recoveredActivityId = out.current.currentActivityId
    if (recoveredActivityId) {
      continueActivity(
        db,
        out,
        recoveredActivityId,
        pauseEnded,
        random,
        'Activity stopped after defeat — requirements no longer met.',
      )
    }
    return out.result()
  }

  const activityId = out.current.currentActivityId
  if (!activityId) return out.result()

  // Legacy inter-round eat pause (no active round clock). Mid-round eat is
  // handled below and does not block the attack.
  if (out.current.combatEatUntil && !out.current.combatRoundStartedAt) {
    const eatUntil = Date.parse(out.current.combatEatUntil)
    if (eatUntil > nowMs) return out.result()
    const continueActivityAfterEat = out.current.combatContinueActivityAfterEat
    out.set({
      ...out.current,
      combatEatUntil: null,
      combatContinueActivityAfterEat: false,
    })
    if (continueActivityAfterEat) {
      continueActivity(
        db,
        out,
        activityId,
        eatUntil,
        random,
        'Defeated enemy · activity stopped.',
      )
      return out.result()
    }
    if (out.current.combatEnemyId) {
      out.set({
        ...out.current,
        ...openCombatRoundClock(db, eatUntil),
      })
    }
    return out.result()
  }

  if (out.current.combatEnemyId && out.current.combatRoundStartedAt) {
    const roundStart = Date.parse(out.current.combatRoundStartedAt)
    const roundMs = configNumber(db, 'combat_round_duration', 6) * 1000
    const playerAt =
      roundStart + configNumber(db, 'combat_player_attack_at', 6) * 1000
    const enemyAt =
      roundStart + configNumber(db, 'combat_enemy_attack_at', 6) * 1000
    const roundEnd = roundStart + roundMs
    const eatUntil = out.current.combatEatUntil
      ? Date.parse(out.current.combatEatUntil)
      : Number.NaN

    const enemy = getEnemy(db, out.current.combatEnemyId)
    const action = actionById(db, out.current.currentActionId)
    if (!enemy || !action || out.current.combatEnemyHp == null) {
      out.set(clearActivitySave(out.current, Math.min(playerAt, nowMs)))
      return out.result()
    }

    if (Number.isFinite(eatUntil) && eatUntil <= nowMs) {
      applyMidRoundEat(db, out)
      return out.result()
    }

    const attackAt = Math.min(playerAt, enemyAt)
    if (!out.current.combatPlayerSwingApplied && attackAt <= nowMs) {
      applyDueCombatRound(
        db,
        out,
        activityId,
        enemy,
        action,
        Math.max(attackAt, roundEnd),
        roundMs,
        random,
      )
      return out.result()
    }

    // Leftover split-swing saves: finish the pending outcome at round end.
    if (out.current.combatPlayerSwingApplied && roundEnd <= nowMs) {
      applyDueCombatOutcome(db, out, activityId, enemy, action, roundEnd, roundMs, random)
      return out.result()
    }

    return out.result()
  }

  // Standard production resolves one craft at a time against its own timer.
  if (out.current.productionRecipeId) {
    const startedAt = out.current.actionStartedAt
    const durationMs = out.current.actionDurationMs
    if (!startedAt || !durationMs) return out.result()
    const due = Date.parse(startedAt) + durationMs
    if (due > nowMs) return out.result()

    const finished = completeProductionCraft(db, out.current, due, random)
    if (!finished) {
      out.emit({ kind: 'inventory-full' })
      return out.result()
    }
    out.set(finished.save)
    out.creditCritterTime(durationMs, due, random)
    const output = finished.reward.loot[0]
    if (output) {
      out.emit({
        kind: 'craft-completed',
        itemId: output.itemId,
        displayName: output.displayName,
      })
    }
    if (finished.failed) {
      out.emit({
        kind: 'message',
        topic: 'general',
        text: `Ruined the ${finished.outputName} — materials lost.`,
      })
    }
    out.emit({ kind: 'rewards', bundle: finished.reward })
    return out.result()
  }

  const actionState = restoreActiveActionState(out.current)
  if (actionState) {
    const due = actionState.startedAtMs + actionState.durationMs
    if (due > nowMs) return out.result()

    const action = actionById(db, actionState.actionId)
    if (!action) {
      out.set(clearActivitySave(out.current, due))
      return out.result()
    }

    const finished = completeGatheringAction(db, out.current, action, random, due)
    out.set(finished.save)
    out.creditCritterTime(actionState.durationMs, due, random)
    const damageTaken = finished.result.damageTaken ?? 0
    const foodHealed = finished.result.foodHealed ?? 0
    const showZeroDamageHit = finished.result.showZeroDamageHit ?? false
    out.emit({
      kind: 'rewards',
      bundle: {
        id: `${finished.result.actionId}-${due}`,
        xpRewards: finished.result.xpRewards,
        loot: finished.result.loot,
        goldGained: finished.result.goldGained,
        ...(finished.result.cosmeticsGranted?.length
          ? { cosmeticsGranted: finished.result.cosmeticsGranted }
          : {}),
      },
      ...(damageTaken !== 0 || foodHealed !== 0 || showZeroDamageHit
        ? { damageTaken, foodHealed, showZeroDamageHit }
        : {}),
    })
    continueActivity(
      db,
      out,
      activityId,
      due,
      random,
      'Activity stopped — requirements are no longer met.',
    )
    return out.result()
  }

  // An activity is running with nothing rolled yet. Standard production waits
  // for the player to pick a recipe instead of rolling an action.
  const activity = db.Activities.find((row) => row['Activity ID'] === activityId)
  if (activity && isStandardProductionActivity(db, activity)) return out.result()
  const waitUntil = bossRespawnWaitUntilMs(db, out.current, activityId)
  if (waitUntil != null && waitUntil > nowMs) return out.result()
  continueActivity(
    db,
    out,
    activityId,
    nowMs,
    random,
    'Activity stopped — requirements are no longer met.',
  )
  return out.result()
}
