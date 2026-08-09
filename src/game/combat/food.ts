import type { GameDatabase } from '../data/types'
import type { PlayerSave } from '../save/types'
import { playerMaxHp } from './stats'

const FOOD_SLOT = 'SLOT-0011'

export function tryConsumeFoodAfterVictory(
  db: GameDatabase,
  save: PlayerSave,
): { save: PlayerSave; consumed: boolean; healed: number; foodName: string | null } {
  const maxHp = playerMaxHp(db, save)
  if (save.currentHp >= maxHp) {
    return { save: { ...save, maxHp }, consumed: false, healed: 0, foodName: null }
  }

  const foodItemId = save.equipment.slots[FOOD_SLOT]
  if (!foodItemId) {
    return { save: { ...save, maxHp }, consumed: false, healed: 0, foodName: null }
  }

  const equipment = db.Equipment.find((row) => row['Item ID'] === foodItemId)
  const healAmount = Number(equipment?.['Healing Amount'] ?? 0)
  if (healAmount <= 0) {
    return { save: { ...save, maxHp }, consumed: false, healed: 0, foodName: null }
  }

  const stack = save.inventory.find((entry) => entry.itemId === foodItemId)
  if (!stack || stack.quantity <= 0) {
    return {
      save: {
        ...save,
        maxHp,
        equipment: {
          ...save.equipment,
          slots: { ...save.equipment.slots, [FOOD_SLOT]: null },
        },
      },
      consumed: false,
      healed: 0,
      foodName: null,
    }
  }

  const inventory = save.inventory
    .map((entry) =>
      entry.itemId === foodItemId ? { ...entry, quantity: entry.quantity - 1 } : entry,
    )
    .filter((entry) => entry.quantity > 0)

  const healed = Math.min(healAmount, maxHp - save.currentHp)
  const slots = { ...save.equipment.slots }
  if (!inventory.some((entry) => entry.itemId === foodItemId)) {
    slots[FOOD_SLOT] = null
  }

  const foodName =
    db.Items.find((item) => item['Item ID'] === foodItemId)?.['Display Name'] ?? foodItemId

  return {
    save: {
      ...save,
      maxHp,
      currentHp: Math.min(maxHp, save.currentHp + healed),
      inventory,
      equipment: { ...save.equipment, slots },
    },
    consumed: true,
    healed,
    foodName,
  }
}
