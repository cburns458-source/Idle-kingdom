import type { CosmeticRow, CosmeticSlotRow, GameDatabase } from '../data/types'
import type { EquipResult } from '../equipment/loadout'
import type { CosmeticsState, PlayerSave } from '../save/types'

export function cosmeticSlots(db: GameDatabase): CosmeticSlotRow[] {
  return db.CosmeticSlots
}

export function cosmeticSlotById(db: GameDatabase, slotId: string): CosmeticSlotRow | undefined {
  return db.CosmeticSlots.find((row) => row['Cosmetic Slot ID'] === slotId)
}

export function cosmeticsForSlot(db: GameDatabase, slotId: string): CosmeticRow[] {
  return db.Cosmetics.filter((row) => row['Cosmetic Slot ID'] === slotId)
}

export function cosmeticById(db: GameDatabase, cosmeticId: string): CosmeticRow | undefined {
  return db.Cosmetics.find((row) => row['Cosmetic ID'] === cosmeticId)
}

export function cosmeticByItemId(db: GameDatabase, itemId: string): CosmeticRow | undefined {
  return db.Cosmetics.find((row) => row['Item ID'] === itemId)
}

function cosmeticsState(save: PlayerSave): CosmeticsState {
  return save.cosmetics ?? { unlocked: [], equipped: {} }
}

export function isCosmeticUnlocked(save: PlayerSave, cosmeticId: string): boolean {
  return cosmeticsState(save).unlocked.includes(cosmeticId)
}

export function equippedCosmeticId(save: PlayerSave, slotId: string): string | null {
  return cosmeticsState(save).equipped[slotId] ?? null
}

/**
 * Unlock a Cosmetic permanently (idempotent — owning multiples has no
 * effect). Cosmetics live in their own always-owned collection rather than
 * the inventory bag, so granting one can never fail for lack of bag space.
 */
export function grantCosmetic(
  save: PlayerSave,
  cosmeticId: string,
): { save: PlayerSave; granted: boolean; isFirstEver: boolean } {
  const current = cosmeticsState(save)
  if (current.unlocked.includes(cosmeticId)) {
    return { save, granted: false, isFirstEver: false }
  }
  const isFirstEver = current.unlocked.length === 0
  return {
    save: {
      ...save,
      cosmetics: {
        ...current,
        unlocked: [...current.unlocked, cosmeticId],
      },
    },
    granted: true,
    isFirstEver,
  }
}

/**
 * Equip an owned Cosmetic into its slot, or pass `cosmeticId: null` to
 * unequip. Blocked (not performed) if the Cosmetic isn't unlocked yet or
 * doesn't belong to the given slot — this can never fail for capacity
 * reasons the way gear equip can, since Cosmetics don't use bag slots.
 */
export function equipCosmetic(
  db: GameDatabase,
  save: PlayerSave,
  slotId: string,
  cosmeticId: string | null,
): EquipResult {
  const current = cosmeticsState(save)
  if (cosmeticId == null) {
    return {
      ok: true,
      save: { ...save, cosmetics: { ...current, equipped: { ...current.equipped, [slotId]: null } } },
    }
  }
  const cosmetic = cosmeticById(db, cosmeticId)
  if (!cosmetic) {
    return { ok: false, reason: 'Unknown Cosmetic.' }
  }
  if (cosmetic['Cosmetic Slot ID'] !== slotId) {
    return { ok: false, reason: 'That Cosmetic does not belong in this slot.' }
  }
  if (!current.unlocked.includes(cosmeticId)) {
    return { ok: false, reason: 'That Cosmetic has not been unlocked yet.' }
  }
  return {
    ok: true,
    save: {
      ...save,
      cosmetics: { ...current, equipped: { ...current.equipped, [slotId]: cosmeticId } },
    },
  }
}
