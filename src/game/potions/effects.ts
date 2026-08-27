import { POTION_SLOT_ID, slotStack } from '../equipment/loadout'
import type { EquipmentRow, GameDatabase } from '../data/types'
import type { ActivePotionEffect, PlayerSave, PotionConsumeScope } from '../save/types'

export function capabilityTags(effects: string | null | undefined): string[] {
  if (typeof effects !== 'string') return []
  return effects
    .split(';')
    .map((part) => part.trim().toLowerCase())
    .filter(Boolean)
}

const SCOPE_TAGS: PotionConsumeScope[] = [
  'one_combat_encounter',
  'one_action',
  'one_standard_production_action',
]

/** Parse data-defined potion capability tags into a structured effect. */
export function parsePotionEffect(
  equipment: EquipmentRow | undefined,
  itemId: string,
): ActivePotionEffect | null {
  if (!equipment) return null
  const tags = capabilityTags(equipment['Capabilities / Effects'])
  if (!tags.includes('potion_slot')) return null

  const scope = SCOPE_TAGS.find((tag) => tags.includes(tag))
  if (!scope) return null

  let damageBonusPercent: number | null = null
  let enemyMaxHpDamagePercent: number | null = null
  let relativeDropChanceBonusPercent: number | null = null
  let baseDurationReductionPercent: number | null = null

  for (const tag of tags) {
    const damage = tag.match(/^\+(\d+(?:\.\d+)?)%\s*damage$/)
    if (damage) {
      damageBonusPercent = Number(damage[1])
      continue
    }
    const poison = tag.match(
      /^deals\s+(\d+(?:\.\d+)?)%\s+of\s+enemy\s+(?:current\s+hp\s+per\s+combat\s+round|maximum\s+hp)$/,
    )
    if (poison) {
      enemyMaxHpDamagePercent = Number(poison[1])
      continue
    }
    const drop = tag.match(/^\+(\d+(?:\.\d+)?)%\s+relative\s+drop\s+chance$/)
    if (drop) {
      relativeDropChanceBonusPercent = Number(drop[1])
      continue
    }
    const duration = tag.match(/^-(\d+(?:\.\d+)?)%\s+base\s+duration$/)
    if (duration) {
      baseDurationReductionPercent = Number(duration[1])
    }
  }

  return {
    scope,
    itemId,
    damageBonusPercent,
    enemyMaxHpDamagePercent,
    relativeDropChanceBonusPercent,
    baseDurationReductionPercent,
  }
}

export function clearActivePotionEffect(save: PlayerSave): PlayerSave {
  if (save.activePotionEffect == null) return save
  return { ...save, activePotionEffect: null }
}

/**
 * Consume one equipped potion when its scope matches the current eligible action.
 * Future potions work automatically if they use the same capability tag patterns.
 */
export function tryConsumePotionForScope(
  db: GameDatabase,
  save: PlayerSave,
  scope: PotionConsumeScope,
): {
  save: PlayerSave
  consumed: boolean
  effect: ActivePotionEffect | null
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
    return { save: cleared, consumed: false, effect: null, potionName: null }
  }

  const equipment = db.Equipment.find((row) => row['Item ID'] === potion.itemId)
  const effect = parsePotionEffect(equipment, potion.itemId)
  if (!effect || effect.scope !== scope) {
    return { save, consumed: false, effect: null, potionName: null }
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
      activePotionEffect: effect,
    },
    consumed: true,
    effect,
    potionName,
  }
}

/** Apply relative drop-chance bonus from an active one_action potion. */
export function applyPotionDropChance(
  baseChance: number | null,
  effect: ActivePotionEffect | null | undefined,
): number | null {
  if (typeof baseChance !== 'number') return baseChance
  const bonus = effect?.relativeDropChanceBonusPercent
  if (bonus == null || bonus === 0) return baseChance
  return Math.min(100, baseChance * (1 + bonus / 100))
}

/** Apply base-duration reduction from an active production potion. */
export function applyPotionDurationMs(
  baseDurationMs: number,
  effect: ActivePotionEffect | null | undefined,
): number {
  const reduction = effect?.baseDurationReductionPercent
  if (reduction == null || reduction <= 0) return Math.max(0, baseDurationMs)
  const factor = Math.max(0.01, 1 - reduction / 100)
  return Math.max(0, Math.floor(baseDurationMs * factor))
}

/** Flat HP from the old one-shot "deals N% of enemy maximum HP" tag. */
export function potionEnemyMaxHpDamage(
  enemyMaxHp: number,
  effect: ActivePotionEffect | null | undefined,
): number {
  const percent = effect?.enemyMaxHpDamagePercent
  if (percent == null || percent <= 0) return 0
  return Math.max(0, Math.floor(enemyMaxHp * (percent / 100)))
}

/** Lowest HP poison will leave: 10% of max, and never 0 while the enemy has HP. */
export function potionEnemyHpFloor(enemyMaxHp: number): number {
  if (enemyMaxHp <= 0) return 0
  return Math.max(1, Math.floor(enemyMaxHp * 0.1))
}

/**
 * After the player's swing: 10% of current HP, then clamp to the 10% max floor.
 * Poison cannot kill.
 */
export function applyPotionEnemyRoundDamage(
  enemyHp: number,
  enemyMaxHp: number,
  effect: ActivePotionEffect | null | undefined,
): number {
  const percent = effect?.enemyMaxHpDamagePercent
  if (percent == null || percent <= 0) return enemyHp
  const floorHp = potionEnemyHpFloor(enemyMaxHp)
  if (enemyHp <= floorHp) return enemyHp
  const damage = Math.floor(enemyHp * (percent / 100))
  if (damage <= 0) return enemyHp
  return Math.max(floorHp, enemyHp - damage)
}
