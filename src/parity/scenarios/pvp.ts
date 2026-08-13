import { simulatePvpFight } from '../../game/combat/pvp'
import {
  applyRankedPvpResult,
  canStartRankedPvp,
  pickRankedOpponent,
  rankedFightsRemaining,
  rankedPvpKd,
  searchArenaOpponents,
  type ArenaOpponent,
} from '../../game/pvp/matchmaking'
import { locationHasArena } from '../../game/pvp/arena'
import { mulberry32 } from '../../game/rng/mulberry32'
import { createNewSave } from '../../game/save/saveStore'
import type { PlayerSave } from '../../game/save/types'
import { scenario, type JsonValue, type ParityScenario } from '../types'
import { contentDatabase } from './contentDatabase'

const NOW_MS = Date.parse('2026-08-13T18:00:00.000Z')

const CANDIDATES: ArenaOpponent[] = [
  { userId: 'usr_demo_bram', username: 'Bram', combatLevel: 6, totalLevel: 11 },
  { userId: 'usr_demo_mira', username: 'Mira', combatLevel: 8, totalLevel: 14 },
  { userId: 'usr_demo_kael', username: 'Kael', combatLevel: 18, totalLevel: 18 },
]

function withCombatLevel(save: PlayerSave, level: number): PlayerSave {
  return {
    ...save,
    skills: save.skills.map((skill) =>
      skill.skillId === 'SKL-0001' ? { ...skill, level } : skill,
    ),
  }
}

export const pvpScenarios: ParityScenario[] = [
  scenario('pvp/matchmaking', 'search-and-ranked', { candidates: CANDIDATES as unknown as JsonValue }, () => {
    return {
      empty: searchArenaOpponents(CANDIDATES, '  '),
      mira: searchArenaOpponents(CANDIDATES, 'mi'),
      a: searchArenaOpponents(CANDIDATES, 'A').map((row) => row.username),
      closestLow: pickRankedOpponent(1, 13, CANDIDATES),
      closestMira: pickRankedOpponent(8, 13, CANDIDATES),
      closestKael: pickRankedOpponent(18, 18, CANDIDATES),
      none: pickRankedOpponent(1, 13, []),
    } as unknown as JsonValue
  }),

  scenario('pvp/matchmaking', 'ranked-cap', { source: 'content', nowMs: NOW_MS }, () => {
    const db = contentDatabase()
    let save = createNewSave(db, NOW_MS)
    const remainingFresh = rankedFightsRemaining(save, NOW_MS)
    const startOk = canStartRankedPvp(save, NOW_MS)
    save = applyRankedPvpResult(save, true, NOW_MS)
    for (let i = 0; i < 4; i++) save = applyRankedPvpResult(save, false, NOW_MS)
    const blocked = canStartRankedPvp(save, NOW_MS)
    const nextDay = applyRankedPvpResult(save, false, NOW_MS + 24 * 60 * 60 * 1000)
    return {
      remainingFresh,
      startOk,
      afterFive: {
        fights: save.rankedPvpFightsToday,
        wins: save.rankedPvpWins,
        losses: save.rankedPvpLosses,
        remaining: rankedFightsRemaining(save, NOW_MS),
        kd: rankedPvpKd(save.rankedPvpWins, save.rankedPvpLosses),
      },
      blocked,
      nextDay: {
        dayKey: nextDay.rankedPvpDayKey,
        fights: nextDay.rankedPvpFightsToday,
      },
    } as unknown as JsonValue
  }),

  scenario('pvp/fight', 'snapshot', { source: 'content', seed: 20260813, nowMs: NOW_MS }, () => {
    const db = contentDatabase()
    const you = createNewSave(db, NOW_MS)
    const them = withCombatLevel(createNewSave(db, NOW_MS), 18)
    const fight = simulatePvpFight(db, you, them, mulberry32(20260813))
    return {
      outcome: fight.outcome,
      roundCount: fight.rounds.length,
      last: fight.rounds.at(-1) ?? null,
      youMaxHp: fight.youMaxHp,
      themMaxHp: fight.themMaxHp,
    } as unknown as JsonValue
  }),

  scenario('pvp/arena', 'locations', { source: 'content' }, () => {
    const db = contentDatabase()
    const byId = (id: string) => db.Locations.find((row) => row['Location ID'] === id)
    return {
      plaza: locationHasArena(byId('LOC-0028')),
      combat: locationHasArena(byId('LOC-0032')),
      market: locationHasArena(byId('LOC-0029')),
      missing: locationHasArena(undefined),
    } as unknown as JsonValue
  }),
]
