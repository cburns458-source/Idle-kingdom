import { POTION_SLOT_ID, slotStack } from '../equipment/loadout'
import type { EquipmentRow, GameDatabase } from '../data/types'
import type { PlayerSave } from '../save/types'

function capabilityTags(effects: string | null | undefined): string[] {
  if (typeof effects !== 'string') return []
  return effects
    .split(';')
    .map((part) => part.trim().toLowerCase())
    .filter(Boolean)
}

/** Percent damage bonus from a one-combat-encounter potion (e.g. "+5% damage" → 5). */
export function encounterPotionDamageBonusPercent(
  equipment: EquipmentRow | undefined,
): number | null {
  if (!equipment) return null
  const tags = capabilityTags(equipment['Capabilities / Effects'])
  if (!tags.includes('one_combat_encounter')) return null
  for (const tag of tags) {
    const match = tag.match(/^\+(\d+(?:\.\d+)?)%\s*damage$/)
    if (match) return Number(match[1])
  }
  return null
}

/**
 * Consume one equipped encounter potion when a combat action begins.
 * Stores the damage bonus for the duration of that encounter.
 */
export function tryConsumeCombatEncounterPotion(
  db: GameDatabase,
  save: PlayerSave,
): {
  save: PlayerSave
  consumed: boolean
  damageBonusPercent: number
  potionName: string | null
} {
  const potion = slotStack(save, POTION_SLOT_ID)
  if (!potion || potion.quantity <= 0) {
    const cleared =
      potion && potion.quantity <= 0
        ? {
            ...save,
            equipment: {
              ...save.equipment,
              slots: { ...save.equipment.slots, [POTION_SLOT_ID]: null },
            },
          }
        : save
    return { save: cleared, consumed: false, damageBonusPercent: 0, potionName: null }
  }

  const equipment = db.Equipment.find((row) => row['Item ID'] === potion.itemId)
  const damageBonusPercent = encounterPotionDamageBonusPercent(equipment)
  if (damageBonusPercent == null || damageBonusPercent <= 0) {
    return { save, consumed: false, damageBonusPercent: 0, potionName: null }
  }

  const nextQuantity = potion.quantity - 1
  const slots = {
    ...save.equipment.slots,
    [POTION_SLOT_ID]:
      nextQuantity > 0 ? { itemId: potion.itemId, quantity: nextQuantity } : null,
  }
  const potionName =
    db.Items.find((item) => item['Item ID'] === potion.itemId)?.['Display Name'] ??
    potion.itemId

  return {
    save: {
      ...save,
      equipment: { ...save.equipment, slots },
    },
    consumed: true,
    damageBonusPercent,
    potionName,
  }
}
