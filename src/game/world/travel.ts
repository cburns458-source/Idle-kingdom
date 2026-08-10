import { isDeathPaused } from '../combat/engine'
import { stopPrimaryActivityNow } from '../activity/transition'
import type { GameDatabase, LocationRow, TravelConnectionRow } from '../data/types'
import type { PlayerSave } from '../save/types'
import {
  DEFAULT_TRAVEL_DURATION_MS,
  MAIN_MAP_ID,
  isFutureHorizonLocation,
} from './constants'
import {
  gatewayLocationIdForSubMap,
  isBrowsableEmptyMap,
  isLocationUnlocked,
  isSubMap,
  subMapIdForGateway,
} from './submaps'

export function travelDurationMs(connection?: TravelConnectionRow | null): number {
  const base = connection?.['Base Duration']
  if (typeof base === 'number' && Number.isFinite(base) && base >= 0) {
    // Database values are expected in seconds when present.
    return base * 1000
  }
  return DEFAULT_TRAVEL_DURATION_MS
}

export function getLocationMapId(location: LocationRow): string {
  return location['Map ID'] ?? MAIN_MAP_ID
}

/** Map shown when browsing from the player's current location. */
export function resolveActiveMapId(db: GameDatabase, location: LocationRow): string {
  const mapId = getLocationMapId(location)
  if (isSubMap(db, mapId)) return mapId
  const childMap = subMapIdForGateway(db, location['Location ID'])
  if (childMap) return childMap
  return MAIN_MAP_ID
}

function isTwoWay(connection: TravelConnectionRow): boolean {
  const direction = (connection.Direction ?? 'Two-way').toLowerCase()
  return direction.includes('two')
}

export function connectionsFrom(
  db: GameDatabase,
  fromLocationId: string,
): TravelConnectionRow[] {
  return db.TravelConnections.filter((connection) => {
    if (connection['From Location ID'] === fromLocationId) return true
    if (isTwoWay(connection) && connection['To Location ID'] === fromLocationId) return true
    return false
  })
}

export function findConnection(
  db: GameDatabase,
  fromLocationId: string,
  toLocationId: string,
): TravelConnectionRow | undefined {
  return db.TravelConnections.find((connection) => {
    if (
      connection['From Location ID'] === fromLocationId &&
      connection['To Location ID'] === toLocationId
    ) {
      return true
    }
    if (
      isTwoWay(connection) &&
      connection['From Location ID'] === toLocationId &&
      connection['To Location ID'] === fromLocationId
    ) {
      return true
    }
    return false
  })
}

/**
 * Destinations selectable on a map.
 * Main map: all Launch locations on MAP-0001.
 * Sub-maps: every node on that map plus its gateway (from Parent Location ID).
 * Locked nodes are omitted unless unlocked on the optional save.
 */
export function locationsForMapView(
  db: GameDatabase,
  mapId: string,
  save?: Pick<PlayerSave, 'unlockedLocationIds'> | null,
): LocationRow[] {
  if (mapId === MAIN_MAP_ID) {
    return db.Locations.filter((location) => location['Map ID'] === MAIN_MAP_ID)
  }

  if (isBrowsableEmptyMap(mapId)) {
    return []
  }

  const onMap = db.Locations.filter((location) => location['Map ID'] === mapId)
  const gatewayId = gatewayLocationIdForSubMap(db, mapId)
  const gateway = gatewayId
    ? db.Locations.find((location) => location['Location ID'] === gatewayId)
    : undefined
  const unlockState = save ?? { unlockedLocationIds: [] }
  const merged = new Map<string, LocationRow>()
  for (const location of onMap) {
    if (!isLocationUnlocked(unlockState, location)) continue
    merged.set(location['Location ID'], location)
  }
  if (gateway) merged.set(gateway['Location ID'], gateway)
  return [...merged.values()]
}

export function canTravelTo(
  db: GameDatabase,
  fromLocationId: string,
  toLocationId: string,
  activeMapId: string,
  save?: Pick<PlayerSave, 'unlockedLocationIds'> | null,
): boolean {
  if (fromLocationId === toLocationId) return false
  if (isFutureHorizonLocation(toLocationId)) return false
  const destination = db.Locations.find((location) => location['Location ID'] === toLocationId)
  if (!destination) return false
  if (!isLocationUnlocked(save ?? { unlockedLocationIds: [] }, destination)) return false

  if (activeMapId === MAIN_MAP_ID) {
    // World-map travel is allowed from anywhere, including sub-locations.
    // Future horizon gateways are browse-only.
    return destination['Map ID'] === MAIN_MAP_ID && !isFutureHorizonLocation(toLocationId)
  }

  if (findConnection(db, fromLocationId, toLocationId)) return true

  // Allow moving among nodes shown on the active sub-map.
  return locationsForMapView(db, activeMapId, save).some(
    (location) => location['Location ID'] === toLocationId,
  )
}

/**
 * Move the player to a destination and stop any running Primary Activity with refunds.
 * Death pause blocks arrival (activity is not cleared).
 */
export function applyTravelArrival(
  db: GameDatabase,
  save: PlayerSave,
  destinationLocationId: string,
  nowMs: number = Date.now(),
): PlayerSave {
  if (isDeathPaused(save, nowMs)) return save
  const stopped = stopPrimaryActivityNow(db, save, nowMs)
  return {
    ...stopped,
    currentLocationId: destinationLocationId,
  }
}
