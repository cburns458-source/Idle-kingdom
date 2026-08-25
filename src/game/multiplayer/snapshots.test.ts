import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { WEAPON_TOOL_SLOT_ID, equipStackToSlot } from '../equipment/loadout'
import { COMBAT_SKILL_ID } from '../combat/stats'
import { totalLevel, totalSkillXp } from '../skills/totals'
import {
  buildLeaderboardSnapshot,
  boardLabel,
  publicProfileStatsFromLeaderboardRows,
  rankLeaderboardEntries,
} from './snapshots'
import { DEFAULT_PLAYER_APPEARANCE, type LeaderboardEntry } from './types'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
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
    expect(keys).toContain('total_level_combat_1')
    // Total XP rides along on the total level board instead of holding its own.
    expect(keys).not.toContain('total_experience')
    expect(keys).toContain('gold_earned')
    expect(keys).toContain('monsters_killed')
    expect(keys).toContain('critters_collected')
    expect(keys).toContain('bounties_completed')
    expect(keys).toContain('pvp_kd')
    expect(keys).toContain('log_completion')
    expect(snapshot.boards.find((board) => board.boardKey === 'pvp_kd')?.value).toBe(0)
    expect(typeof snapshot.boards.find((board) => board.boardKey === 'log_completion')?.value).toBe(
      'number',
    )
    expect(snapshot.boards.find((board) => board.boardKey === 'critters_collected')?.value).toBe(2)
    expect(snapshot.boards.find((board) => board.boardKey === 'bounties_completed')?.value).toBe(1)
    const launchSkills = launch.Skills.filter((skill) => skill['Release Phase'] === 'Launch')
    expect(launchSkills.length).toBe(13)
    for (const skill of launchSkills) {
      expect(keys).toContain(`skill:${skill['Skill ID']}`)
    }
    expect(boardLabel(launch, 'total_level')).toBe('Total Level & XP')
    expect(boardLabel(launch, 'total_level_combat_1')).toBe('Pacifist Total Level')
    expect(boardLabel(launch, 'guild_total_level')).toBe('Guild Total Level')
    expect(boardLabel(launch, 'log_completion')).toBe('Log Completion')
  })

  it('carries total XP alongside the total level', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    const snapshot = buildLeaderboardSnapshot(launch, save)

    const total = snapshot.boards.find((board) => board.boardKey === 'total_level')
    expect(total?.value).toBe(totalLevel(save))
    expect(total?.secondaryValue).toBe(totalSkillXp(save))
  })

  it('stands a fresh character on the pacifist board and a fighter off it', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)

    const pacifist = buildLeaderboardSnapshot(launch, save).boards.find(
      (board) => board.boardKey === 'total_level_combat_1',
    )
    expect(pacifist?.value).toBe(totalLevel(save))
    expect(pacifist?.secondaryValue).toBe(totalSkillXp(save))

    const fighter = {
      ...save,
      skills: save.skills.map((skill) =>
        skill.skillId === COMBAT_SKILL_ID ? { ...skill, level: 2 } : skill,
      ),
    }
    const off = buildLeaderboardSnapshot(launch, fighter).boards.find(
      (board) => board.boardKey === 'total_level_combat_1',
    )
    // A zero reads as "not on this board" rather than a score of nothing.
    expect(off?.value).toBe(0)
    expect(off?.secondaryValue).toBe(0)
  })

  it('splits a tie on total level by experience', () => {
    const entries: LeaderboardEntry[] = [
      {
        userId: 'usr-1',
        username: 'Ada',
        appearance: DEFAULT_PLAYER_APPEARANCE,
        guildName: null,
        boardKey: 'total_level',
        value: 20,
        secondaryValue: 400,
        rank: 0,
      },
      {
        userId: 'usr-2',
        username: 'Bea',
        appearance: DEFAULT_PLAYER_APPEARANCE,
        guildName: null,
        boardKey: 'total_level',
        value: 20,
        secondaryValue: 900,
        rank: 0,
      },
    ]

    expect(rankLeaderboardEntries(entries).map((entry) => entry.username)).toEqual(['Bea', 'Ada'])
  })

  it('rebuilds public profile skills from the same snapshot rows', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = {
      ...createNewSave(launch),
      skills: createNewSave(launch).skills.map((skill) =>
        skill.skillId === COMBAT_SKILL_ID ? { ...skill, level: 18, xp: 4000 } : skill,
      ),
    }
    const snapshot = buildLeaderboardSnapshot(launch, save)
    const rows = snapshot.boards.map((board) => ({
      board_key: board.boardKey,
      value: board.value,
      value_secondary: board.secondaryValue,
    }))
    const stats = publicProfileStatsFromLeaderboardRows(rows, launch)
    expect(stats.totalLevel).toBe(totalLevel(save))
    expect(stats.totalXp).toBe(totalSkillXp(save))
    expect(stats.skills.find((skill) => skill.skillId === COMBAT_SKILL_ID)?.level).toBe(18)
    expect(stats.skills.find((skill) => skill.skillId === COMBAT_SKILL_ID)?.xp).toBe(4000)
    expect(snapshot.boards.find((board) => board.boardKey === `skill:${COMBAT_SKILL_ID}`)?.secondaryValue).toBe(
      4000,
    )
    expect(stats.skills).toHaveLength(launch.Skills.filter((row) => row['Release Phase'] === 'Launch').length)
  })

  it('publishes equipped slots with the snapshot', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = equipStackToSlot(createNewSave(launch), WEAPON_TOOL_SLOT_ID, 'ITEM-0110', 1)
    const snapshot = buildLeaderboardSnapshot(launch, save)
    expect(snapshot.equipment).toEqual([
      { slotId: WEAPON_TOOL_SLOT_ID, itemId: 'ITEM-0110', quantity: 1, enchantmentId: null },
    ])
    expect(buildLeaderboardSnapshot(launch, createNewSave(launch)).equipment).toEqual([])
  })
})
