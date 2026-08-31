import {
  parseRelativeDropChanceBonusPercent,
  skillRelativeDropChanceTooltipLines,
} from '../loot/dropChance'
import type { EquipmentRow, GameDatabase } from '../data/types'

function skillDisplayName(
  db: GameDatabase | undefined,
  skillId: string | null | undefined,
): string | null {
  if (!skillId) return null
  const name = db?.Skills.find((skill) => skill['Skill ID'] === skillId)?.['Display Name']
  return typeof name === 'string' && name.length > 0 ? name : skillId
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

  const atr = equipment['Action Time Reduction %']
  if (typeof atr === 'number' && atr > 0) {
    const skills = [equipment['Required Skill ID'], equipment['Secondary Required Skill ID']]
      .map((id) => skillDisplayName(db, id))
      .filter((name): name is string => Boolean(name))
    lines.push(skills.length > 0 ? `${skills.join(', ')}: -${atr}% action time` : `-${atr}% action time`)
  }

  const dropBonus = parseRelativeDropChanceBonusPercent(equipment['Capabilities / Effects'])
  if (dropBonus > 0) {
    lines.push(`+${dropBonus}% relative Drop Chance`)
  }
  lines.push(...skillRelativeDropChanceTooltipLines(equipment['Capabilities / Effects']))

  return lines
}

export function equipmentForItemId(
  db: GameDatabase,
  itemId: string,
): EquipmentRow | undefined {
  return db.Equipment.find((row) => row['Item ID'] === itemId)
}
