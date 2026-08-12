import { beginActivitySave, generateNextAction } from '../../game/activity/engine'
import type { GameDatabase } from '../../game/data/types'
import { INVENTORY_SLOT_LIMIT } from '../../game/inventory/capacity'
import { mulberry32 } from '../../game/rng/mulberry32'
import type { PlayerSave } from '../../game/save/types'
import { prepareSaveForWrite } from '../../game/session/persist'
import { actionProgressAt } from '../../game/session/progress'
import { advanceSession } from '../../game/session/tick'
import { arriveFromTravel, planTravel, type TravelPlan } from '../../game/session/travel'
import { scenario, type JsonValue, type ParityScenario } from '../types'
import {
  asDatabase,
  contentDatabase,
  location,
  minimalDatabase,
  type JsonDatabase,
} from './contentDatabase'
import {
  asJson,
  baseSave,
  combatSave,
  FIXED_TIMESTAMP,
  FIXED_TIMESTAMP_MS,
  kitchenSave,
  queuedProductionSave,
} from './saveFixtures'

/** Pinned generator seed; every roll a scripted run makes comes from it. */
const SEED = 909

/** Gather meadow supplies: two gathering actions, 20s and 60s. */
const MEADOW_ACTIVITY_ID = 'ACT-0012'
const MEADOW_LOCATION_ID = 'LOC-0009'

/** Fight the goblins: an all-combat pool, at the location `combatSave` stands in. */
const GOBLIN_ACTIVITY_ID = 'ACT-0002'

/** Cook at the kitchen, a Standard Production station. */
const KITCHEN_ACTIVITY_ID = 'ACT-0017'

const SECOND = 1_000

/** Start [activityId] at the pin and roll its first action from the seed. */
function started(db: GameDatabase, save: PlayerSave, activityId: string): PlayerSave {
  const begun = beginActivitySave(save, activityId, FIXED_TIMESTAMP)
  const generated = generateNextAction(
    db,
    begun,
    activityId,
    mulberry32(SEED),
    FIXED_TIMESTAMP_MS,
  )
  if (!generated) throw new Error(`Expected ${activityId} to roll an action`)
  return generated.save
}

/** Mid-gather at the meadow, with the rolled action due later in the run. */
function gatheringSave(db: GameDatabase): PlayerSave {
  return started(db, { ...baseSave(db), currentLocationId: MEADOW_LOCATION_ID }, MEADOW_ACTIVITY_ID)
}

/**
 * Mid-gather, but standing somewhere the activity does not exist.
 *
 * The action still completes and pays out; it is rolling the next one that
 * discovers the activity is no longer startable here and stops it.
 */
function strandedSave(db: GameDatabase): PlayerSave {
  return { ...gatheringSave(db), currentLocationId: 'LOC-0002' }
}

/** An activity running with nothing rolled yet, so the first tick rolls one. */
function pendingActionSave(db: GameDatabase): PlayerSave {
  return beginActivitySave(
    { ...baseSave(db), currentLocationId: MEADOW_LOCATION_ID },
    MEADOW_ACTIVITY_ID,
    FIXED_TIMESTAMP,
  )
}

/** Mid-fight in the goblin camp, armed and levelled enough to win. */
function fightingSave(db: GameDatabase): PlayerSave {
  return started(db, combatSave(db), GOBLIN_ACTIVITY_ID)
}

/** The same fight, entered on a sliver of HP, so the first round is a loss. */
function doomedSave(db: GameDatabase): PlayerSave {
  return { ...fightingSave(db), currentHp: 1 }
}

/** A queued cooking run whose current craft is due at the pin. */
function productionSave(db: GameDatabase): PlayerSave {
  return queuedProductionSave(db)
}

/** The same run with no room for the Baked Potato it is about to finish. */
function fullBagProductionSave(db: GameDatabase): PlayerSave {
  const queued = queuedProductionSave(db)
  const filler = Array.from(
    { length: INVENTORY_SLOT_LIMIT - queued.inventory.length },
    (_, index) => ({
      itemId: 'ITEM-0100',
      quantity: 1,
      // Distinct enchantments keep every filler stack in a slot of its own.
      enchantmentId: `ENCH-${String(index).padStart(4, '0')}`,
    }),
  )
  return { ...queued, inventory: [...queued.inventory, ...filler] }
}

