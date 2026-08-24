import {
  activityStillValid,
  clearActivitySave,
  completeGatheringAction,
  generateNextAction,
  restoreActiveActionState,
  bossRespawnWaitUntilMs,
} from '../activity/engine'
import { configNumber } from '../activity/gathering'
import type { RandomFn } from '../activity/pools'
import { resolveActivityTransitions } from '../activity/transition'
import {
  applyCombatDefeat,
  applyCombatVictory,
  clearCombatSave,
  deathPauseRemainingMs,
  getEnemy,
  resolveCombatRound,
} from '../combat/engine'
import type { GameDatabase } from '../data/types'
import { applyActivityTimeTowardCritters } from '../critters/critters'
import { resolveProductionProgress } from '../production/engine'
import { accruePlayTime } from '../save/playTime'
import type { PlayerSave } from '../save/types'

/**
 * Safety valve on the combat/gathering catch-up loop (one discrete
 * round/action per step). Sized relative to config so it can never fall
 * short of the advertised unattended cap for the fastest possible tick
 * (today, combat rounds), with a generous margin for shorter future ticks.
 * If it's ever exhausted anyway, `resolveUnattendedProgress` only advances
 * the save's catch-up anchor as far as the simulation actually got (see
 * `hitStepLimit` below), so the remainder is caught up on the next load
 * instead of being silently lost.
 */
function maxUnattendedSteps(db: GameDatabase): number {
  const capMs = unattendedCapMs(db)
  const roundMs = Math.max(1, configNumber(db, 'combat_round_duration', 4) * 1000)
  const minimumTickMs = Math.min(roundMs, 1_000)
  return Math.max(20_000, Math.ceil(capMs / minimumTickMs) + 1_000)
}

export interface UnattendedResult {
  save: PlayerSave
  changed: boolean
  messages: string[]
  gatheringActions: number
  craftsCompleted: number
  combatVictories: number
  combatDeaths: number
  crittersSpawned: number
  effectiveElapsedMs: number
}

export function unattendedCapMs(db: GameDatabase): number {
  return Math.max(0, configNumber(db, 'unattended_cap', 24) * 3_600_000)
}

export function stampUnattendedProgressAt(
  save: PlayerSave,
  nowMs: number = Date.now(),
): PlayerSave {
  return {
    ...save,
    unattendedProgressAt: new Date(nowMs).toISOString(),
  }
}

function effectiveEndMs(save: PlayerSave, nowMs: number, capMs: number): number {
  const anchorRaw = save.unattendedProgressAt ? Date.parse(save.unattendedProgressAt) : NaN
  const anchor = Number.isFinite(anchorRaw) ? anchorRaw : nowMs
  return Math.min(nowMs, anchor + capMs)
}

/**
 * Catch up Gathering, Combat, and Standard Production for time away,
 * using the same engines as live play and the configured unattended cap.
 */
