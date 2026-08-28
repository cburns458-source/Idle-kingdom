import { recordFoodConsumed } from '../achievements/progress'
import { FOOD_SLOT_ID, slotStack } from '../equipment/loadout'
import type { GameDatabase } from '../data/types'
import type { InventoryStack, PlayerSave } from '../save/types'
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

/** Extra victory eats. One per Gluttony stack. Does not fire between rounds. */
export function extraFoodPerRound(db: GameDatabase, save: PlayerSave): number {
  let extra = 0
  for (const stack of equippedSpellStacks(save)) {
    extra += extraFoodFromItem(db, stack.itemId)
  }
  return extra
}

export function foodHealAmount(db: GameDatabase, itemId: string): number {
  const equipment = db.Equipment.find((row) => row['Item ID'] === itemId)
  return Number(equipment?.['Healing Amount'] ?? 0)
}

export function isEdibleItem(db: GameDatabase, itemId: string): boolean {
  return foodHealAmount(db, itemId) !== 0
}

export function isInCombat(save: PlayerSave): boolean {
  return save.combatEnemyId != null && save.combatEnemyId !== ''
}

function applyManualEat(
  db: GameDatabase,
  save: PlayerSave,
  itemId: string,
): { save: PlayerSave; healed: number; foodName: string } {
  const maxHp = playerMaxHp(db, save)
  const healAmount = foodHealAmount(db, itemId)
  const damaging = healAmount < 0
  const nextHp = damaging
    ? Math.max(1, save.currentHp + healAmount)
    : save.currentHp >= maxHp
      ? save.currentHp
      : Math.min(maxHp, save.currentHp + healAmount)
  const foodName =
    db.Items.find((item) => item['Item ID'] === itemId)?.['Display Name'] ?? itemId
  return {
    save: recordFoodConsumed({ ...save, maxHp, currentHp: nextHp }, itemId),
    healed: nextHp - save.currentHp,
    foodName,
  }
}

export type EatFoodResult =
  | { ok: true; save: PlayerSave; healed: number; foodName: string; reason?: undefined }
  | { ok: false; save?: undefined; healed: 0; foodName: null; reason: string }

/** One-tap eat from a bag stack. Consumes even at full HP (shows +0). */
export function eatInventoryFood(
  db: GameDatabase,
  save: PlayerSave,
  index: number,
): EatFoodResult {
  if (isInCombat(save)) {
    return { ok: false, healed: 0, foodName: null, reason: 'You cannot eat during combat.' }
  }
  const stack = save.inventory[index]
  if (!stack || stack.quantity <= 0) {
    return { ok: false, healed: 0, foodName: null, reason: 'Nothing to eat.' }
  }
  if (!isEdibleItem(db, stack.itemId)) {
    return { ok: false, healed: 0, foodName: null, reason: 'That cannot be eaten.' }
  }

  const eaten = applyManualEat(db, save, stack.itemId)
  const nextQuantity = stack.quantity - 1
  const inventory = save.inventory
    .map((row, rowIndex) =>
      rowIndex === index
        ? nextQuantity > 0
          ? { ...row, quantity: nextQuantity }
          : null
        : row,
    )
    .filter((row): row is InventoryStack => row != null)

  return {
    ok: true,
    save: { ...eaten.save, inventory },
    healed: eaten.healed,
    foodName: eaten.foodName,
  }
}

/** One-tap eat from the equipped food slot. Consumes even at full HP (shows +0). */
export function eatEquippedFood(db: GameDatabase, save: PlayerSave): EatFoodResult {
  if (isInCombat(save)) {
    return { ok: false, healed: 0, foodName: null, reason: 'You cannot eat during combat.' }
  }
  const food = slotStack(save, FOOD_SLOT_ID)
  if (!food || food.quantity <= 0) {
    return { ok: false, healed: 0, foodName: null, reason: 'Nothing to eat.' }
  }
  if (!isEdibleItem(db, food.itemId)) {
    return { ok: false, healed: 0, foodName: null, reason: 'That cannot be eaten.' }
  }

  const eaten = applyManualEat(db, save, food.itemId)
  const nextQuantity = food.quantity - 1
  return {
    ok: true,
    save: {
      ...eaten.save,
      equipment: {
        ...eaten.save.equipment,
        slots: {
          ...eaten.save.equipment.slots,
          [FOOD_SLOT_ID]: nextQuantity > 0 ? { ...food, quantity: nextQuantity } : null,
        },
      },
    },
    healed: eaten.healed,
    foodName: eaten.foodName,
  }
}

/**
 * Victory already eats one food. Each Gluttony stack adds another eat on top.
 * Combat rounds do not eat.
 */
export function consumeFoodAfterVictory(db: GameDatabase, save: PlayerSave): FoodConsumption {
  const times = 1 + extraFoodPerRound(db, save)
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