/** At the kitchen with the station running but no recipe picked. */
function kitchenIdleSave(db: GameDatabase): PlayerSave {
  return beginActivitySave(kitchenSave(db), KITCHEN_ACTIVITY_ID, FIXED_TIMESTAMP)
}

/** A legacy queued activity change, which a tick applies immediately. */
function legacyTransitionSave(db: GameDatabase): PlayerSave {
  return {
    ...baseSave(db),
    currentLocationId: MEADOW_LOCATION_ID,
    activityTransition: {
      kind: 'starting',
      activityId: MEADOW_ACTIVITY_ID,
      followUpActivityId: null,
      productionRecipeId: null,
      productionQuantity: null,
      startedAt: FIXED_TIMESTAMP,
      durationMs: 5 * SECOND,
    },
  }
}

/** Nothing running, so every tick is a no-op. */
function idleSave(db: GameDatabase): PlayerSave {
  return baseSave(db)
}

type SaveKind =
  | 'idle'
  | 'gathering'
  | 'stranded'
  | 'pending-action'
  | 'fighting'
  | 'doomed'
  | 'production'
  | 'production-full-bag'
  | 'kitchen-idle'
  | 'legacy-transition'

const SAVE_BUILDERS: Record<SaveKind, (db: GameDatabase) => PlayerSave> = {
  idle: idleSave,
  gathering: gatheringSave,
  stranded: strandedSave,
  'pending-action': pendingActionSave,
  fighting: fightingSave,
  doomed: doomedSave,
  production: productionSave,
  'production-full-bag': fullBagProductionSave,
  'kitchen-idle': kitchenIdleSave,
  'legacy-transition': legacyTransitionSave,
}

function saveFor(kind: SaveKind): PlayerSave {
  return SAVE_BUILDERS[kind](contentDatabase())
}

/**
 * One scripted run: tick the session at each offset, feeding each result into
 * the next, and record what the client would draw and react to.
 *
 * The generator is created once for the whole run, so the recorded sequence only
 * matches if the Dart port makes the same number of rolls in the same order.
 */
function run(kind: SaveKind, offsetsMs: number[]): JsonValue {
  const db = contentDatabase()
  const random = mulberry32(SEED)
  let save = saveFor(kind)
  const steps = offsetsMs.map((offsetMs) => {
    const nowMs = FIXED_TIMESTAMP_MS + offsetMs
    const result = advanceSession(db, save, nowMs, random)
    save = result.save
    return {
      offsetMs,
      changed: result.changed,
      events: result.events,
      progress: actionProgressAt(save, nowMs),
      save: asJson(save),
    }
  })
  return { steps } as unknown as JsonValue
}

/**
 * Each case walks one save shape through the ticks that matter for it: before
 * the timer is due, the tick that resolves it, and enough afterwards to see the
 * follow-up action, a queue finishing, or a death pause being waited out.
 */
const RUNS: Array<{ kind: SaveKind; offsetsMs: number[] }> = [
  { kind: 'idle', offsetsMs: [0, 60 * SECOND] },
  // Meadow actions run 120s here, so this covers two completions.
  {
    kind: 'gathering',
    offsetsMs: [0, 60 * SECOND, 120 * SECOND, 130 * SECOND, 250 * SECOND, 260 * SECOND],
  },
  { kind: 'stranded', offsetsMs: [0, 130 * SECOND] },
  { kind: 'pending-action', offsetsMs: [0, 30 * SECOND] },
  // Combat rounds are 4s and the Goblin Warrior has 900 HP, so this trades blows
  // until the fight settles and the next enemy is rolled.
  {
    kind: 'fighting',
    offsetsMs: [0, 2 * SECOND, ...Array.from({ length: 10 }, (_, index) => (index + 1) * 4 * SECOND)],
  },
  // Loses the first round, then waits out the death pause and resumes.
  { kind: 'doomed', offsetsMs: [4 * SECOND, 10 * SECOND, 5 * 60 * SECOND] },
  // Crafts are 20s and three remain, so the run finishes and clears itself.
  {
    kind: 'production',
    offsetsMs: [0, 10 * SECOND, 20 * SECOND, 40 * SECOND, 60 * SECOND, 80 * SECOND],
  },
  { kind: 'production-full-bag', offsetsMs: [20 * SECOND, 40 * SECOND] },
  { kind: 'kitchen-idle', offsetsMs: [0, 60 * SECOND] },
  { kind: 'legacy-transition', offsetsMs: [0, 30 * SECOND] },
]

