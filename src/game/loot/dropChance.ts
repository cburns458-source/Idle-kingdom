import { capabilityTags } from '../potions/effects'
import type { GameDatabase } from '../data/types'
import type { PlayerSave } from '../save/types'

/** Sum every `+N% relative Drop Chance` tag in a capability string. */
export function parseRelativeDropChanceBonusPercent(
  effects: string | null | undefined,
): number {
  let total = 0
  for (const tag of capabilityTags(effects)) {
    const match = tag.match(/^\+(\d+(?:\.\d+)?)%\s+relative\s+drop\s+chance$/)
    if (match) total += Number(match[1])
  }
  return total
}

/** Equipped gear bonuses (Lucky Necklace, future luck items). Same bonus types add. */
export function equippedRelativeDropChanceBonusPercent(
  db: GameDatabase,
  save: PlayerSave,
): number {
  let total = 0
  for (const stack of Object.values(save.equipment.slots)) {
    if (!stack?.itemId) continue
    const equipment = db.Equipment.find((row) => row['Item ID'] === stack.itemId)
    total += parseRelativeDropChanceBonusPercent(equipment?.['Capabilities / Effects'])
  }
  return total
}

/**
 * Total relative drop-chance bonus from all sources (gear + active luck potion).
 * Same bonus types stack by addition.
 */
export function totalRelativeDropChanceBonusPercent(
  db: GameDatabase,
  save: PlayerSave,
): number {
  let total = equippedRelativeDropChanceBonusPercent(db, save)
  if (save.activePotionEffect?.scope === 'one_action') {
    total += save.activePotionEffect.relativeDropChanceBonusPercent ?? 0
  }
  return total
}

/** Apply a summed relative drop-chance bonus: base × (1 + bonus/100), capped at 100. */
export function applyRelativeDropChance(
  baseChance: number | null,
  relativeBonusPercent: number,
): number | null {
  if (typeof baseChance !== 'number') return baseChance
  if (!relativeBonusPercent) return baseChance
  return Math.min(100, baseChance * (1 + relativeBonusPercent / 100))
}
