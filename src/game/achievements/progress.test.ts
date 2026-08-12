import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { asAchievementRows, syncProgressionMeta } from './progress'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('achievements and statistics', () => {
  it('has one level-50 achievement per Launch skill', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const achievements = asAchievementRows(launch)
    expect(achievements).toHaveLength(launch.Skills.length)
    expect(achievements.every((row) => row['Required Level'] === 50)).toBe(true)
  })

  it('unlocks a skill achievement at level 50 and syncs totals', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = {
      ...save,
      skills: save.skills.map((skill) =>
        skill.skillId === 'SKL-0007' ? { ...skill, level: 50, xp: 1_000_000 } : skill,
      ),
    }
    save = syncProgressionMeta(launch, save)
    expect(save.statistics.values.total_level).toBeGreaterThan(50)
    expect(save.statistics.values.total_experience).toBe(1_000_000)
    const cooking = asAchievementRows(launch).find((row) => row['Target Skill ID'] === 'SKL-0007')
    expect(cooking).toBeTruthy()
    expect(
      save.achievements.some(
        (row) => row.achievementId === cooking!['Achievement ID'] && row.unlocked,
      ),
    ).toBe(true)
  })
})
