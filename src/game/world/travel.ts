import type { GameDatabase, LocationRow, TravelConnectionRow } from '../data/types'
import {
  CASTLE_GATEWAY_ID,
  CASTLE_MAP_ID,
  CAVE_ENTRANCE_ID,
  CAVE_MAP_ID,
  DEFAULT_TRAVEL_DURATION_MS,
  MAIN_MAP_ID,
} from './constants'

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
export function resolveActiveMapId(location: LocationRow): string {
  const mapId = getLocationMapId(location)
  if (mapId === CAVE_MAP_ID || location['Location ID'] === CAVE_ENTRANCE_ID) {
    return CAVE_MAP_ID
  }
  if (mapId === CASTLE_MAP_ID || location['Location ID'] === CASTLE_GATEWAY_ID) {
    return CASTLE_MAP_ID
  }
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
 * Main map: all Launch locations on MAP-0001 (owner-approved node travel).
 * Sub-maps: gateway + children on that map, plus connection endpoints.
 */
export function locationsForMapView(db: GameDatabase, mapId: string): LocationRow[] {
  if (mapId === MAIN_MAP_ID) {
    return db.Locations.filter((location) => location['Map ID'] === MAIN_MAP_ID)
  }

  const onMap = db.Locations.filter((location) => location['Map ID'] === mapId)
  const gatewayId = mapId === CAVE_MAP_ID ? CAVE_ENTRANCE_ID : CASTLE_GATEWAY_ID
  const gateway = db.Locations.find((location) => location['Location ID'] === gatewayId)
  const merged = new Map<string, LocationRow>()
  for (const location of onMap) merged.set(location['Location ID'], location)
  if (gateway) merged.set(gateway['Location ID'], gateway)
  return [...merged.values()]
}

export function canTravelTo(
  db: GameDatabase,
  fromLocationId: string,
  toLocationId: string,
  activeMapId: string,
): boolean {
  if (fromLocationId === toLocationId) return false
  const destination = db.Locations.find((location) => location['Location ID'] === toLocationId)
  if (!destination) return false

  if (activeMapId === MAIN_MAP_ID) {
    if (destination['Map ID'] !== MAIN_MAP_ID) return false
    const origin = db.Locations.find((location) => location['Location ID'] === fromLocationId)
    // Main-map travel is available from overworld/gateway nodes, not from deep sub-locations.
    return origin?.['Map ID'] === MAIN_MAP_ID
  }

  if (findConnection(db, fromLocationId, toLocationId)) return true

  // Allow moving among nodes shown on the active sub-map.
  return locationsForMapView(db, activeMapId).some(
    (location) => location['Location ID'] === toLocationId,
  )
}

export function stopPrimaryActivity<T extends { currentActivityId: string | null; activityStartedAt: string | null }>(
  save: T,
): T {
  return {
    ...save,
    currentActivityId: null,
    activityStartedAt: null,
  }
}

export function applyTravelArrival<
  T extends {
    currentLocationId: string
    currentActivityId: string | null
    activityStartedAt: string | null
  },
>(save: T, destinationLocationId: string): T {
  return {
    ...stopPrimaryActivity(save),
    currentLocationId: destinationLocationId,
  }
}
