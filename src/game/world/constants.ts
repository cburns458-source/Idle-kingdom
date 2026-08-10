/** Travel delay when database Base Duration is null. 0 = instant travel. */
export const DEFAULT_TRAVEL_DURATION_MS = 0

export const MAIN_MAP_ID = 'MAP-0001'
export const CAVE_MAP_ID = 'MAP-0002'
export const CASTLE_MAP_ID = 'MAP-0003'
export const WEST_MAP_ID = 'MAP-0004'
export const EAST_MAP_ID = 'MAP-0005'

export const CAVE_ENTRANCE_ID = 'LOC-0010'
export const CASTLE_GATEWAY_ID = 'LOC-0013'
export const WEST_HORIZON_ID = 'LOC-0019'
export const EAST_HORIZON_ID = 'LOC-0020'

export function isSubMapId(mapId: string | null | undefined): boolean {
  return mapId === CAVE_MAP_ID || mapId === CASTLE_MAP_ID
}

export function isFutureHorizonLocation(locationId: string): boolean {
  return locationId === WEST_HORIZON_ID || locationId === EAST_HORIZON_ID
}

export function adjacentMapForHorizon(locationId: string): string | null {
  if (locationId === WEST_HORIZON_ID) return WEST_MAP_ID
  if (locationId === EAST_HORIZON_ID) return EAST_MAP_ID
  return null
}
