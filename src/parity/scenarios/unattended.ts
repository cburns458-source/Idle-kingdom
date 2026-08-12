import { beginActivitySave, generateNextAction } from '../../game/activity/engine'
import { addItemToInventory } from '../../game/activity/rewards'
import type { GameDatabase } from '../../game/data/types'
import { beginProductionQueue } from '../../game/production/engine'
import { mulberry32 } from '../../game/rng/mulberry32'
import type { PlayerSave } from '../../game/save/types'
import {
  resolveUnattendedProgress,
  stampUnattendedProgressAt,
  unattendedCapMs,
} from '../../game/unattended/resolve'
import { scenario, type JsonValue, type ParityScenario } from '../types'
import { contentDatabase } from './contentDatabase'
import { asJson, baseSave, FIXED_TIMESTAMP, FIXED_TIMESTAMP_MS } from './saveFixtures'

/** Pinned generator seed; the resolver's every roll comes from it. */
const SEED = 11

/** A meadow gathering activity, whose actions are short enough to repeat. */
const GATHERING_ACTIVITY_ID = 'ACT-0012'
const GATHERING_LOCATION_ID = 'LOC-0009'

/** Tend the Pasture, which has combat pool entries. */
const COMBAT_ACTIVITY_ID = 'ACT-0001'
const COMBAT_LOCATION_ID = 'LOC-0001'
const COMBAT_POOL_ID = 'POOL-0001'

const HOUR_MS = 3_600_000

/** Anchored at the pinned clock so the catch-up window is exactly `spanMs`. */
function anchored(save: PlayerSave): PlayerSave {
  return stampUnattendedProgressAt(save, FIXED_TIMESTAMP_MS)
}

/** Mid-gather: an action is already running and due inside the window. */
function gatheringSave(db: GameDatabase): PlayerSave {
  const started = beginActivitySave(
    { ...baseSave(db), currentLocationId: GATHERING_LOCATION_ID },
    GATHERING_ACTIVITY_ID,
    FIXED_TIMESTAMP,
  )
  const generated = generateNextAction(
    db,
    started,
    GATHERING_ACTIVITY_ID,
    mulberry32(SEED),
    FIXED_TIMESTAMP_MS,
  )
  if (!generated) throw new Error('Expected the meadow activity to roll an action')
  return anchored(generated.save)
}

/** Mid-combat: a round is in flight against the first pooled enemy. */
function combatSave(db: GameDatabase): PlayerSave {
  const started = beginActivitySave(
    {
      ...baseSave(db),
      currentLocationId: COMBAT_LOCATION_ID,
      currentHp: 100_000,
      maxHp: 100_000,
    },
    COMBAT_ACTIVITY_ID,
    FIXED_TIMESTAMP,
  )
  const action = db.Actions.find(
    (row) =>
      row.Category === 'Combat' &&
      db.PoolEntries.some(
        (entry) => entry['Pool ID'] === COMBAT_POOL_ID && entry['Action ID'] === row['Action ID'],
      ),
  )
  if (!action) throw new Error('Expected a combat action in the pasture pool')
  const enemy = db.Enemies.find((row) => row['Enemy ID'] === action['Target ID'])
  if (!enemy) throw new Error(`Expected an enemy for ${action['Action ID']}`)

  return anchored({
    ...started,
    currentActionId: action['Action ID'],
    actionStartedAt: FIXED_TIMESTAMP,
    actionDurationMs: null,
    combatEnemyId: enemy['Enemy ID'],
    combatEnemyHp: enemy['Maximum HP'],
    combatRoundStartedAt: FIXED_TIMESTAMP,
  })
}

/** A combat save already knocked out, so the death pause has to be waited out. */
function deathPausedSave(db: GameDatabase): PlayerSave {
  const fighting = combatSave(db)
  return {
    ...fighting,
    currentHp: 0,
    // Ends 30s into the window, so the pause is waited out and play resumes.
    deathPauseUntil: new Date(FIXED_TIMESTAMP_MS + 30_000).toISOString(),
  }
}

/** A queued production run with the ingredients it needs. */
function productionSave(db: GameDatabase): PlayerSave {
  const stocked = addItemToInventory(baseSave(db), 'ITEM-0025', 20)
  const begun = beginProductionQueue(db, stocked, 'ACT-0017', 'RCP-0001', 3, FIXED_TIMESTAMP_MS)
  if (!begun.ok) throw new Error(`Expected the kitchen queue to start: ${begun.reason}`)
  return anchored(begun.save)
}

/** Idle at the starting location, so catch-up has nothing to advance. */
function idleSave(db: GameDatabase): PlayerSave {
  return anchored(baseSave(db))
}

