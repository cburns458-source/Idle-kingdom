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
  rankedWinsRemaining,
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

  it('is at the Citadel plaza only', () => {
    expect(locationHasArena(launchIndexes.locationsById.get('LOC-0028'))).toBe(true)
    expect(locationHasArena(launchIndexes.locationsById.get('LOC-0032'))).toBe(false)
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

  it('caps ranked wins at 5 a UTC day and pays 1000 gold only under the cap', () => {
    let save = createNewSave(launch, NOW)
    expect(combatLevelOf(save)).toBe(2)
    expect(rankedPvpDayKey(NOW)).toBe('2026-08-13')
    expect(rankedWinsRemaining(save, NOW)).toBe(RANKED_PVP_DAILY_CAP)
    expect(canStartRankedPvp(save, NOW).ok).toBe(true)

    const goldBefore = save.gold
    const first = applyRankedPvpResult(save, true, NOW)
    save = first.save
    expect(first.paid).toBe(true)
    expect(save.gold).toBe(goldBefore + RANKED_PVP_WIN_GOLD)
    expect(save.rankedPvpWins).toBe(1)
    expect(save.rankedPvpLosses).toBe(0)
    expect(save.rankedPvpFightsToday).toBe(1)

    const loss = applyRankedPvpResult(save, false, NOW)
    save = loss.save
    expect(loss.paid).toBe(false)
    expect(save.gold).toBe(goldBefore + RANKED_PVP_WIN_GOLD)
    expect(rankedWinsRemaining(save, NOW)).toBe(RANKED_PVP_DAILY_CAP - 1)
    expect(canStartRankedPvp(save, NOW).ok).toBe(true)

    for (let i = 0; i < RANKED_PVP_DAILY_CAP - 1; i++) {
      save = applyRankedPvpResult(save, true, NOW).save
    }
    expect(rankedWinsRemaining(save, NOW)).toBe(0)
    expect(canStartRankedPvp(save, NOW).ok).toBe(true)

    const sixth = applyRankedPvpResult(save, true, NOW)
    expect(sixth.paid).toBe(false)
    expect(sixth.code).toBe('daily_cap_reached')
    expect(sixth.save.gold).toBe(save.gold)
    expect(sixth.save.rankedPvpWins).toBe(save.rankedPvpWins + 1)
    expect(rankedPvpKd(sixth.save.rankedPvpWins, sixth.save.rankedPvpLosses)).toBe(6 / 1)

    const nextDay = applyRankedPvpResult(sixth.save, true, NOW + 24 * 60 * 60 * 1000)
    expect(nextDay.paid).toBe(true)
    expect(nextDay.save.rankedPvpFightsToday).toBe(1)
    expect(nextDay.save.rankedPvpDayKey).toBe('2026-08-14')
  })
})