export function resolveUnattendedProgress(
  db: GameDatabase,
  save: PlayerSave,
  nowMs: number = Date.now(),
  random: RandomFn = Math.random,
): UnattendedResult {
  const capMs = unattendedCapMs(db)
  const endMs = effectiveEndMs(save, nowMs, capMs)
  const anchorRaw = save.unattendedProgressAt ? Date.parse(save.unattendedProgressAt) : NaN
  const anchor = Number.isFinite(anchorRaw) ? anchorRaw : nowMs
  const effectiveElapsedMs = Math.max(0, endMs - anchor)

  let current = resolveActivityTransitions(db, save, endMs, random)
  const messages: string[] = []
  let gatheringActions = 0
  let craftsCompleted = 0
  let combatVictories = 0
  let combatDeaths = 0
  let crittersSpawned = 0
  let steps = 0
  const maxSteps = maxUnattendedSteps(db)
  // Tracks how far the combat/gathering simulation's own clock has actually
  // advanced, so we can tell "ran out of step budget mid-catch-up" apart
  // from "genuinely nothing more to simulate in this window."
  let lastResolvedMs = anchor
  let hitStepLimit = false

  const pushCritterSpawn = (spawned: { displayName: string } | null) => {
    if (!spawned) return
    crittersSpawned += 1
    messages.push(`A ${spawned.displayName} appeared while you were away.`)
  }

  const production = resolveProductionProgress(db, current, endMs, random)
  if (production.blockedByInventory) {
    messages.push('Crafting paused: inventory is full.')
  }
  if (production.craftsCompleted > 0 || production.activityMs > 0) {
    current = production.save
    craftsCompleted = production.craftsCompleted
    messages.push(...production.messages.slice(0, 6))
    if (production.messages.length > 6) {
      messages.push(`…and ${production.messages.length - 6} more crafts.`)
    }
    if (production.activityMs > 0) {
      const critter = applyActivityTimeTowardCritters(
        current,
        current.currentLocationId,
        production.activityMs,
        endMs,
        random,
      )
      current = critter.save
      pushCritterSpawn(critter.spawned)
    }
  }

  while (true) {
    if (steps >= maxSteps) {
      hitStepLimit = true
      break
    }
    steps += 1
    if (!current.currentActivityId) break
    // Production is batch-resolved above against the capped clock.
    if (current.productionRecipeId) break

    // Death pause: wait out remaining pause within the capped window.
    const pauseLeft = deathPauseRemainingMs(current, endMs)
    if (current.deathPauseUntil && pauseLeft > 0) {
      break
    }
    if (current.deathPauseUntil && pauseLeft <= 0) {
      const pauseEnded = Date.parse(current.deathPauseUntil)
      let resumed: PlayerSave = { ...current, deathPauseUntil: null }
      if (!activityStillValid(db, resumed, resumed.currentActivityId!)) {
        current = clearActivitySave(resumed, pauseEnded)
        messages.push('Activity stopped after defeat — requirements no longer met.')
        break
      }
      const generated = generateNextAction(
        db,
        resumed,
        resumed.currentActivityId!,
        random,
        Math.max(pauseEnded, anchor),
      )
      current = generated ? generated.save : resumed
      lastResolvedMs = Math.max(pauseEnded, anchor)
      messages.push('Recovered from defeat while away.')
      continue
    }

    // Combat rounds.
    if (current.combatEnemyId && current.combatRoundStartedAt) {
      const roundMs = configNumber(db, 'combat_round_duration', 4) * 1000
      const roundStart = Date.parse(current.combatRoundStartedAt)
      const roundEnd = roundStart + roundMs
      if (roundEnd > endMs) break

      const enemy = getEnemy(db, current.combatEnemyId)
      const action = current.currentActionId
        ? db.Actions.find((row) => row['Action ID'] === current.currentActionId)
        : undefined
      if (!enemy || !action || current.combatEnemyHp == null) {
        current = clearActivitySave(current, roundEnd)
        break
      }

      const round = resolveCombatRound(db, current, enemy, current.combatEnemyHp, random)
      if (round.outcome === 'victory') {
        const victory = applyCombatVictory(
          db,
          { ...current, combatEnemyHp: 0, currentHp: round.playerHp },
          action,
          enemy,
          random,
          // Credit the kill to the hour it happened in, not to the hour the
          // player happens to come back in.
          roundEnd,
        )
        combatVictories += 1
        let next = victory.save
        const critter = applyActivityTimeTowardCritters(
          next,
          next.currentLocationId,
          roundMs,
          roundEnd,
          random,
        )
        next = critter.save
        pushCritterSpawn(critter.spawned)
        const activityId = current.currentActivityId
        if (!activityStillValid(db, next, activityId)) {
          current = clearActivitySave(next, roundEnd)
          messages.push(`Defeated ${enemy['Display Name']} · activity stopped.`)
          break
        }
        const generated = generateNextAction(db, next, activityId, random, roundEnd)
        current = generated ? generated.save : next
        lastResolvedMs = roundEnd
        continue
      }

      if (round.outcome === 'defeat') {
        combatDeaths += 1
        let defeated = applyCombatDefeat(
          db,
          { ...current, currentHp: 0 },
          roundEnd,
        )
        const critter = applyActivityTimeTowardCritters(
          defeated,
          defeated.currentLocationId,
          roundMs,
          roundEnd,
          random,
        )
        defeated = critter.save
        pushCritterSpawn(critter.spawned)
        current = defeated
        lastResolvedMs = roundEnd
        messages.push(`Defeated by ${enemy['Display Name']} while away.`)
        continue
      }

      let continued: PlayerSave = {
        ...current,
        currentHp: round.playerHp,
        combatEnemyHp: round.enemyHp,
        combatRoundStartedAt: new Date(roundEnd).toISOString(),
        combatSkipEnemyAttack: round.skipNextEnemyAttack,
        combatBossSleepRoundsRemaining: round.bossSleepRoundsRemaining,
      }
      const critter = applyActivityTimeTowardCritters(
        continued,
        continued.currentLocationId,
        roundMs,
        roundEnd,
        random,
      )
      continued = critter.save
      pushCritterSpawn(critter.spawned)
      current = continued
      lastResolvedMs = roundEnd
      continue
    }

    // Gathering action in progress.
    const actionState = restoreActiveActionState(current)
    if (actionState) {
      const due = actionState.startedAtMs + actionState.durationMs
      if (due > endMs) break

      const action = db.Actions.find((row) => row['Action ID'] === actionState.actionId)
      if (!action) {
        current = clearActivitySave(current, due)
        break
      }

      const completed = completeGatheringAction(db, current, action, random)
      gatheringActions += 1
      let next = completed.save
      // Clear completed action fields before generating the next one.
      next = clearCombatSave({
        ...next,
        currentActionId: null,
        actionStartedAt: null,
        actionDurationMs: null,
      })
      const critter = applyActivityTimeTowardCritters(
        next,
        next.currentLocationId,
        actionState.durationMs,
        due,
        random,
      )
      next = critter.save
      pushCritterSpawn(critter.spawned)

      const activityId = current.currentActivityId
      if (!activityStillValid(db, next, activityId)) {
        current = clearActivitySave(next, due)
        messages.push('Activity stopped — requirements no longer met.')
        break
      }
      const generated = generateNextAction(db, next, activityId, random, due)
      current = generated ? generated.save : next
      lastResolvedMs = due
      continue
    }

    // Activity running but no action yet — generate one at the sim clock.
    if (current.currentActivityId && !current.productionRecipeId) {
      if (!activityStillValid(db, current, current.currentActivityId)) {
        current = clearActivitySave(current, endMs)
        messages.push('Activity stopped — requirements no longer met.')
        break
      }
      const waitUntil = bossRespawnWaitUntilMs(db, current, current.currentActivityId)
      const startAt = waitUntil != null ? waitUntil : endMs
      if (startAt > endMs) break
      const generated = generateNextAction(
        db,
        current,
        current.currentActivityId,
        random,
        startAt,
      )
      if (!generated) break
      // If generation only stamps "now" without being due, avoid looping forever:
      // only accept if something actionable was created.
      if (
        generated.save.currentActionId === current.currentActionId &&
        generated.save.combatEnemyId === current.combatEnemyId
      ) {
        break
      }
      current = generated.save
      lastResolvedMs = startAt
      continue
    }

    break
  }

  if (gatheringActions > 0) {
    messages.unshift(`Gathered through ${gatheringActions} action${gatheringActions === 1 ? '' : 's'} while away.`)
  }
  if (combatVictories > 0) {
    messages.unshift(
      `Won ${combatVictories} fight${combatVictories === 1 ? '' : 's'} while away.`,
    )
  }
  if (craftsCompleted > 0 && !messages.some((line) => line.includes('Crafted'))) {
    messages.unshift(`Completed ${craftsCompleted} craft${craftsCompleted === 1 ? '' : 's'} while away.`)
  }

  // Normally we're fully caught up to `endMs` (which is already <= nowMs),
  // so it's safe to stamp `nowMs`. But if the combat/gathering loop ran out
  // of step budget while there was still more due within the window, only
  // advance the anchor as far as the simulation actually got — the
  // remainder will be caught up on the next load instead of being lost.
  const stampAt = hitStepLimit ? Math.min(nowMs, lastResolvedMs) : nowMs
  const stamped = accruePlayTime(stampUnattendedProgressAt(current, stampAt), effectiveElapsedMs)
  const changed =
    stamped !== save &&
    (gatheringActions > 0 ||
      craftsCompleted > 0 ||
      combatVictories > 0 ||
      combatDeaths > 0 ||
      crittersSpawned > 0 ||
      stamped.unattendedProgressAt !== save.unattendedProgressAt ||
      stamped.playTimeMs !== save.playTimeMs ||
      stamped.currentActionId !== save.currentActionId ||
      stamped.combatEnemyHp !== save.combatEnemyHp ||
      stamped.currentHp !== save.currentHp ||
      stamped.gold !== save.gold ||
      stamped.deathPauseUntil !== save.deathPauseUntil ||
      stamped.productionQuantityRemaining !== save.productionQuantityRemaining ||
      JSON.stringify(stamped.inventory) !== JSON.stringify(save.inventory) ||
      JSON.stringify(stamped.skills) !== JSON.stringify(save.skills) ||
      JSON.stringify(stamped.activeCritterSpawns) !== JSON.stringify(save.activeCritterSpawns) ||
      JSON.stringify(stamped.critterProgressMs) !== JSON.stringify(save.critterProgressMs))

  return {
    save: stamped,
    changed,
    messages,
    gatheringActions,
    craftsCompleted,
    combatVictories,
    combatDeaths,
    crittersSpawned,
    effectiveElapsedMs,
  }
}
