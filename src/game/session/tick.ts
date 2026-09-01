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
  deathPauseRemainingMs,
  getEnemy,
  resolveCombatRound,
  shouldSkipVictoryHealingFood,
} from '../combat/engine'
import { bossProfile } from '../combat/boss'
import { applySquidlingVictory, beginBossAddsEncounter, isSquidlingVictory } from '../combat/bossPhase'
import { applyActivityTimeTowardCritters } from '../critters/critters'
import type { ActionRow, EnemyRow, GameDatabase } from '../data/types'
import { completeProductionCraft } from '../production/engine'
import { isStandardProductionActivity } from '../production/recipes'
import type { PlayerSave } from '../save/types'
import type { SessionEvent } from './events'

const COMBAT_SKILL_ID = 'SKL-0001'

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
  xpGained: number,
  loot: ActionRewardBundle['loot'],
  goldGained: number,
  nowMs: number,
  xpSkillId: string = COMBAT_SKILL_ID,
): ActionRewardBundle {
  const levelBefore = getSkillProgress(before, xpSkillId).level
  const levelAfter = getSkillProgress(after, xpSkillId).level
  const summary = summarizeXpReward(
    db,
    after,
    xpSkillId,
    xpGained,
    levelAfter > levelBefore ? levelAfter : null,
  )
  return {
    id: `combat-${enemy['Enemy ID']}-${nowMs}`,
    xpRewards: summary ? [summary] : [],
    loot,
    goldGained,
  }
}

function roundMessage(enemy: EnemyRow, round: ReturnType<typeof resolveCombatRound>): string {
  const inkLabel = round.bossInkActive ? ' Ink clouds your strike!' : ''
  const hitLabel = round.playerCrit ? `crit for ${round.playerHit}` : `hit ${round.playerHit}`
  const offhandLabel =
    round.offhandHit != null && round.offhandHit > 0 ? ` Off-hand hits ${round.offhandHit}.` : ''
  const sparksLabel =
    round.staffHit != null && round.staffHit > 0 ? ` Sparks hit ${round.staffHit}.` : ''
  const name = enemy['Display Name']
  if (round.enemyHit == null) {
    return round.enemyAsleep
      ? `You ${hitLabel}.${offhandLabel}${sparksLabel}${inkLabel} ${name} sleeps.`
      : `You ${hitLabel}.${offhandLabel}${sparksLabel}${inkLabel} ${name} is bound and cannot attack.`
  }
  const swing = round.enemyRampage
    ? `${name} rampages for ${round.enemyHit}`
    : `${name} hits ${round.enemyHit}`
  return round.thornsHit > 0
    ? `You ${hitLabel}.${offhandLabel}${sparksLabel}${inkLabel} ${swing}. Thorns reflects ${round.thornsHit}.`
    : `You ${hitLabel}.${offhandLabel}${sparksLabel}${inkLabel} ${swing}.`
}

