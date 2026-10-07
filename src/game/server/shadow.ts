import type { RandomFn } from '../activity/pools'
import { prepareDatabase } from '../data/loadDatabase'
import type { GameDatabase } from '../data/types'
import { parseSave } from '../save/saveStore'
import type { PlayerSave } from '../save/types'
import { advanceSession } from '../session/tick'
import { totalLevel, totalSkillXp } from '../skills/totals'
import { resolveUnattendedProgress } from '../unattended/resolve'

const firstOfPool: RandomFn = () => 0

/** playTimeMs / unattended stamps may land a beat apart on two clocks. */
export const SHADOW_PLAY_TIME_SLACK_MS = 2_000
export const SHADOW_STAMP_SLACK_MS = 5_000

export type ShadowFieldDiff = {
  field: string
  client: string | number | null
  server: string | number | null
}

export type ShadowAdvanceTiming = {
  advanceMs: number
  unattendedMs: number
  gatheringActions: number
  craftsCompleted: number
  combatVictories: number
  combatDeaths: number
  effectiveElapsedMs: number
}

export type Phase1ShadowResult = {
  phase: 1
  replay: ShadowFieldDiff[]
  own: ShadowFieldDiff[]
  replayMatched: boolean
  ownMatched: boolean
  timing: ShadowAdvanceTiming
  ownTiming: ShadowAdvanceTiming
  /** Server-owned copy after this interval. Not sent to the client. */
  ownSave: PlayerSave
}

function elapsedMs(started: number): number {
  return performance.now() - started
}

function bagQty(save: PlayerSave): number {
  return save.inventory.reduce((sum, stack) => sum + stack.quantity, 0)
}

function stampMs(value: string | null | undefined): number | null {
  if (!value) return null
  const parsed = Date.parse(value)
  return Number.isFinite(parsed) ? parsed : null
}

function addDiff(
  diffs: ShadowFieldDiff[],
  field: string,
  client: string | number | null,
  server: string | number | null,
): void {
  if (client === server) return
  diffs.push({ field, client, server })
}

function addNumeric(
  diffs: ShadowFieldDiff[],
  field: string,
  client: number | null | undefined,
  server: number | null | undefined,
  slack = 0,
): void {
  const left = client ?? null
  const right = server ?? null
  if (left === null && right === null) return
  if (left !== null && right !== null && Math.abs(left - right) <= slack) return
  addDiff(diffs, field, left, right)
}

/** Fields that show Dart/TS drift without dumping the whole save. */
export function compareShadowSaves(client: PlayerSave, server: PlayerSave): ShadowFieldDiff[] {
  const diffs: ShadowFieldDiff[] = []
  addDiff(diffs, 'characterName', client.characterName ?? null, server.characterName ?? null)
  addDiff(diffs, 'raceId', client.raceId ?? null, server.raceId ?? null)
  addDiff(diffs, 'currentLocationId', client.currentLocationId, server.currentLocationId)
  addDiff(diffs, 'currentActivityId', client.currentActivityId ?? null, server.currentActivityId ?? null)
  addDiff(diffs, 'combatEnemyId', client.combatEnemyId ?? null, server.combatEnemyId ?? null)
  addDiff(diffs, 'productionRecipeId', client.productionRecipeId ?? null, server.productionRecipeId ?? null)
  addNumeric(diffs, 'productionQuantityRemaining', client.productionQuantityRemaining, server.productionQuantityRemaining)
  addNumeric(diffs, 'gold', client.gold, server.gold)
  addNumeric(diffs, 'inventoryQty', bagQty(client), bagQty(server))
  addNumeric(diffs, 'totalSkillXp', totalSkillXp(client), totalSkillXp(server))
  addNumeric(diffs, 'totalLevel', totalLevel(client), totalLevel(server))
  addNumeric(diffs, 'playTimeMs', client.playTimeMs, server.playTimeMs, SHADOW_PLAY_TIME_SLACK_MS)
  addNumeric(diffs, 'currentHp', client.currentHp, server.currentHp, 1)
  addNumeric(
    diffs,
    'unattendedProgressAt',
    stampMs(client.unattendedProgressAt),
    stampMs(server.unattendedProgressAt),
    SHADOW_STAMP_SLACK_MS,
  )
  return diffs
}

function advanceCopy(db: GameDatabase, save: PlayerSave, nowMs: number): {
  save: PlayerSave
  timing: ShadowAdvanceTiming
} {
  const unattendedStarted = performance.now()
  const unattended = resolveUnattendedProgress(db, save, nowMs, firstOfPool)
  const unattendedMs = elapsedMs(unattendedStarted)
  const advanceStarted = performance.now()
  const advanced = advanceSession(db, unattended.save, nowMs, firstOfPool)
  const advanceMs = elapsedMs(advanceStarted)
  return {
    save: advanced.save,
    timing: {
      advanceMs,
      unattendedMs,
      gatheringActions: unattended.gatheringActions,
      craftsCompleted: unattended.craftsCompleted,
      combatVictories: unattended.combatVictories,
      combatDeaths: unattended.combatDeaths,
      effectiveElapsedMs: unattended.effectiveElapsedMs,
    },
  }
}

/**
 * Advances copies of the previous upload (and the server's own copy) to `nowMs`
 * and diffs them against the save the client just uploaded.
 *
 * RNG is pinned to the first pool entry, so loot/gold will disagree until
 * phase 2 holds a server seed. Location, activity, and play time are the signal.
 */
export function runPhase1Shadow(
  rawDatabase: unknown,
  options: {
    previousClientSave: unknown
    currentClientSave: unknown
    ownSave?: unknown
    nowMs: number
  },
): Phase1ShadowResult {
  const { launch: db } = prepareDatabase(rawDatabase)
  const previous = parseSave(options.previousClientSave, options.nowMs)
  const current = parseSave(options.currentClientSave, options.nowMs)
  const ownBase = options.ownSave === undefined ? previous : parseSave(options.ownSave, options.nowMs)

  const replayed = advanceCopy(db, previous, options.nowMs)
  const owned = advanceCopy(db, ownBase, options.nowMs)
  const replay = compareShadowSaves(current, replayed.save)
  const own = compareShadowSaves(current, owned.save)

  return {
    phase: 1,
    replay,
    own,
    replayMatched: replay.length === 0,
    ownMatched: own.length === 0,
    timing: replayed.timing,
    ownTiming: owned.timing,
    ownSave: owned.save,
  }
}
