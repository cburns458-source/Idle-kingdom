import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { actionsForSkill } from './skillActions'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'public/data/game-database.json'), 'utf8'),
)

describe('actionsForSkill', () => {
  it('lists harvesting actions by display name and drops duplicate Harvest potato', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const items = actionsForSkill(launch, 'SKL-0004')
    const potatoes = items.filter((item) => item.displayName === 'Harvest potato')
    expect(potatoes).toHaveLength(1)
    expect(potatoes[0]?.proficiencyLevel).toBe(10)
    expect(items.every((item) => !item.displayName.startsWith('ACN-'))).toBe(true)
    expect(items.some((item) => item.displayName === 'Gather fernleaf' && item.proficiencyLevel === 5)).toBe(
      true,
    )
  })

  it('omits proficiency when the action has none', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const combat = actionsForSkill(launch, 'SKL-0001')
    expect(combat.length).toBeGreaterThan(0)
    expect(combat.every((item) => item.proficiencyLevel == null)).toBe(true)
  })
})
