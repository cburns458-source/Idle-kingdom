import type { PlayerSave } from '../save/types'

export const ESSENCE_ITEM_ID = 'ITEM-0011'
export const CHEF_HAT_ITEM_ID = 'ITEM-0165'
export const WIZARD_HAT_ITEM_ID = 'ITEM-0166'
export const QUIVER_ITEM_ID = 'ITEM-0303'
export const ALCHEMIST_GOGGLES_ITEM_ID = 'ITEM-0318'
export const COOKING_SKILL_ID = 'SKL-0007'
export const HUNTING_SKILL_ID = 'SKL-0005'
export const ALCHEMY_SKILL_ID = 'SKL-0010'

export const CHEF_HAT_DOUBLE_CHANCE = 1 / 100
export const WIZARD_HAT_ESSENCE_FACTOR = 0.99
export const QUIVER_HUNTING_XP_FACTOR = 1.05
/** Max potions granted per Alchemy craft (queue space assumes this). */
export const ALCHEMY_POTION_OUTPUT_MAX = 3
/** Min potions granted per Alchemy craft without Alchemist Goggles. */
export const ALCHEMY_POTION_OUTPUT_MIN = 1
/** Min potions granted per Alchemy craft with Alchemist Goggles. */
export const ALCHEMY_POTION_OUTPUT_GOGGLES_MIN = 2

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

/** Fair die for potion crafts: 1–3 normally, 2–3 with Alchemist Goggles. */
export function alchemyPotionOutputQuantity(
  baseQuantity: number,
  save: PlayerSave,
  skillId: string,
  random: () => number,
): number {
  if (baseQuantity <= 0) return 0
  if (skillId !== ALCHEMY_SKILL_ID) return baseQuantity
  const roll = random()
  if (hasEquippedItem(save, ALCHEMIST_GOGGLES_ITEM_ID)) {
    const die = Math.floor(roll * 2) + ALCHEMY_POTION_OUTPUT_GOGGLES_MIN
    return baseQuantity * die
  }
  const die = Math.floor(roll * ALCHEMY_POTION_OUTPUT_MAX) + ALCHEMY_POTION_OUTPUT_MIN
  return baseQuantity * die
}

/** Per-craft output used when reserving bag space for a production queue. */
export function productionOutputReservePerCraft(
  skillId: string,
  baseQuantity: number,
): number {
  if (skillId === ALCHEMY_SKILL_ID) {
    return baseQuantity * ALCHEMY_POTION_OUTPUT_MAX
  }
  return baseQuantity
}
