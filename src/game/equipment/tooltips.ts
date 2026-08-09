import type { EquipmentRow, GameDatabase } from '../data/types'

/** Combat-facing equipment stats for hold tooltips. */
export function equipmentTooltipStatLines(equipment: EquipmentRow | undefined): string[] {
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

  return lines
}

export function equipmentForItemId(
  db: GameDatabase,
  itemId: string,
): EquipmentRow | undefined {
  return db.Equipment.find((row) => row['Item ID'] === itemId)
}
