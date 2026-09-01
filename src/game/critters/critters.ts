import type { PlayerSave } from '../save/types'
import { grantCosmetic } from '../cosmetics/cosmetics'
import { petCosmeticIdForCritter } from './pets'

export const CRITTER_HOUR_MS = 3_600_000
/** One roll per full activity-hour at the Critter's location. */
export const CRITTER_SPAWN_CHANCE = 1 / 50

export interface CritterDef {
  id: string
  internalKey: string
  displayName: string
  locationId: string
  description: string
}

/** Expandable starter set — add rows here (or later from data) without schema churn. */
export const CRITTER_DEFS: CritterDef[] = [
  {
    id: 'CRT-0001',
    internalKey: 'fly',
    displayName: 'Fly',
    locationId: 'LOC-0001',
    description: 'A buzzing farmyard nuisance.',
  },
  {
    id: 'CRT-0002',
    internalKey: 'rat',
    displayName: 'Rat',
    locationId: 'LOC-0004',
    description: 'A dockside scavenger.',
  },
  {
    id: 'CRT-0003',
    internalKey: 'entling',
    displayName: 'Entling',
    locationId: 'LOC-0018',
    description: 'A tiny forest spirit of bark and leaf.',
  },
  {
    id: 'CRT-0004',
    internalKey: 'mole',
    displayName: 'Mole',
    locationId: 'LOC-0011',
    description: 'A tunnel-dweller from the deep mines.',
  },
]

export function critterForLocation(locationId: string): CritterDef | undefined {
  return CRITTER_DEFS.find((critter) => critter.locationId === locationId)
}

export function getCritter(critterId: string): CritterDef | undefined {
  return CRITTER_DEFS.find((critter) => critter.id === critterId)
}

export function collectionCount(save: PlayerSave, critterId: string): number {
  return save.critterCollections?.find((row) => row.critterId === critterId)?.count ?? 0
}

export function activeSpawnAtLocation(
  save: PlayerSave,
  locationId: string,
): { locationId: string; critterId: string; appearedAt: string } | null {
  return (
    save.activeCritterSpawns?.find((spawn) => spawn.locationId === locationId) ?? null
  )
}

/**
 * Apply activity time at a location toward Critter hour-rolls.
 * Full hours each roll 1/50; remainder is kept. No stacking if a spawn is already active.
 */
export function applyActivityTimeTowardCritters(
  save: PlayerSave,
  locationId: string,
  elapsedMs: number,
  nowMs: number = Date.now(),
  random: () => number = Math.random,
): { save: PlayerSave; spawned: CritterDef | null; hoursRolled: number } {
  if (elapsedMs <= 0) return { save, spawned: null, hoursRolled: 0 }
  const critter = critterForLocation(locationId)
  if (!critter) return { save, spawned: null, hoursRolled: 0 }

  const progress = { ...(save.critterProgressMs ?? {}) }
  const prior = progress[locationId] ?? 0
  const total = prior + elapsedMs
  const hoursRolled = Math.floor(total / CRITTER_HOUR_MS)
  progress[locationId] = total % CRITTER_HOUR_MS

  let next: PlayerSave = { ...save, critterProgressMs: progress }
  if (hoursRolled <= 0) return { save: next, spawned: null, hoursRolled: 0 }

  // Already waiting to be collected — do not stack.
  if (activeSpawnAtLocation(next, locationId)) {
    return { save: next, spawned: null, hoursRolled }
  }

  let spawned: CritterDef | null = null
  for (let i = 0; i < hoursRolled; i += 1) {
    if (random() < CRITTER_SPAWN_CHANCE) {
      spawned = critter
      break
    }
  }

  if (!spawned) return { save: next, spawned: null, hoursRolled }

  const spawns = [
    ...(next.activeCritterSpawns ?? []).filter((row) => row.locationId !== locationId),
    {
      locationId,
      critterId: spawned.id,
      appearedAt: new Date(nowMs).toISOString(),
    },
  ]
  next = { ...next, activeCritterSpawns: spawns }
  return { save: next, spawned, hoursRolled }
}

export function collectCritter(
  save: PlayerSave,
  locationId: string,
):
  | { ok: true; save: PlayerSave; critter: CritterDef; count: number; message: string }
  | { ok: false; reason: string } {
  const spawn = activeSpawnAtLocation(save, locationId)
  if (!spawn) return { ok: false, reason: 'No Critter here.' }
  const critter = getCritter(spawn.critterId)
  if (!critter) return { ok: false, reason: 'Unknown Critter.' }

  const existing = (save.critterCollections ?? []).find((row) => row.critterId === critter.id)
  const count = (existing?.count ?? 0) + 1
  const collections = existing
    ? (save.critterCollections ?? []).map((row) =>
        row.critterId === critter.id ? { ...row, count } : row,
      )
    : [...(save.critterCollections ?? []), { critterId: critter.id, count }]

  const spawns = (save.activeCritterSpawns ?? []).filter(
    (row) => row.locationId !== locationId,
  )

  let next: PlayerSave = {
    ...save,
    critterCollections: collections,
    activeCritterSpawns: spawns,
  }
  // First find unlocks the matching pet cosmetic for the wardrobe Pet slot.
  if (count === 1) {
    const petId = petCosmeticIdForCritter(critter.id)
    if (petId) next = grantCosmetic(next, petId).save
  }

  return {
    ok: true,
    save: next,
    critter,
    count,
    message:
      count > 1
        ? `Collected ${critter.displayName} (×${count}).`
        : `Collected ${critter.displayName}!`,
  }
}

/** Demo/debug: force-spawn the habitat Critter if one is available and none is waiting. */
export function spawnCritterAtLocation(
  save: PlayerSave,
  locationId: string,
  nowMs: number = Date.now(),
): { ok: true; save: PlayerSave; critter: CritterDef } | { ok: false; reason: string } {
  const critter = critterForLocation(locationId)
  if (!critter) {
    return { ok: false, reason: 'No Critter is available at this location.' }
  }
  if (activeSpawnAtLocation(save, locationId)) {
    return { ok: false, reason: 'A Critter is already waiting here.' }
  }

  const spawns = [
    ...(save.activeCritterSpawns ?? []).filter((row) => row.locationId !== locationId),
    {
      locationId,
      critterId: critter.id,
      appearedAt: new Date(nowMs).toISOString(),
    },
  ]

  return {
    ok: true,
    save: {
      ...save,
      activeCritterSpawns: spawns,
    },
    critter,
  }
}
