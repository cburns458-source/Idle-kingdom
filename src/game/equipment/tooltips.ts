import { parseLockpickBreakChanceReductionPercent } from './loadout'
import {
  parseRelativeDropChanceBonusPercent,
  skillRelativeDropChanceTooltipLines,
} from '../loot/dropChance'
import { parsePotionEffect } from '../potions/effects'
import { POTION_ACTION_DURATION } from '../save/types'
import { parseSpellPowerPercent } from '../spells/spells'
import type { EquipmentRow, GameDatabase } from '../data/types'

function skillDisplayName(
  db: GameDatabase | undefined,
  skillId: string | null | undefined,
): string | null {
  if (!skillId) return null
  const name = db?.Skills.find((skill) => skill['Skill ID'] === skillId)?.['Display Name']
  return typeof name === 'string' && name.length > 0 ? name : skillId
}

/** Potion effect line from capability tags, always including the 6-use duration. */
export function potionTooltipStatLines(
  equipment: EquipmentRow | undefined,
  itemId: string,
): string[] {
  const effect = parsePotionEffect(equipment, itemId)
  if (!effect) return []
  const parts: string[] = []
  if (effect.instantHealMaxHpPercent != null && effect.instantHealMaxHpPercent > 0) {
    parts.push(`Heals ${effect.instantHealMaxHpPercent}%`)
  }
  if (effect.regenMaxHpPercentPerRound != null && effect.regenMaxHpPercentPerRound > 0) {
    parts.push(`Heals ${effect.regenMaxHpPercentPerRound}% each round`)
  }
  if (
    effect.damageBonusMin != null &&
    effect.damageBonusMax != null &&
    (effect.damageBonusMin > 0 || effect.damageBonusMax > 0)
  ) {
    parts.push(`+${effect.damageBonusMin}–${effect.damageBonusMax} damage`)
  }
  if (effect.damageBonusPercent != null && effect.damageBonusPercent > 0) {
    parts.push(`+${effect.damageBonusPercent}% damage`)
  }
  if (effect.relativeDropChanceBonusPercent != null && effect.relativeDropChanceBonusPercent > 0) {
    parts.push(`+${effect.relativeDropChanceBonusPercent}% relative Drop Chance`)
  }
  if (effect.baseDurationReductionPercent != null && effect.baseDurationReductionPercent > 0) {
    parts.push(`-${effect.baseDurationReductionPercent}% base duration`)
  }
  const poison = effect.enemyMaxHpDamagePercent
  if (poison != null && poison > 0) {
    parts.push(`Deals ${poison}% of enemy current HP each round`)
  }
  parts.push(`${POTION_ACTION_DURATION} uses`)
  return [parts.join(', ')]
}

/** Combat-facing equipment stats for hold tooltips. */
export function equipmentTooltipStatLines(
  equipment: EquipmentRow | undefined,
  db?: GameDatabase,
): string[] {
  if (!equipment) return []
  const lines: string[] = []
  const min = equipment['Min Damage']
  const max = equipment['Max Damage']
  if (typeof min === 'number' && typeof max === 'number') {
    lines.push(`Damage ${min}–${Math.max(min, max)}`)
  } else if (typeof min === 'number') {
    lines.push(`Damage ${min}`)
  } else if (typeof max === 'number') {
    lines.push(`Damage ${max}`)
  }

  const hp = equipment['HP Bonus']
  if (typeof hp === 'number' && hp !== 0) {
    lines.push(hp > 0 ? `Health +${hp}` : `Health ${hp}`)
  }

  const reduction = equipment['Damage Reduction']
  if (typeof reduction === 'number' && reduction !== 0) {
    lines.push(reduction > 0 ? `Damage reduction +${reduction}` : `Damage reduction ${reduction}`)
  }

  const healing = equipment['Healing Amount']
  if (typeof healing === 'number' && healing !== 0) {
    lines.push(healing > 0 ? `Healing +${healing}` : `Healing ${healing}`)
  }

  const successRaw = equipment['Action Time Reduction %']
  if (typeof successRaw === 'number' && successRaw > 0) {
    const skills = [equipment['Required Skill ID'], equipment['Secondary Required Skill ID']]
      .map((id) => skillDisplayName(db, id))
      .filter((name): name is string => Boolean(name))
    lines.push(
      skills.length > 0
        ? `${skills.join(', ')}: +${successRaw}% success chance`
        : `+${successRaw}% success chance`,
    )
  }

  const potionLines = potionTooltipStatLines(equipment, equipment['Item ID'])
  if (potionLines.length > 0) {
    lines.push(...potionLines)
  } else {
    const dropBonus = parseRelativeDropChanceBonusPercent(equipment['Capabilities / Effects'])
    if (dropBonus > 0) {
      lines.push(`+${dropBonus}% relative Drop Chance`)
    }
  }
  lines.push(...skillRelativeDropChanceTooltipLines(equipment['Capabilities / Effects']))
  const lockpickBreakReduction = parseLockpickBreakChanceReductionPercent(
    equipment['Capabilities / Effects'],
  )
  if (lockpickBreakReduction !== 0) {
    lines.push(
      lockpickBreakReduction > 0
        ? `Lockpick break chance -${lockpickBreakReduction}%`
        : `Lockpick break chance +${Math.abs(lockpickBreakReduction)}%`,
    )
  }

  const spellPower = parseSpellPowerPercent(equipment['Capabilities / Effects'])
  if (spellPower > 0) {
    lines.push(`Equipped spells +${spellPower}% stronger`)
  }

  return lines
}

export function equipmentForItemId(
  db: GameDatabase,
  itemId: string,
): EquipmentRow | undefined {
  return db.Equipment.find((row) => row['Item ID'] === itemId)
}
