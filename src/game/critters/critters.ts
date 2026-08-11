import type { PlayerSave } from '../save/types'

export const CRITTER_HOUR_MS = 3_600_000
/** One roll per full activity-hour at the Critter's location. */
export const CRITTER_SPAWN_CHANCE = 1 / 200

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
 * Full hours each roll 1/200; remainder is kept. No stacking if a spawn is already active.
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
): { ok: true; save: PlayerSave; critter: CritterDef; count: number } | { ok: false; reason: string } {
  const spawn = activeSpawnAtLocation(save, locationId)
  if (!spawn) return { ok: false, reason: 'No Critter here.' }
  const critter = getCritter(spawn.critterId)
  if (!critter) return { ok: false, reason: 'Unknown Critter.' }

  const collections = [...(save.critterCollections ?? [])]
  const existing = collections.find((row) => row.critterId === critter.id)
  let count = 1
  if (existing) {
    existing.count += 1
    count = existing.count
  } else {
    collections.push({ critterId: critter.id, count: 1 })
  }

  const spawns = (save.activeCritterSpawns ?? []).filter(
    (row) => row.locationId !== locationId,
  )

  return {
    ok: true,
    save: {
      ...save,
      critterCollections: collections,
      activeCritterSpawns: spawns,
    },
    critter,
    count,
  }
}
