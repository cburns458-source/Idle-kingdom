import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { CRITTER_DEFS } from '../critters/critters'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import type { PlayerSave } from '../save/types'
import {
  CRITTER_COLLECTOR_ACHIEVEMENT_ID,
  asAchievementRows,
  hasEveryCritter,
  syncProgressionMeta,
} from './progress'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('achievements and statistics', () => {
  it('uses all-skill tiers instead of one achievement per skill', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const rows = asAchievementRows(launch)
    const skillAll = rows.filter((row) => row['Check Type'] === 'skill_all')
    expect(skillAll.map((row) => row['Required Level']).sort((a, b) => Number(a) - Number(b))).toEqual(
      [50, 70, 100],
    )
    expect(rows.every((row) => !row['Target Skill ID'])).toBe(true)
    expect(rows.some((row) => row.Difficulty === 'Easy')).toBe(true)
    expect(rows.some((row) => row.Difficulty === 'Hard')).toBe(true)
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

  it('unlocks every-skill-50 only when every skill is 50', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const target = asAchievementRows(launch).find(
      (row) => row['Check Type'] === 'skill_all' && row['Required Level'] === 50,
    )
    expect(target).toBeTruthy()

    let save = createNewSave(launch)
    save = {
      ...save,
      skills: save.skills.map((skill) =>
        skill.skillId === 'SKL-0007' ? { ...skill, level: 50, xp: 1_000_000 } : skill,
      ),
    }
    save = syncProgressionMeta(launch, save)
    expect(save.statistics.values.total_experience).toBe(1_000_000)
    expect(
      save.achievements.some((row) => row.achievementId === target!['Achievement ID'] && row.unlocked),
    ).toBe(false)

    save = {
      ...save,
      skills: save.skills.map((skill) => ({ ...skill, level: 50, xp: 1_000_000 })),
    }
    save = syncProgressionMeta(launch, save)
    expect(
      save.achievements.some((row) => row.achievementId === target!['Achievement ID'] && row.unlocked),
    ).toBe(true)
  })
})
