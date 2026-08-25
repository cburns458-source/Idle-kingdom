import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { COMBAT_SKILL_ID } from '../combat/stats'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { HARVESTING_SKILL_ID, FISHING_SKILL_ID } from '../skills/skillActions'
import { skillIdsForLocation } from './locationSkills'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('location skill icons', () => {
  it('the farm shows combat and harvesting, not every skill', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    const skills = skillIdsForLocation(launch, save, 'LOC-0001')
    expect(skills).toEqual(expect.arrayContaining([COMBAT_SKILL_ID, HARVESTING_SKILL_ID]))
    expect(skills).not.toContain(FISHING_SKILL_ID)
  })

  it('a combat camp includes combat from the fight, not from PvP', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    expect(skillIdsForLocation(launch, save, 'LOC-0003')).toContain(COMBAT_SKILL_ID)
  })
})
