import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import type { EquipmentRow } from '../data/types'
import { equipmentTooltipStatLines } from './tooltips'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

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

  it('names the skill for action time reduction and lists other bonuses', () => {
    expect(
      equipmentTooltipStatLines(
        equipment({
          'Required Skill ID': 'SKL-0002',
          'Damage Reduction': 2,
          'Healing Amount': 15,
          'Action Time Reduction %': 5,
        }),
      ),
    ).toEqual(['Damage reduction +2', 'Healing +15', 'SKL-0002: -5% action time'])
  })

  it('resolves the skill name when the database is provided', () => {
    const { launch } = prepareDatabase(rawDatabase)
    expect(
      equipmentTooltipStatLines(
        equipment({
          'Required Skill ID': 'SKL-0002',
          'Action Time Reduction %': 5,
        }),
        launch,
      ),
    ).toEqual(['Mining: -5% action time'])
  })

  it('lists secondary skill action time and skill-gated drop chance', () => {
    const { launch } = prepareDatabase(rawDatabase)
    expect(
      equipmentTooltipStatLines(
        equipment({
          'Required Skill ID': 'SKL-0007',
          'Secondary Required Skill ID': 'SKL-0008',
          'Action Time Reduction %': 5,
        }),
        launch,
      ),
    ).toEqual(['Cooking, Metallurgy: -5% action time'])
    expect(
      equipmentTooltipStatLines(
        equipment({
          'Capabilities / Effects': 'harvesting_tool; +10% relative harvesting drop chance',
        }),
      ),
    ).toEqual(['+10% relative Harvesting Drop Chance'])
  })
})