function resolveDueCombatRound(
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
  out.emit({
    kind: 'combat-round',
    enemyId: enemy['Enemy ID'],
    enemyName: enemy['Display Name'],
    playerHit: round.playerHit,
    playerCrit: round.playerCrit,
    offhandHit: round.offhandHit,
    staffHit: round.staffHit,
    enemyHit: round.enemyHit,
    thornsHit: round.thornsHit,
    outcome: round.outcome,
  })

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
      out.emit({ kind: 'message', text: squidlingResult.message })
      if (squidlingResult.xpGained > 0) {
        out.emit({
          kind: 'rewards',
          bundle: victoryRewardBundle(
            db,
            before,
            out.current,
            enemy,
            squidlingResult.xpGained,
            [],
            0,
            roundEnd,
            squidlingResult.xpSkillId,
          ),
        })
      }
      if (!squidlingResult.bossResumed) {
        out.emit({
          kind: 'enemy-defeated',
          enemyId: enemy['Enemy ID'],
          enemyName: enemy['Display Name'],
        })
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
      {
        skipVictoryFood: shouldSkipVictoryHealingFood(
          enemy,
          before.combatEnemyHp,
          round.enemyHit,
          round.playerHp,
          before.currentHp,
        ),
      },
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
        victory.xpGained,
        victory.loot,
        victory.goldGained,
        roundEnd,
        victory.xpSkillId,
      ),
    })
    out.emit({
      kind: 'message',
      text: victory.foodConsumed
        ? `Ate ${victory.foodName} (${victory.foodHealed > 0 ? '+' : ''}${victory.foodHealed} HP)`
        : round.thornsHit > 0
          ? `Thorns reflects ${round.thornsHit} and defeats ${enemy['Display Name']}!`
          : round.playerCrit
            ? `Critical hit! Defeated ${enemy['Display Name']}`
            : `Defeated ${enemy['Display Name']}`,
    })
    if (victory.foodConsumed && victory.foodHealed !== 0) {
      out.emit({
        kind: 'food-healed',
        healed: victory.foodHealed,
        foodName: String(victory.foodName ?? ''),
      })
    }
    out.emit({
      kind: 'enemy-defeated',
      enemyId: enemy['Enemy ID'],
      enemyName: enemy['Display Name'],
    })
    continueActivity(db, out, activityId, roundEnd, random, `Defeated ${enemy['Display Name']} · activity stopped.`)
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
    out.emit({ kind: 'message', text: `Defeated by ${enemy['Display Name']}. Recovering…` })
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
        text: `${enemy['Display Name']} releases squidlings! Defeat them to continue.`,
      })
      return
    }
  }

  const continued = {
    ...before,
    currentHp: round.playerHp,
    combatEnemyHp: round.enemyHp,
    combatRoundStartedAt: new Date(roundEnd).toISOString(),
    combatSkipEnemyAttack: round.skipNextEnemyAttack,
    combatBossSleepRoundsRemaining: round.bossSleepRoundsRemaining,
    combatBossInkActive: round.bossInkActive,
  }
  out.set(continued)
  out.creditCritterTime(roundMs, roundEnd, random)
  out.emit({ kind: 'message', text: roundMessage(enemy, round) })
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

  const activityId = out.current.currentActivityId
  if (!activityId) return out.result()

  // Death pause blocks everything until it elapses, then play resumes.
  if (out.current.deathPauseUntil) {
    if (deathPauseRemainingMs(out.current, nowMs) > 0) return out.result()
    const pauseEnded = Date.parse(out.current.deathPauseUntil)
    out.set({ ...out.current, deathPauseUntil: null })
    continueActivity(
      db,
      out,
      activityId,
      pauseEnded,
      random,
      'Activity stopped after defeat — requirements no longer met.',
    )
    out.emit({ kind: 'recovered' })
    return out.result()
  }

  if (out.current.combatEnemyId && out.current.combatRoundStartedAt) {
    const roundMs = configNumber(db, 'combat_round_duration', 4) * 1000
    const roundEnd = Date.parse(out.current.combatRoundStartedAt) + roundMs
    if (roundEnd > nowMs) return out.result()

    const enemy = getEnemy(db, out.current.combatEnemyId)
    const action = actionById(db, out.current.currentActionId)
    if (!enemy || !action || out.current.combatEnemyHp == null) {
      out.set(clearActivitySave(out.current, roundEnd))
      return out.result()
    }
    resolveDueCombatRound(db, out, activityId, enemy, action, roundEnd, roundMs, random)
    return out.result()
  }

  // Standard production resolves one craft at a time against its own timer.
  if (out.current.productionRecipeId) {
    const startedAt = out.current.actionStartedAt
    const durationMs = out.current.actionDurationMs
    if (!startedAt || !durationMs) return out.result()
    const due = Date.parse(startedAt) + durationMs
    if (due > nowMs) return out.result()

    const finished = completeProductionCraft(db, out.current, due)
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

    const finished = completeGatheringAction(db, out.current, action, random)
    out.set(finished.save)
    out.creditCritterTime(actionState.durationMs, due, random)
    out.emit({
      kind: 'rewards',
      bundle: {
        id: `${finished.result.actionId}-${due}`,
        xpRewards: finished.result.xpRewards,
        loot: finished.result.loot,
        goldGained: finished.result.goldGained,
      },
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
