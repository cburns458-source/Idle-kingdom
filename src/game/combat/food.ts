import { recordFoodConsumed } from '../achievements/progress'
import { FOOD_SLOT_ID, slotStack } from '../equipment/loadout'
import type { GameDatabase } from '../data/types'
import type { PlayerSave } from '../save/types'
import { equippedSpellStacks } from '../spells/spells'
import { playerMaxHp } from './stats'

export type FoodConsumption = {
  save: PlayerSave
  consumed: boolean
  healed: number
  foodName: string | null
}

export function tryConsumeFoodAfterVictory(db: GameDatabase, save: PlayerSave): FoodConsumption {
  const maxHp = playerMaxHp(db, save)
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
  if (healAmount === 0) {
    return { save: { ...save, maxHp }, consumed: false, healed: 0, foodName: null }
  }
  const damaging = healAmount < 0
  if (!damaging && save.currentHp >= maxHp) {
    return { save: { ...save, maxHp }, consumed: false, healed: 0, foodName: null }
  }

  const nextQuantity = food.quantity - 1
  const slots = {
    ...save.equipment.slots,
    [FOOD_SLOT_ID]: nextQuantity > 0 ? { itemId: food.itemId, quantity: nextQuantity } : null,
  }
  const nextHp = damaging
    ? Math.max(1, save.currentHp + healAmount)
    : Math.min(maxHp, save.currentHp + healAmount)
  const healed = nextHp - save.currentHp
  const foodName =
    db.Items.find((item) => item['Item ID'] === food.itemId)?.['Display Name'] ?? food.itemId

  return {
    save: recordFoodConsumed(
      {
        ...save,
        maxHp,
        currentHp: nextHp,
        equipment: { ...save.equipment, slots },
      },
      food.itemId,
    ),
    consumed: true,
    healed,
    foodName,
  }
}

function extraFoodFromItem(db: GameDatabase, itemId: string): number {
  const effects = db.Equipment.find((row) => row['Item ID'] === itemId)?.['Capabilities / Effects']
  if (typeof effects !== 'string') return 0
  let extra = 0
  for (const part of effects.split(';')) {
    const match = part.trim().toLowerCase().match(/^extra_food_per_round:(\d+(?:\.\d+)?)$/)
    if (match) extra += Number(match[1])
  }
  return extra
}

/** Extra equipped-food eats after an ongoing combat round. One per Gluttony stack. */
export function extraFoodPerRound(db: GameDatabase, save: PlayerSave): number {
  let extra = 0
  for (const stack of equippedSpellStacks(save)) {
    extra += extraFoodFromItem(db, stack.itemId)
  }
  return extra
}

function consumeFoodTimes(db: GameDatabase, save: PlayerSave, times: number): FoodConsumption {
  let current = save
  let consumed = false
  let healed = 0
  let foodName: string | null = null
  for (let i = 0; i < times; i += 1) {
    const bite = tryConsumeFoodAfterVictory(db, current)
    current = bite.save
    if (!bite.consumed) break
    consumed = true
    healed += bite.healed
    foodName = bite.foodName
  }
  return { save: current, consumed, healed, foodName }
}

/** Eats equipped food between combat rounds, once per extra_food_per_round stack. */
export function consumeFoodBetweenRounds(db: GameDatabase, save: PlayerSave): FoodConsumption {
  return consumeFoodTimes(db, save, extraFoodPerRound(db, save))
}

/**
 * Victory already eats one food. Each Gluttony stack adds another eat on top.
 */
export function consumeFoodAfterVictory(db: GameDatabase, save: PlayerSave): FoodConsumption {
  return consumeFoodTimes(db, save, 1 + extraFoodPerRound(db, save))
}
