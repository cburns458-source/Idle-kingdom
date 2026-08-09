import { describe, expect, it } from 'vitest'
import type { EquipmentRow } from '../data/types'
import { equipmentTooltipStatLines } from './tooltips'

function equipment(partial: Partial<EquipmentRow>): EquipmentRow {
  return {
    'Equipment ID': 'EQP-TEST',
    'Item ID': 'ITEM-TEST',
    'Slot ID': 'SLOT-0001',
    'Required Skill ID': null,
    'Required Level': null,
    'Secondary Required Skill ID': null,
    'Secondary Required Level': null,
    'Min Damage': null,
    'Max Damage': null,
    'Damage Reduction': null,
    'HP Bonus': null,
    'Healing Amount': null,
    'Action Time Reduction %': null,
    'Capabilities / Effects': null,
    Status: 'Planned',
    Notes: null,
    ...partial,
  }
}

describe('equipment tooltips', () => {
  it('includes damage range and health when present', () => {
    expect(
      equipmentTooltipStatLines(
        equipment({ 'Min Damage': 10, 'Max Damage': 30, 'HP Bonus': 50 }),
      ),
    ).toEqual(['Damage 10–30', 'Health +50'])
  })

  it('omits zero or missing combat stats', () => {
    expect(equipmentTooltipStatLines(equipment({ 'HP Bonus': 0 }))).toEqual([])
    expect(equipmentTooltipStatLines(undefined)).toEqual([])
  })
})
