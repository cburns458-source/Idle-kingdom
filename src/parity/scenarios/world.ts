import { mulberry32 } from '../../game/rng/mulberry32'
import type { PlayerSave } from '../../game/save/types'
import {
  applyHostileTravelArrival,
  forcedHostileActivity,
  hostileActivitiesAt,
  hostileForceMessage,
} from '../../game/world/hostility'
import {
  canClaimLocationSearch,
  claimLocationSearch,
  locationSearchCooldownRemainingMs,
  locationSearchesAt,
} from '../../game/world/locationSearch'
import { layoutForMap, positionForLocation } from '../../game/world/mapLayout'
import {
  applyTravelArrival,
  canTravelTo,
  connectionsFrom,
  findConnection,
  getLocationMapId,
  locationsForMapView,
  resolveActiveMapId,
  travelDurationMs,
} from '../../game/world/travel'
import { scenario, type JsonValue, type ParityScenario } from '../types'
import { contentDatabase } from './contentDatabase'
import { asJson, baseSave, fullBagSave, queuedProductionSave } from './saveFixtures'

const PINNED_NOW_MS = Date.parse('2026-01-01T00:00:00.000Z')

type SaveKind = 'base' | 'leveled' | 'queued-production' | 'gathering' | 'death-paused' | 'full-bag'

/** Combat 10, which clears every Goblin Camp danger warning. */
function leveledSave(): PlayerSave {
  const base = baseSave(contentDatabase())
  return {
    ...base,
    characterName: 'Veteran',
    skills: base.skills.map((skill) =>
      skill.skillId === 'SKL-0001' ? { ...skill, level: 10, xp: 50_000 } : skill,
    ),
  }
}

/** Mid-gather in the Meadow, so arrival has a primary activity to stop. */
function gatheringSave(): PlayerSave {
  const base = baseSave(contentDatabase())
  return {
    ...base,
    characterName: 'Gatherer',
    currentLocationId: 'LOC-0009',
    currentActivityId: 'ACT-0012',
    activityStartedAt: '2026-01-01T00:00:00.000Z',
    currentActionId: 'ACN-0029',
    actionStartedAt: '2026-01-01T00:00:00.000Z',
    actionDurationMs: 12_000,
  }
}

/** Recovering from a death, which blocks arrival entirely. */
function deathPausedSave(): PlayerSave {
  return {
    ...gatheringSave(),
    characterName: 'Downed',
    deathPauseUntil: new Date(PINNED_NOW_MS + 30_000).toISOString(),
  }
}

function saveFor(kind: SaveKind): PlayerSave {
  const db = contentDatabase()
  if (kind === 'base') return baseSave(db)
  if (kind === 'leveled') return leveledSave()
  if (kind === 'queued-production') return queuedProductionSave(db)
  if (kind === 'gathering') return gatheringSave()
  if (kind === 'death-paused') return deathPausedSave()
  return fullBagSave(db, ['ITEM-0100'])
}

function withSave(kind: SaveKind, extra: Record<string, JsonValue> = {}): JsonValue {
  return { source: 'content', save: asJson(saveFor(kind)), nowMs: PINNED_NOW_MS, ...extra }
}

const MAP_IDS = ['MAP-0001', 'MAP-0002', 'MAP-0003', 'MAP-0004', 'MAP-0005', 'MAP-0006', 'MAP-0007', 'MAP-0008', 'MAP-0009', 'MAP-9999']
const TRAVEL_LOCATIONS = [
  'LOC-0002',
  'LOC-0003',
  'LOC-0010',
  'LOC-0011',
  'LOC-0013',
  'LOC-0017',
  'LOC-0018',
  'LOC-0019',
  'LOC-0026',
  'LOC-0027',
  'LOC-0028',
  'LOC-0029',
  'LOC-9999',
]
const SEARCH_LOCATIONS = ['LOC-0010', 'LOC-0002', 'LOC-9999']
const HOSTILE_LOCATIONS = ['LOC-0003', 'LOC-0006', 'LOC-0032', 'LOC-0002', 'LOC-9999']

/** Every ordered pair among the sampled nodes, on each map that could show them. */
function travelPairs(): Array<{ from: string; to: string; mapId: string }> {
  const pairs: Array<{ from: string; to: string; mapId: string }> = []
  for (const from of TRAVEL_LOCATIONS) {
    for (const to of TRAVEL_LOCATIONS) {
      for (const mapId of ['MAP-0001', 'MAP-0002', 'MAP-0006', 'MAP-0007']) {
        pairs.push({ from, to, mapId })
      }
    }
  }
  return pairs
}

