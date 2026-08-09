import { FOOD_SLOT_ID, slotStack } from '../equipment/loadout'
import type { GameDatabase } from '../data/types'
import type { PlayerSave } from '../save/types'
import { playerMaxHp } from './stats'

export function tryConsumeFoodAfterVictory(
  db: GameDatabase,
  save: PlayerSave,
): { save: PlayerSave; consumed: boolean; healed: number; foodName: string | null } {
  const maxHp = playerMaxHp(db, save)
  if (save.currentHp >= maxHp) {
    return { save: { ...save, maxHp }, consumed: false, healed: 0, foodName: null }
  }

  const food = slotStack(save, FOOD_SLOT_ID)
  if (!food || food.quantity <= 0) {
    const cleared =
      food && food.quantity <= 0
        ? {
            ...save,
            maxHp,
            equipment: {
              ...save.equipment,
              slots: { ...save.equipment.slots, [FOOD_SLOT_ID]: null },
            },
          }
        : { ...save, maxHp }
    return { save: cleared, consumed: false, healed: 0, foodName: null }
  }

  const equipment = db.Equipment.find((row) => row['Item ID'] === food.itemId)
  const healAmount = Number(equipment?.['Healing Amount'] ?? 0)
  if (healAmount <= 0) {
    return { save: { ...save, maxHp }, consumed: false, healed: 0, foodName: null }
  }

  const nextQuantity = food.quantity - 1
  const slots = {
    ...save.equipment.slots,
    [FOOD_SLOT_ID]: nextQuantity > 0 ? { itemId: food.itemId, quantity: nextQuantity } : null,
  }

  const healed = Math.min(healAmount, maxHp - save.currentHp)
  const foodName =
    db.Items.find((item) => item['Item ID'] === food.itemId)?.['Display Name'] ?? food.itemId

  return {
    save: {
      ...save,
      maxHp,
      currentHp: Math.min(maxHp, save.currentHp + healed),
      equipment: { ...save.equipment, slots },
    },
    consumed: true,
    healed,
    foodName,
  }
}
