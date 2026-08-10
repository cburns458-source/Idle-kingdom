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

/** Enter-button label for a gateway location. */
export function enterSubMapLabel(db: GameDatabase, gateway: LocationRow): string | null {
  const mapId = subMapIdForGateway(db, gateway['Location ID'])
  if (!mapId) return null
  const name = subMapDisplayName(db, mapId)
  // Prefer short CTA: "Enter Town Map" → "Enter Town" when name ends with Map.
  const short = name.replace(/\s+map$/i, '').trim() || name
  return `Enter ${short}`
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