export const worldScenarios: ParityScenario[] = [
  scenario(
    'world/travel/connections',
    'lookups',
    { source: 'content', locations: TRAVEL_LOCATIONS },
    () => {
      const db = contentDatabase()
      return {
        byLocation: TRAVEL_LOCATIONS.map((locationId) => ({
          locationId,
          from: connectionsFrom(db, locationId).map((row) => row['Connection ID']),
          durations: connectionsFrom(db, locationId).map((row) => travelDurationMs(row)),
        })),
        pairs: TRAVEL_LOCATIONS.flatMap((from) =>
          TRAVEL_LOCATIONS.map((to) => ({
            from,
            to,
            connectionId: findConnection(db, from, to)?.['Connection ID'] ?? null,
          })),
        ),
        missingDuration: [travelDurationMs(null), travelDurationMs(undefined)],
      } as unknown as JsonValue
    },
  ),

  scenario(
    'world/travel/maps',
    'views',
    { source: 'content', mapIds: MAP_IDS, locations: TRAVEL_LOCATIONS },
    () => {
    const db = contentDatabase()
    const unlocked = { unlockedLocationIds: ['LOC-0026'] }
    return {
      byMap: MAP_IDS.map((mapId) => ({
        mapId,
        locked: locationsForMapView(db, mapId).map((row) => row['Location ID']),
        unlocked: locationsForMapView(db, mapId, unlocked).map((row) => row['Location ID']),
      })),
      activeMap: TRAVEL_LOCATIONS.map((locationId) => {
        const location = db.Locations.find((row) => row['Location ID'] === locationId)
        return {
          locationId,
          mapId: location ? getLocationMapId(location) : null,
          activeMapId: location ? resolveActiveMapId(db, location) : null,
        }
      }),
    } as unknown as JsonValue
    },
  ),

  scenario(
    'world/travel/reachability',
    'pairs',
    { source: 'content', locations: TRAVEL_LOCATIONS },
    () => {
      const db = contentDatabase()
      const unlocked = { unlockedLocationIds: ['LOC-0026'] }
      return {
        results: travelPairs().map((pair) => ({
          ...pair,
          locked: canTravelTo(db, pair.from, pair.to, pair.mapId),
          unlocked: canTravelTo(db, pair.from, pair.to, pair.mapId, unlocked),
        })),
      } as unknown as JsonValue
    },
  ),

  ...(['base', 'gathering', 'queued-production', 'death-paused'] as const).map((kind) =>
    scenario('world/travel/arrival', kind, withSave(kind, { destinations: ['LOC-0001'] }), () => ({
      arrived: asJson(applyTravelArrival(contentDatabase(), saveFor(kind), 'LOC-0001', PINNED_NOW_MS)),
      sameLocation: asJson(
        applyTravelArrival(
          contentDatabase(),
          saveFor(kind),
          saveFor(kind).currentLocationId,
          PINNED_NOW_MS,
        ),
      ),
    }) as unknown as JsonValue),
  ),

  scenario(
    'world/hostility/warnings',
    'by-location',
    { source: 'content', locations: HOSTILE_LOCATIONS },
    () => {
      const db = contentDatabase()
      return {
        byLocation: HOSTILE_LOCATIONS.map((locationId) => ({
          locationId,
          hostile: hostileActivitiesAt(db, locationId).map((row) => row['Activity ID']),
        })),
      } as unknown as JsonValue
    },
  ),

  ...(['base', 'leveled'] as const).map((kind) =>
    scenario('world/hostility/forced', kind, withSave(kind, { locations: HOSTILE_LOCATIONS }), () => {
      const db = contentDatabase()
      const save = saveFor(kind)
      return {
        byLocation: HOSTILE_LOCATIONS.map((locationId) => ({
          locationId,
          forced: forcedHostileActivity(db, save, locationId)?.['Activity ID'] ?? null,
        })),
      } as unknown as JsonValue
    }),
  ),

  ...([
    { name: 'forced-combat', save: 'base' as const, destination: 'LOC-0003' },
    { name: 'high-level-safe', save: 'leveled' as const, destination: 'LOC-0003' },
    { name: 'safe-destination', save: 'base' as const, destination: 'LOC-0002' },
    { name: 'stops-gathering', save: 'gathering' as const, destination: 'LOC-0002' },
    { name: 'force-blocked', save: 'base' as const, destination: 'LOC-0006' },
    { name: 'citadel-training', save: 'base' as const, destination: 'LOC-0032' },
    { name: 'death-paused', save: 'death-paused' as const, destination: 'LOC-0003' },
  ]).map((entry) =>
    scenario(
      'world/hostility/arrival',
      entry.name,
      withSave(entry.save, { destination: entry.destination, seed: 424_242 }),
      () => {
        const db = contentDatabase()
        const result = applyHostileTravelArrival(
          db,
          saveFor(entry.save),
          entry.destination,
          PINNED_NOW_MS,
          mulberry32(424_242),
        )
        return {
          save: asJson(result.save),
          forcedActivityId: result.forcedActivityId,
          forceBlockedReason: result.forceBlockedReason,
          threatenedActivityId: result.threatenedActivityId,
          message: hostileForceMessage(db, result),
        } as unknown as JsonValue
      },
    ),
  ),

  scenario(
    'world/hostility/message',
    'unknown-activity',
    { source: 'content', save: asJson(baseSave(contentDatabase())) },
    () => {
      const db = contentDatabase()
      const save = baseSave(db)
      return {
        noThreat: hostileForceMessage(db, {
          save,
          forcedActivityId: null,
          forceBlockedReason: null,
          threatenedActivityId: null,
        }),
        unknownForced: hostileForceMessage(db, {
          save,
          forcedActivityId: 'ACT-9999',
          forceBlockedReason: null,
          threatenedActivityId: 'ACT-9999',
        }),
        unknownBlocked: hostileForceMessage(db, {
          save,
          forcedActivityId: null,
          forceBlockedReason: 'Requirements not met.',
          threatenedActivityId: 'ACT-9999',
        }),
        neither: hostileForceMessage(db, {
          save,
          forcedActivityId: null,
          forceBlockedReason: null,
          threatenedActivityId: 'ACT-0002',
        }),
      } as unknown as JsonValue
    },
  ),

  scenario(
    'world/search/spots',
    'cooldowns',
    withSave('base', { locations: SEARCH_LOCATIONS }),
    () => {
      const db = contentDatabase()
      const save = saveFor('base')
      const claimed: PlayerSave = {
        ...save,
        locationSearchClaims: {
          'SRCH-0001': new Date(PINNED_NOW_MS - 60_000).toISOString(),
          'SRCH-0002': 'not-a-date',
        },
      }
      return {
        byLocation: SEARCH_LOCATIONS.map((locationId) => ({
          locationId,
          searches: locationSearchesAt(db, locationId).map((search) => ({
            searchId: search['Search ID'],
            freshRemaining: locationSearchCooldownRemainingMs(save, search, PINNED_NOW_MS),
            freshReady: canClaimLocationSearch(save, search, PINNED_NOW_MS),
            claimedRemaining: locationSearchCooldownRemainingMs(claimed, search, PINNED_NOW_MS),
            claimedReady: canClaimLocationSearch(claimed, search, PINNED_NOW_MS),
            afterCooldown: canClaimLocationSearch(
              claimed,
              search,
              PINNED_NOW_MS + 25 * 60 * 60 * 1000,
            ),
            unparseableClaim: locationSearchCooldownRemainingMs(
              { ...claimed, locationSearchClaims: { [search['Search ID']]: 'not-a-date' } },
              search,
              PINNED_NOW_MS,
            ),
          })),
        })),
      } as unknown as JsonValue
    },
  ),

  ...([
    { name: 'ok', save: 'base' as const, searchId: 'SRCH-0001' },
    { name: 'unknown-spot', save: 'base' as const, searchId: 'SRCH-9999' },
    { name: 'full-bag', save: 'full-bag' as const, searchId: 'SRCH-0001' },
  ]).map((entry) =>
    scenario(
      'world/search/claim',
      entry.name,
      withSave(entry.save, { searchId: entry.searchId }),
      () => {
        const db = contentDatabase()
        const first = claimLocationSearch(db, saveFor(entry.save), entry.searchId, PINNED_NOW_MS)
        const again = claimLocationSearch(db, first.save, entry.searchId, PINNED_NOW_MS + 60_000)
        const later = claimLocationSearch(
          db,
          first.save,
          entry.searchId,
          PINNED_NOW_MS + 25 * 60 * 60 * 1000,
        )
        const asResult = (result: typeof first) => ({
          ok: result.ok,
          save: asJson(result.save),
          reason: result.reason ?? null,
          itemId: result.itemId ?? null,
          itemName: result.itemName ?? null,
          quantity: result.quantity ?? null,
        })
        return {
          first: asResult(first),
          again: asResult(again),
          later: asResult(later),
        } as unknown as JsonValue
      },
    ),
  ),

  scenario('world/layout', 'positions', { source: 'content', mapIds: MAP_IDS }, () => {
    const db = contentDatabase()
    return {
      byMap: MAP_IDS.map((mapId) => ({
        mapId,
        nodes: Object.entries(layoutForMap(mapId))
          .map(([locationId, position]) => ({ locationId, ...position }))
          .sort((a, b) => a.locationId.localeCompare(b.locationId)),
      })),
      byLocation: db.Locations.map((location) => ({
        locationId: location['Location ID'],
        position: positionForLocation(location),
      })),
    } as unknown as JsonValue
  }),
]