/** Saves whose in-flight timer makes a progress bar worth reading. */
const PROGRESS_KINDS: SaveKind[] = ['idle', 'gathering', 'fighting', 'production', 'kitchen-idle']

const PROGRESS_OFFSETS_MS = [0, 5 * SECOND, 20 * SECOND, 3600 * SECOND]

/** The town, from which the Goblin Camp is one hostile step away. */
const TOWN_LOCATION_ID = 'LOC-0002'
const GOBLIN_LOCATION_ID = 'LOC-0003'

/** Recovering from a defeat, which blocks travel outright. */
function downedSave(db: GameDatabase): PlayerSave {
  return {
    ...gatheringSave(db),
    deathPauseUntil: new Date(FIXED_TIMESTAMP_MS + 30 * SECOND).toISOString(),
  }
}

/** Levelled past the Goblin Camp danger warning, so arrival forces nothing. */
function veteranSave(db: GameDatabase): PlayerSave {
  return { ...combatSave(db), currentLocationId: TOWN_LOCATION_ID }
}

type TravelSaveKind = 'town' | 'veteran' | 'gathering' | 'downed'

function travelSaveFor(kind: TravelSaveKind): PlayerSave {
  const db = contentDatabase()
  switch (kind) {
    case 'town':
      return { ...baseSave(db), currentLocationId: TOWN_LOCATION_ID }
    case 'veteran':
      return veteranSave(db)
    case 'gathering':
      return gatheringSave(db)
    case 'downed':
      return downedSave(db)
  }
}

/** `planTravel` plus, for a journey, the arrival that ends it. */
function plannedTravel(
  db: GameDatabase,
  save: PlayerSave,
  destinationId: string,
  browseMapId: string,
  nowMs: number,
): JsonValue {
  const plan = planTravel(db, save, destinationId, browseMapId, nowMs, mulberry32(SEED))
  return {
    plan: planJson(plan),
    arrival:
      plan.kind === 'timed'
        ? (arrivalJson(
            arriveFromTravel(
              db,
              plan.save,
              destinationId,
              nowMs + plan.durationMs,
              mulberry32(SEED),
            ),
          ) as JsonValue)
        : null,
  } as unknown as JsonValue
}

function planJson(plan: TravelPlan): JsonValue {
  if (plan.kind === 'blocked') return { kind: plan.kind }
  if (plan.kind === 'instant') {
    return { kind: plan.kind, arrival: arrivalJson(plan.arrival) }
  }
  return { kind: plan.kind, durationMs: plan.durationMs, save: asJson(plan.save) }
}

function arrivalJson(arrival: ReturnType<typeof arriveFromTravel>): JsonValue {
  return {
    save: asJson(arrival.save),
    forcedActivityId: arrival.forcedActivityId,
    blockedReason: arrival.blockedReason,
    message: arrival.message,
  } as unknown as JsonValue
}

/** Where a travel request can land, on the shipped content. */
const TRAVEL_CASES: Array<{
  name: string
  kind: TravelSaveKind
  destinationId: string
  browseMapId: string
}> = [
  { name: 'hostile-forced', kind: 'town', destinationId: GOBLIN_LOCATION_ID, browseMapId: 'MAP-0001' },
  { name: 'hostile-cleared', kind: 'veteran', destinationId: GOBLIN_LOCATION_ID, browseMapId: 'MAP-0001' },
  // Arriving stops whatever was running, refunding production materials.
  { name: 'stops-activity', kind: 'gathering', destinationId: TOWN_LOCATION_ID, browseMapId: 'MAP-0001' },
  { name: 'same-location', kind: 'town', destinationId: TOWN_LOCATION_ID, browseMapId: 'MAP-0001' },
  { name: 'unknown-destination', kind: 'town', destinationId: 'LOC-9999', browseMapId: 'MAP-0001' },
  // Still locked, so it cannot be travelled to even while its map is browsed.
  { name: 'locked-destination', kind: 'town', destinationId: 'LOC-0026', browseMapId: 'MAP-0006' },
  // A node on the browsed sub-map, reachable without a connection of its own.
  { name: 'submap-node', kind: 'town', destinationId: 'LOC-0011', browseMapId: 'MAP-0002' },
  { name: 'death-paused', kind: 'downed', destinationId: TOWN_LOCATION_ID, browseMapId: 'MAP-0001' },
]

