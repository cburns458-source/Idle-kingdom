import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { CRITTER_DEFS } from '../critters/critters'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import type { PlayerSave } from '../save/types'
import {
  CRITTER_COLLECTOR_ACHIEVEMENT_ID,
  REVOCABLE_ACHIEVEMENT_CATEGORY,
  asAchievementRows,
  hasEveryCritter,
  syncProgressionMeta,
} from './progress'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('achievements and statistics', () => {
  it('has one level-50 achievement per Launch skill', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const milestones = asAchievementRows(launch).filter(
      (row) => row.Category !== REVOCABLE_ACHIEVEMENT_CATEGORY,
    )
    expect(milestones).toHaveLength(launch.Skills.length)
    expect(milestones.every((row) => row['Required Level'] === 50)).toBe(true)
  })

  it('holds Critter Collector only while the collection is complete', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = createNewSave(launch)
    const held = (save: PlayerSave) =>
      syncProgressionMeta(launch, save).achievements.some(
        (row) => row.achievementId === CRITTER_COLLECTOR_ACHIEVEMENT_ID && row.unlocked,
      )

    expect(hasEveryCritter(base)).toBe(false)
    expect(held(base)).toBe(false)

    const complete: PlayerSave = {
      ...base,
      critterCollections: CRITTER_DEFS.map((critter) => ({ critterId: critter.id, count: 1 })),
    }
    expect(hasEveryCritter(complete)).toBe(true)
    expect(held(complete)).toBe(true)

    // A new critter joining the world is the same shape as one going missing.
    const earned = syncProgressionMeta(launch, complete)
    const widened: PlayerSave = {
      ...earned,
      critterCollections: earned.critterCollections.slice(1),
    }
    expect(held(widened)).toBe(false)
    // And catching up gets it back.
    expect(held(complete)).toBe(true)
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
