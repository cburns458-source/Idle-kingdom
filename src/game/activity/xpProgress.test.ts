import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { skillXpProgress } from '../activity/xpProgress'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('skillXpProgress', () => {
  it('reports total XP and progress within the current level', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const progress = skillXpProgress(launch, 200)
    expect(progress.level).toBe(1)
    expect(progress.totalXp).toBe(200)
    expect(progress.intoLevel).toBe(200)
    expect(progress.toNextLevel).toBe(800)
    expect(progress.nextLevel).toBe(2)
    expect(progress.atCap).toBe(false)
  })

  it('starts the next level progress after crossing a threshold', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const progress = skillXpProgress(launch, 800)
    expect(progress.level).toBe(2)
    expect(progress.intoLevel).toBe(0)
    expect(progress.toNextLevel).toBe(880)
    expect(progress.nextLevel).toBe(3)
  })
})
