import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { getSkillProgress, raiseSkillToMinimumLevel } from './xp'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('raiseSkillToMinimumLevel', () => {
  it('raises alchemy to level 10 when below', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    expect(getSkillProgress(save, 'SKL-0010').level).toBeLessThan(10)

    const result = raiseSkillToMinimumLevel(save, launch, 'SKL-0010', 10)
    expect(result.raised).toBe(true)
    expect(getSkillProgress(result.save, 'SKL-0010').level).toBe(10)
    expect(getSkillProgress(result.save, 'SKL-0010').xp).toBe(
      launch.XPCurve.find((row) => row.Level === 10)?.['Total XP at Level'],
    )
  })

  it('does nothing when alchemy is already above level 10', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    const xpAt20 = launch.XPCurve.find((row) => row.Level === 20)?.['Total XP at Level'] ?? 0
    save = {
      ...save,
      skills: save.skills.map((skill) =>
        skill.skillId === 'SKL-0010' ? { ...skill, level: 20, xp: xpAt20 } : skill,
      ),
    }

    const result = raiseSkillToMinimumLevel(save, launch, 'SKL-0010', 10)
    expect(result.raised).toBe(false)
    expect(getSkillProgress(result.save, 'SKL-0010').level).toBe(20)
    expect(getSkillProgress(result.save, 'SKL-0010').xp).toBe(xpAt20)
  })
})
