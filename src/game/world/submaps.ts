import type { GameDatabase, LocationRow, MapRow } from '../data/types'
import {
  EAST_MAP_ID,
  MAIN_MAP_ID,
  WEST_MAP_ID,
  isFutureRegionMapId,
} from './constants'

function mapTypeOf(db: GameDatabase, mapId: string): string {
  const map = db.Maps.find((row) => row['Map ID'] === mapId)
  return map?.['Map Type'] ?? ''
}

/** True when Map Type marks a sub-map (unlimited; not hardcapped to cave/castle). */
export function isSubMapType(mapType: string | null | undefined): boolean {
  return (mapType ?? '').toLowerCase().includes('sub-map')
}

export function isSubMap(db: GameDatabase, mapId: string | null | undefined): boolean {
  if (!mapId || mapId === MAIN_MAP_ID || isFutureRegionMapId(mapId)) return false
  if (isSubMapType(mapTypeOf(db, mapId))) return true
  // Fallback: any map that hosts parented child locations.
  return db.Locations.some(
    (location) => location['Map ID'] === mapId && Boolean(location['Parent Location ID']),
  )
}

export function isSubMapGateway(location: LocationRow): boolean {
  return (location['Location Type'] ?? '').toLowerCase().includes('sub-map gateway')
}

/** Landing node written on a gateway row, if any. */
export function landingLocationIdFor(location: LocationRow): string | null {
  const raw = location['Landing Location ID']
  if (typeof raw !== 'string') return null
  const id = raw.trim()
  return id.length > 0 ? id : null
}

/**
 * World-map Travel to a gateway lands on that gateway's child-map node.
 * Standing on a gateway and choosing it again does the same, so Enter still
 * works if someone is already on an inaccessible entrance.
 * Intra-submap travel is left alone.
 */
export function resolveSubMapTravelDestination(
  db: GameDatabase,
  selectedLocationId: string,
  browseMapId: string,
  currentLocationId: string = selectedLocationId,
): string {
  const dest = db.Locations.find((row) => row['Location ID'] === selectedLocationId)
  if (!dest) return selectedLocationId
  const landing = landingLocationIdFor(dest)
  if (!landing) return selectedLocationId
  if (!db.Locations.some((row) => row['Location ID'] === landing)) return selectedLocationId
  const fromMain = browseMapId === MAIN_MAP_ID
  const standingOnGateway = currentLocationId === selectedLocationId
  if (!fromMain && !standingOnGateway) return selectedLocationId
  return landing
}

/** Where a walk onto [mapId] should start when the player is not on that map. */
export function entryLandingLocationIdForMap(db: GameDatabase, mapId: string): string | null {
  const gatewayId = gatewayLocationIdForSubMap(db, mapId)
  if (!gatewayId) return null
  const gateway = db.Locations.find((row) => row['Location ID'] === gatewayId)
  if (!gateway) return gatewayId
  return landingLocationIdFor(gateway) ?? gatewayId
}

/** Child Map ID for a gateway location, if any. */
export function subMapIdForGateway(
  db: GameDatabase,
  gatewayLocationId: string,
): string | null {
  const child = db.Locations.find(
    (location) => location['Parent Location ID'] === gatewayLocationId,
  )
  return child?.['Map ID'] ?? null
}

export function gatewayLocationIdForSubMap(
  db: GameDatabase,
  mapId: string,
): string | null {
  for (const location of db.Locations) {
    if (location['Map ID'] !== mapId) continue
    const parentId = location['Parent Location ID']
    if (parentId) return parentId
  }
  return null
}

export function subMapDisplayName(db: GameDatabase, mapId: string): string {
  const map = db.Maps.find((row) => row['Map ID'] === mapId) as MapRow | undefined
  return map?.['Display Name'] ?? 'Sub-map'
}

/** Drops a trailing "Map" so "Town Map" reads as "Town". */
export function shortSubMapName(db: GameDatabase, mapId: string): string {
  const name = subMapDisplayName(db, mapId)
  return name.replace(/\s+map$/i, '').trim() || name
}

/** Enter-button label for a gateway location. */
export function enterSubMapLabel(db: GameDatabase, gateway: LocationRow): string | null {
  const mapId = subMapIdForGateway(db, gateway['Location ID'])
  if (!mapId) return null
  return `Enter ${shortSubMapName(db, mapId)}`
}

/** Back-button label for a location that sits on a sub-map. */
export function backToSubMapLabel(db: GameDatabase, location: LocationRow): string | null {
  const mapId = location['Map ID'] ?? MAIN_MAP_ID
  if (!isSubMap(db, mapId) || isSubMapGateway(location)) return null
  return `Back to ${shortSubMapName(db, mapId)}`
}

/** Notes marker: location stays hidden/locked until unlockedLocationIds includes it. */
export function locationRequiresUnlock(location: LocationRow): boolean {
  return (location.Notes ?? '').toLowerCase().includes('requires_unlock')
}

export function isLocationUnlocked(
  save: { unlockedLocationIds?: string[] | null },
  location: LocationRow,
): boolean {
  if (!locationRequiresUnlock(location)) return true
  return (save.unlockedLocationIds ?? []).includes(location['Location ID'])
}

export function unlockLocation(
  save: { unlockedLocationIds?: string[] | null },
  locationId: string,
): string[] {
  const current = save.unlockedLocationIds ?? []
  if (current.includes(locationId)) return current
  return [...current, locationId]
}

/** Keep WEST_/EAST_ map constants usable without treating them as submaps. */
export function isBrowsableEmptyMap(mapId: string): boolean {
  return mapId === WEST_MAP_ID || mapId === EAST_MAP_ID
}
