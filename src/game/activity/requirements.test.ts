import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import type { RequirementRow } from '../data/types'
import { createNewSave } from '../save/saveStore'
import { evaluateRequirement, isKnownRequirementType } from './requirements'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('requirements', () => {
  it('knows the launched requirement types', () => {
    expect(isKnownRequirementType('Tool Capability')).toBe(true)
    expect(isKnownRequirementType('Made Up')).toBe(false)
  })

  it('fails closed on an unknown requirement type', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    const requirement = {
      'Requirement ID': 'REQ-BAD',
      'Requirement Type': 'Made Up',
      'Entity Type': 'Activity',
      'Entity ID': 'ACT-0001',
      'Reference ID / Value': 'x',
    } as RequirementRow
    const result = evaluateRequirement(launch, save, requirement)
    expect(result.met).toBe(false)
    expect(result.detail).toBe('Unknown requirement.')
  })

  it('requires a harpoon for sea turtle, not a fishing rod', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const requirement = launch.Requirements.find((row) => row['Requirement ID'] === 'REQ-0118')!
    expect(requirement['Reference ID / Value']).toBe('harpoon')
    const base = createNewSave(launch)
    const withRod = {
      ...base,
      equipment: {
        ...base.equipment,
        slots: { ...base.equipment.slots, 'SLOT-0001': { itemId: 'ITEM-0103', quantity: 1 } },
      },
    }
    const withHarpoon = {
      ...base,
      equipment: {
        ...base.equipment,
        slots: { ...base.equipment.slots, 'SLOT-0001': { itemId: 'ITEM-0113', quantity: 1 } },
      },
    }
    expect(evaluateRequirement(launch, withRod, requirement).met).toBe(false)
    expect(evaluateRequirement(launch, withHarpoon, requirement).met).toBe(true)
  })
})
