import type { PlayerSave } from '../save/types'

export const ESSENCE_ITEM_ID = 'ITEM-0011'
export const CHEF_HAT_ITEM_ID = 'ITEM-0165'
export const WIZARD_HAT_ITEM_ID = 'ITEM-0166'
export const QUIVER_ITEM_ID = 'ITEM-0303'
export const COOKING_SKILL_ID = 'SKL-0007'
export const HUNTING_SKILL_ID = 'SKL-0005'

export const CHEF_HAT_DOUBLE_CHANCE = 1 / 100
export const WIZARD_HAT_ESSENCE_FACTOR = 0.99
export const QUIVER_HUNTING_XP_FACTOR = 1.05

export function hasEquippedItem(save: PlayerSave, itemId: string): boolean {
  return Object.values(save.equipment.slots).some((stack) => stack?.itemId === itemId)
}

/** 1% essence discount, with the remaining cost rounded up. */
export function wizardEssenceCost(baseQuantity: number, save: PlayerSave): number {
  if (baseQuantity <= 0) return 0
  if (!hasEquippedItem(save, WIZARD_HAT_ITEM_ID)) return baseQuantity
  return Math.ceil(baseQuantity * WIZARD_HAT_ESSENCE_FACTOR)
}

export function applyQuiverHuntingXp(amount: number, save: PlayerSave, skillId: string): number {
  if (amount <= 0) return 0
  if (skillId !== HUNTING_SKILL_ID) return amount
  if (!hasEquippedItem(save, QUIVER_ITEM_ID)) return amount
  return Math.floor(amount * QUIVER_HUNTING_XP_FACTOR)
}

export function chefHatOutputQuantity(
  baseQuantity: number,
  save: PlayerSave,
  skillId: string,
  random: () => number,
): number {
  if (baseQuantity <= 0) return 0
  if (skillId !== COOKING_SKILL_ID) return baseQuantity
  if (!hasEquippedItem(save, CHEF_HAT_ITEM_ID)) return baseQuantity
  if (random() >= CHEF_HAT_DOUBLE_CHANCE) return baseQuantity
  return baseQuantity * 2
}
