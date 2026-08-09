import type { EquipmentRow, GameDatabase } from '../data/types'
import type { PlayerSave } from '../save/types'
import { configNumber } from '../activity/gathering'

const WEAPON_SLOT = 'SLOT-0001'

function equippedRows(db: GameDatabase, save: PlayerSave): EquipmentRow[] {
  const rows: EquipmentRow[] = []
  for (const itemId of Object.values(save.equipment.slots)) {
    if (!itemId) continue
    const row = db.Equipment.find((entry) => entry['Item ID'] === itemId)
    if (row) rows.push(row)
  }
  return rows
}

export function playerDamageRange(
  db: GameDatabase,
  save: PlayerSave,
): { min: number; max: number } {
  const weaponId = save.equipment.slots[WEAPON_SLOT]
  if (weaponId) {
    const weapon = db.Equipment.find((entry) => entry['Item ID'] === weaponId)
    const min = weapon?.['Min Damage']
    const max = weapon?.['Max Damage']
    if (typeof min === 'number' && typeof max === 'number') {
      return { min, max: Math.max(min, max) }
    }
  }
  return {
    min: configNumber(db, 'unarmed_min_damage', 10),
    max: configNumber(db, 'unarmed_max_damage', 30),
  }
}

export function playerDamageReduction(db: GameDatabase, save: PlayerSave): number {
  return equippedRows(db, save).reduce((sum, row) => sum + Number(row['Damage Reduction'] ?? 0), 0)
}

export function playerMaxHp(db: GameDatabase, save: PlayerSave): number {
  const base = configNumber(db, 'starting_max_hp', 1000)
  const bonus = equippedRows(db, save).reduce((sum, row) => sum + Number(row['HP Bonus'] ?? 0), 0)
  return base + bonus
}

export function rollDamage(min: number, max: number, random: () => number = Math.random): number {
  const lo = Math.min(min, max)
  const hi = Math.max(min, max)
  return lo + Math.floor(random() * (hi - lo + 1))
}

export function applyMitigation(
  rawDamage: number,
  reduction: number,
  damageFloor: number,
): number {
  return Math.max(damageFloor, rawDamage - Math.max(0, reduction))
}
