import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { locationHasArena } from './arena'
import {
  applyRankedPvpResult,
  canStartRankedPvp,
  combatLevelOf,
  pickRankedOpponent,
  RANKED_PVP_DAILY_CAP,
  RANKED_PVP_WIN_GOLD,
  rankedFightsRemaining,
  rankedPvpDayKey,
  rankedPvpKd,
  searchArenaOpponents,
  type ArenaOpponent,
} from './matchmaking'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

const NOW = Date.parse('2026-08-13T18:00:00.000Z')

function opponents(): ArenaOpponent[] {
  return [
    { userId: 'usr_demo_bram', username: 'Bram', combatLevel: 6, totalLevel: 11 },
    { userId: 'usr_demo_mira', username: 'Mira', combatLevel: 8, totalLevel: 14 },
    { userId: 'usr_demo_kael', username: 'Kael', combatLevel: 18, totalLevel: 18 },
  ]
}

describe('arena matchmaking', () => {
  const { launch, launchIndexes } = prepareDatabase(rawDatabase)

  it('is at the Citadel plaza and combat grounds', () => {
    expect(locationHasArena(launchIndexes.locationsById.get('LOC-0028'))).toBe(true)
    expect(locationHasArena(launchIndexes.locationsById.get('LOC-0032'))).toBe(true)
    expect(locationHasArena(launchIndexes.locationsById.get('LOC-0029'))).toBe(false)
    expect(locationHasArena(undefined)).toBe(false)
  })

  it('searches by name and ignores empty queries', () => {
    expect(searchArenaOpponents(opponents(), '  ')).toEqual([])
    expect(searchArenaOpponents(opponents(), 'mi').map((row) => row.username)).toEqual(['Mira'])
    expect(searchArenaOpponents(opponents(), 'A').map((row) => row.username)).toEqual([
      'Bram',
      'Kael',
      'Mira',
    ])
  })

  it('picks ranked opponents by closest combat level', () => {
    expect(pickRankedOpponent(1, 13, opponents())?.username).toBe('Bram')
    expect(pickRankedOpponent(8, 13, opponents())?.username).toBe('Mira')
    expect(pickRankedOpponent(18, 18, opponents())?.username).toBe('Kael')
    expect(pickRankedOpponent(1, 13, [])).toBeNull()
  })

  it('caps ranked fights at 5 a UTC day and pays 1000 gold on a win', () => {
    let save = createNewSave(launch, NOW)
    expect(combatLevelOf(save)).toBe(1)
    expect(rankedPvpDayKey(NOW)).toBe('2026-08-13')
    expect(rankedFightsRemaining(save, NOW)).toBe(RANKED_PVP_DAILY_CAP)
    expect(canStartRankedPvp(save, NOW).ok).toBe(true)

    const goldBefore = save.gold
    save = applyRankedPvpResult(save, true, NOW)
    expect(save.gold).toBe(goldBefore + RANKED_PVP_WIN_GOLD)
    expect(save.rankedPvpWins).toBe(1)
    expect(save.rankedPvpLosses).toBe(0)
    expect(save.rankedPvpFightsToday).toBe(1)

    for (let i = 0; i < RANKED_PVP_DAILY_CAP - 1; i++) {
      save = applyRankedPvpResult(save, false, NOW)
    }
    expect(rankedFightsRemaining(save, NOW)).toBe(0)
    expect(canStartRankedPvp(save, NOW).ok).toBe(false)
    expect(save.rankedPvpLosses).toBe(4)
    expect(rankedPvpKd(save.rankedPvpWins, save.rankedPvpLosses)).toBe(1 / 4)

    const nextDay = applyRankedPvpResult(save, false, NOW + 24 * 60 * 60 * 1000)
    expect(nextDay.rankedPvpFightsToday).toBe(1)
    expect(nextDay.rankedPvpDayKey).toBe('2026-08-14')
  })
})
