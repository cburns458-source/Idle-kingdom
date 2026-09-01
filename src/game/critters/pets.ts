import { grantCosmetic } from '../cosmetics/cosmetics'
import type { PlayerSave } from '../save/types'

/** Critter ID → Pet Cosmetic ID. First collection unlocks the matching pet. */
export const CRITTER_PET_COSMETIC_IDS: Record<string, string> = {
  'CRT-0001': 'COS-0004',
  'CRT-0002': 'COS-0005',
  'CRT-0003': 'COS-0006',
  'CRT-0004': 'COS-0007',
}

export function petCosmeticIdForCritter(critterId: string): string | null {
  return CRITTER_PET_COSMETIC_IDS[critterId] ?? null
}

/** Critter internal key used for asset paths, keyed by pet cosmetic. */
export const PET_COSMETIC_CRITTER_KEYS: Record<string, string> = {
  'COS-0004': 'fly',
  'COS-0005': 'rat',
  'COS-0006': 'entling',
  'COS-0007': 'mole',
}

export function critterKeyForPetCosmetic(cosmeticId: string): string | null {
  return PET_COSMETIC_CRITTER_KEYS[cosmeticId] ?? null
}

/** Unlock pets for every Critter already in the collection (migration / catch-up). */
export function grantPetsForCollectedCritters(save: PlayerSave): PlayerSave {
  let next = save
  for (const row of save.critterCollections ?? []) {
    if ((row.count ?? 0) < 1) continue
    const cosmeticId = petCosmeticIdForCritter(row.critterId)
    if (!cosmeticId) continue
    next = grantCosmetic(next, cosmeticId).save
  }
  return next
}
