import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { buildLeaderboardSnapshot, boardLabel } from './snapshots'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'public/data/game-database.json'), 'utf8'),
)

describe('leaderboard snapshot builder', () => {
  it('includes total boards and one board per launch skill', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = {
      ...createNewSave(launch),
      statistics: {
        values: {
          gold_earned: 50,
          monsters_killed: 3,
          bounties_completed: 1,
        },
      },
      critterCollections: [{ critterId: 'CRT-0001', count: 2 }],
    }
    const snapshot = buildLeaderboardSnapshot(launch, save)
    const keys = snapshot.boards.map((board) => board.boardKey)
    expect(keys).toContain('total_level')
    expect(keys).toContain('total_experience')
    expect(keys).toContain('gold_earned')
    expect(keys).toContain('monsters_killed')
    expect(keys).toContain('critters_collected')
    expect(keys).toContain('bounties_completed')
    expect(snapshot.boards.find((board) => board.boardKey === 'critters_collected')?.value).toBe(2)
    expect(snapshot.boards.find((board) => board.boardKey === 'bounties_completed')?.value).toBe(1)
    const launchSkills = launch.Skills.filter((skill) => skill['Release Phase'] === 'Launch')
    expect(launchSkills.length).toBe(13)
    for (const skill of launchSkills) {
      expect(keys).toContain(`skill:${skill['Skill ID']}`)
    }
    expect(boardLabel(launch, 'total_level')).toBe('Total Level')
    expect(boardLabel(launch, 'guild_total_level')).toBe('Guild Total Level')
  })
})
