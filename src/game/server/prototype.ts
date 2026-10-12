import { beginActivitySave, generateNextAction } from '../activity/engine'
import type { RandomFn } from '../activity/pools'
import { prepareDatabase } from '../data/loadDatabase'
import type { GameDatabase } from '../data/types'
import { createNewSave, parseSave } from '../save/saveStore'
import type { PlayerSave } from '../save/types'
import { advanceSession } from '../session/tick'
import { resolveUnattendedProgress } from '../unattended/resolve'

export { compareShadowSaves, runPhase1Shadow, SHADOW_PLAY_TIME_SLACK_MS } from './shadow'
export type { Phase1ShadowResult, ShadowFieldDiff } from './shadow'
export {
  applyGameCommand,
  createTrackedMulberry32,
  runPhase2Sync,
} from './authority'
export type { GameCommandResult, Phase2SyncResult } from './authority'
export {
  applyDevCommand,
  DEV_COMMAND_HELP,
  parseDevCommandLine,
} from './devCommands'
export type { DevCommandHelpLine, DevCommandResult } from './devCommands'
export {
  overlayPublishedPvpSnapshot,
  pvpSnapshotRowForSave,
  rankingBoardRowsFor,
  rankingProfilePatch,
} from './rankings'
export { prepareDatabase } from '../data/loadDatabase'
export { parseSave } from '../save/saveStore'

const MEADOW_LOCATION_ID = 'LOC-0009'
const MEADOW_ACTIVITY_ID = 'ACT-0012'
const START_MS = Date.parse('2026-01-01T00:00:00.000Z')

/** Eight hours: the catch-up the design expects one `sync` to cover. */
export const PHASE0_DEFAULT_AWAY_MS = 8 * 3_600_000

export type Phase0ScenarioTiming = {
  name: string
  advanceMs: number
  advanceChanged: boolean
  unattendedMs: number
  unattendedChanged: boolean
  gatheringActions: number
  craftsCompleted: number
  combatVictories: number
  combatDeaths: number
  effectiveElapsedMs: number
}

export type Phase0PrototypeResult = {
  phase: 0
  prepareDbMs: number
  awayMs: number
  scenarios: Phase0ScenarioTiming[]
}

const firstOfPool: RandomFn = () => 0

function elapsedMs(started: number): number {
  return performance.now() - started
}

function gatheringSave(db: GameDatabase, startedAt: number): PlayerSave {
  const begun = beginActivitySave(
    { ...createNewSave(db, startedAt), currentLocationId: MEADOW_LOCATION_ID },
    MEADOW_ACTIVITY_ID,
    new Date(startedAt).toISOString(),
  )
  const generated = generateNextAction(db, begun, MEADOW_ACTIVITY_ID, firstOfPool, startedAt)
  if (!generated) {
    throw new Error('Could not start meadow gathering for the phase 0 prototype.')
  }
  return {
    ...generated.save,
    unattendedProgressAt: new Date(startedAt).toISOString(),
  }
}

function idleSave(db: GameDatabase, startedAt: number): PlayerSave {
  return {
    ...createNewSave(db, startedAt),
    unattendedProgressAt: new Date(startedAt).toISOString(),
  }
}

function timeScenario(
  db: GameDatabase,
  name: string,
  save: PlayerSave,
  nowMs: number,
): Phase0ScenarioTiming {
  const advanceStarted = performance.now()
  const advanced = advanceSession(db, save, nowMs, firstOfPool)
  const advanceMs = elapsedMs(advanceStarted)

  const unattendedStarted = performance.now()
  const unattended = resolveUnattendedProgress(db, save, nowMs, firstOfPool)
  const unattendedMs = elapsedMs(unattendedStarted)

  return {
    name,
    advanceMs,
    advanceChanged: advanced.changed,
    unattendedMs,
    unattendedChanged: unattended.changed,
    gatheringActions: unattended.gatheringActions,
    craftsCompleted: unattended.craftsCompleted,
    combatVictories: unattended.combatVictories,
    combatDeaths: unattended.combatDeaths,
    effectiveElapsedMs: unattended.effectiveElapsedMs,
  }
}

/**
 * Times `advanceSession` and the unattended resolver on copies of saves.
 *
 * Each scenario starts from its own copy. The hosted save is never written.
 */
export function runPhase0Prototype(
  rawDatabase: unknown,
  options: {
    hostedSave?: unknown
    awayMs?: number
    nowMs?: number
  } = {},
): Phase0PrototypeResult {
  const prepareStarted = performance.now()
  const { launch: db } = prepareDatabase(rawDatabase)
  const prepareDbMs = elapsedMs(prepareStarted)

  const awayMs = options.awayMs ?? PHASE0_DEFAULT_AWAY_MS
  const nowMs = options.nowMs ?? START_MS + awayMs
  const startedAt = nowMs - awayMs

  const scenarios: Phase0ScenarioTiming[] = [
    timeScenario(db, 'idle', idleSave(db, startedAt), nowMs),
    timeScenario(db, 'gathering', gatheringSave(db, startedAt), nowMs),
  ]

  if (options.hostedSave !== undefined) {
    const hosted = parseSave(options.hostedSave, nowMs)
    scenarios.push(
      timeScenario(
        db,
        'hosted-copy',
        {
          ...hosted,
          unattendedProgressAt: hosted.unattendedProgressAt ?? new Date(startedAt).toISOString(),
        },
        nowMs,
      ),
    )
  }

  return { phase: 0, prepareDbMs, awayMs, scenarios }
}