/**
 * The shipped connections all leave `Base Duration` empty, which means instant
 * travel, so the journey branch needs a database that names a duration.
 */
function timedTravelDatabase(): JsonDatabase {
  const base = minimalDatabase()
  return {
    ...base,
    Locations: [...base.Locations, location('LOC-0003', 'Goblin Camp')],
    TravelConnections: [
      {
        'Connection ID': 'TRV-0001',
        'From Location ID': 'LOC-0002',
        'To Location ID': 'LOC-0003',
        Method: 'Road',
        Direction: 'Two-way',
        'Base Duration': 90,
        'Required Mount / Status': null,
        Status: 'Confirmed',
        'Release Phase': 'Launch',
        Notes: null,
      },
    ],
  }
}

export const sessionScenarios: ParityScenario[] = [
  scenario(
    'session/progress',
    'action-progress',
    {
      source: 'content',
      offsetsMs: PROGRESS_OFFSETS_MS,
      saves: Object.fromEntries(
        PROGRESS_KINDS.map((kind) => [kind, asJson(saveFor(kind))]),
      ) as JsonValue,
    },
    () =>
      Object.fromEntries(
        PROGRESS_KINDS.map((kind) => [
          kind,
          PROGRESS_OFFSETS_MS.map((offsetMs) =>
            actionProgressAt(saveFor(kind), FIXED_TIMESTAMP_MS + offsetMs),
          ),
        ]),
      ),
  ),

  ...RUNS.map((entry) =>
    scenario(
      'session/tick',
      entry.kind,
      {
        source: 'content',
        seed: SEED,
        offsetsMs: entry.offsetsMs,
        save: asJson(saveFor(entry.kind)),
      },
      () => run(entry.kind, entry.offsetsMs),
    ),
  ),

  ...TRAVEL_CASES.map((entry) =>
    scenario(
      'session/travel',
      entry.name,
      {
        source: 'content',
        seed: SEED,
        nowMs: FIXED_TIMESTAMP_MS,
        destinationId: entry.destinationId,
        browseMapId: entry.browseMapId,
        save: asJson(travelSaveFor(entry.kind)),
      },
      () =>
        plannedTravel(
          contentDatabase(),
          travelSaveFor(entry.kind),
          entry.destinationId,
          entry.browseMapId,
          FIXED_TIMESTAMP_MS,
        ),
    ),
  ),

  scenario(
    'session/travel',
    'timed-journey',
    {
      source: 'inline',
      database: timedTravelDatabase() as unknown as JsonValue,
      seed: SEED,
      nowMs: FIXED_TIMESTAMP_MS,
      destinationId: 'LOC-0003',
      browseMapId: 'MAP-0001',
      save: asJson(baseSave(asDatabase(timedTravelDatabase()))),
    },
    () =>
      plannedTravel(
        asDatabase(timedTravelDatabase()),
        baseSave(asDatabase(timedTravelDatabase())),
        'LOC-0003',
        'MAP-0001',
        FIXED_TIMESTAMP_MS,
      ),
  ),

  ...(['idle', 'gathering', 'fighting', 'production'] as const).map((kind) =>
    scenario(
      'session/persist',
      kind,
      { source: 'content', nowMs: FIXED_TIMESTAMP_MS, save: asJson(saveFor(kind)) },
      () =>
        asJson(
          prepareSaveForWrite(
            contentDatabase(),
            saveFor(kind),
            // A later clock, so the anchor visibly moves to the write time.
            FIXED_TIMESTAMP_MS + 90 * SECOND,
          ),
        ),
    ),
  ),
]
