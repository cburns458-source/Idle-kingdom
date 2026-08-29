import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { raiseSkillToMinimumLevel } from '../activity/xp'
import { prepareDatabase } from '../data/loadDatabase'
import { ARCHMAGE_ID, ARCANA_SKILL_ID, ARTISANRY_SKILL_ID } from '../npcs/knowledge'
import { createNewSave } from '../save/saveStore'
import { skillUnlocksBetween } from './levelUnlocks'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('skill unlocks between levels', () => {
  const { launch } = prepareDatabase(rawDatabase)

  function atLevel(skillId: string, level: number, mentors: string[] = []) {
    let save = createNewSave(launch, 0)
    if (level > 1) save = raiseSkillToMinimumLevel(save, launch, skillId, level).save
    if (mentors.length > 0) save = { ...save, unlockedNpcIds: mentors }
    return save
  }

  it('lists Leather Straps when crafting reaches 10', () => {
    const save = atLevel('SKL-0009', 10)
    const unlocks = skillUnlocksBetween(launch, save, 'SKL-0009', 9, 10)
    expect(unlocks.recipes).toContain('Leather Straps')
  })

  it('never lists combat fight or enemy action names', () => {
    const save = atLevel('SKL-0001', 20)
    const unlocks = skillUnlocksBetween(launch, save, 'SKL-0001', 1, 20)
    const names = [
      ...unlocks.unlockedActivities,
      ...unlocks.proficientActivities,
      ...unlocks.recipes,
      ...unlocks.projects,
    ]
    expect(names.some((name) => name.startsWith('Fight '))).toBe(false)
    expect(names).not.toContain('Cow')
    expect(names).not.toContain('Goblin Scout')
    for (const action of launch.Actions.filter((row) => row.Category === 'Combat')) {
      expect(names).not.toContain(action['Display Name'])
    }
  })

  it('lists Noose Wand at artisanry 25 without a mentor', () => {
    const save = atLevel(ARTISANRY_SKILL_ID, 25)
    const unlocks = skillUnlocksBetween(launch, save, ARTISANRY_SKILL_ID, 24, 25)
    expect(unlocks.projects).toContain('Noose Wand')
    expect(unlocks.projects).toContain('Lucky Necklace')
    expect(unlocks.projects).not.toContain('Cedar Bow')
  })

  it('lists Magic Net at arcana 40 only after the Archmage', () => {
    const locked = skillUnlocksBetween(launch, atLevel(ARCANA_SKILL_ID, 40), ARCANA_SKILL_ID, 39, 40)
    expect(locked.projects).not.toContain('Magic Net')

    const taught = atLevel(ARCANA_SKILL_ID, 40, [ARCHMAGE_ID])
    const unlocks = skillUnlocksBetween(launch, taught, ARCANA_SKILL_ID, 39, 40)
    expect(unlocks.projects).toContain('Magic Net')
  })
})