/** An activity running with no action rolled yet, generated at the sim clock. */
function pendingActionSave(db: GameDatabase): PlayerSave {
  return anchored(
    beginActivitySave(
      { ...baseSave(db), currentLocationId: GATHERING_LOCATION_ID },
      GATHERING_ACTIVITY_ID,
      FIXED_TIMESTAMP,
    ),
  )
}

/** Anchored in the future, which must not run the simulation backwards. */
function futureAnchorSave(db: GameDatabase): PlayerSave {
  return stampUnattendedProgressAt(gatheringSave(db), FIXED_TIMESTAMP_MS + HOUR_MS)
}

/** No anchor at all, which falls back to the caller's clock. */
function anchorlessSave(db: GameDatabase): PlayerSave {
  return { ...gatheringSave(db), unattendedProgressAt: null }
}

type SaveKind =
  | 'idle'
  | 'gathering'
  | 'pending-action'
  | 'combat'
  | 'death-paused'
  | 'production'
  | 'future-anchor'
  | 'anchorless'

const SAVE_BUILDERS: Record<SaveKind, (db: GameDatabase) => PlayerSave> = {
  idle: idleSave,
  gathering: gatheringSave,
  'pending-action': pendingActionSave,
  combat: combatSave,
  'death-paused': deathPausedSave,
  production: productionSave,
  'future-anchor': futureAnchorSave,
  anchorless: anchorlessSave,
}

function saveFor(kind: SaveKind): PlayerSave {
  return SAVE_BUILDERS[kind](contentDatabase())
}

/** Each case is one save shape caught up across one absence length. */
const CASES: Array<{ kind: SaveKind; spanMs: number }> = [
  { kind: 'idle', spanMs: 2 * HOUR_MS },
  { kind: 'gathering', spanMs: 0 },
  { kind: 'gathering', spanMs: 120_000 },
  { kind: 'gathering', spanMs: 6 * HOUR_MS },
  // Past the 24h cap, so the window clamps and the second day is not simulated.
  { kind: 'gathering', spanMs: 48 * HOUR_MS },
  { kind: 'pending-action', spanMs: 60_000 },
  { kind: 'combat', spanMs: 160_000 },
  { kind: 'combat', spanMs: 8 * HOUR_MS },
  { kind: 'death-paused', spanMs: 120_000 },
  // Shorter than the pause, so the save comes back still knocked out.
  { kind: 'death-paused', spanMs: 10_000 },
  { kind: 'production', spanMs: 4 * HOUR_MS },
  { kind: 'future-anchor', spanMs: 0 },
  { kind: 'anchorless', spanMs: 120_000 },
]

function resolved(kind: SaveKind, spanMs: number): JsonValue {
  const result = resolveUnattendedProgress(
    contentDatabase(),
    saveFor(kind),
    FIXED_TIMESTAMP_MS + spanMs,
    mulberry32(SEED),
  )
  return {
    save: asJson(result.save),
    changed: result.changed,
    messages: result.messages,
    gatheringActions: result.gatheringActions,
    craftsCompleted: result.craftsCompleted,
    combatVictories: result.combatVictories,
    combatDeaths: result.combatDeaths,
    crittersSpawned: result.crittersSpawned,
    effectiveElapsedMs: result.effectiveElapsedMs,
  } as unknown as JsonValue
}

export const unattendedScenarios: ParityScenario[] = [
  scenario('unattended/cap', 'from-config', { source: 'content' }, () =>
    unattendedCapMs(contentDatabase()),
  ),

  scenario(
    'unattended/stamp',
    'anchor',
    { source: 'content', save: asJson(baseSave(contentDatabase())), nowMs: FIXED_TIMESTAMP_MS },
    () =>
      ({
        atPin: asJson(stampUnattendedProgressAt(baseSave(contentDatabase()), FIXED_TIMESTAMP_MS)),
        laterUnattendedProgressAt: stampUnattendedProgressAt(
          baseSave(contentDatabase()),
          FIXED_TIMESTAMP_MS + HOUR_MS,
        ).unattendedProgressAt,
      }) as unknown as JsonValue,
  ),

  ...CASES.map((entry) =>
    scenario(
      'unattended/resolve',
      `${entry.kind}-${entry.spanMs}ms`,
      {
        source: 'content',
        seed: SEED,
        spanMs: entry.spanMs,
        nowMs: FIXED_TIMESTAMP_MS + entry.spanMs,
        save: asJson(saveFor(entry.kind)),
      },
      () => resolved(entry.kind, entry.spanMs),
    ),
  ),
]
