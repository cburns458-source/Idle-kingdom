import { getSkillProgress } from '../activity/xp'
import { COMBAT_SKILL_ID } from '../combat/stats'
import type { PlayerSave } from '../save/types'
import { totalLevel } from '../skills/totals'

export const RANKED_PVP_DAILY_CAP = 5
export const RANKED_PVP_WIN_GOLD = 1000

/** A stored player the arena can search or match against. */
export interface ArenaOpponent {
  userId: string
  username: string
  combatLevel: number
  totalLevel: number
}

export function combatLevelOf(save: Pick<PlayerSave, 'skills'>): number {
  return getSkillProgress(save as PlayerSave, COMBAT_SKILL_ID).level
}

/** UTC calendar day, matching `toISOString().slice(0, 10)`. */
export function rankedPvpDayKey(nowMs: number): string {
  return new Date(nowMs).toISOString().slice(0, 10)
}

export function rankedPvpKd(wins: number, losses: number): number {
  const w = Math.max(0, Number(wins) || 0)
  const l = Math.max(0, Number(losses) || 0)
  if (w <= 0 && l <= 0) return 0
  return w / Math.max(l, 1)
}

export function rankedFightsUsedToday(save: PlayerSave, nowMs: number): number {
  const key = rankedPvpDayKey(nowMs)
  if (save.rankedPvpDayKey !== key) return 0
  return Math.max(0, Math.floor(Number(save.rankedPvpFightsToday) || 0))
}

export function rankedFightsRemaining(save: PlayerSave, nowMs: number): number {
  return Math.max(0, RANKED_PVP_DAILY_CAP - rankedFightsUsedToday(save, nowMs))
}

/**
 * Search is by name: a case-insensitive substring of the stored username.
 * An empty query matches nobody, so the list is never "every player".
 */
export function searchArenaOpponents(candidates: ArenaOpponent[], query: string): ArenaOpponent[] {
  const needle = query.trim().toLowerCase()
  if (!needle) return []
  return candidates
    .filter((row) => row.username.toLowerCase().includes(needle))
    .slice()
    .sort((a, b) => a.username.localeCompare(b.username) || a.userId.localeCompare(b.userId))
}

/**
 * Ranked picks the closest combat level on the game, then closer total level,
 * then a stable user id. Self is already excluded by the caller.
 */
export function pickRankedOpponent(
  selfCombatLevel: number,
  selfTotalLevel: number,
  candidates: ArenaOpponent[],
): ArenaOpponent | null {
  if (candidates.length === 0) return null
  return candidates.slice().sort((a, b) => {
    const combatA = Math.abs(a.combatLevel - selfCombatLevel)
    const combatB = Math.abs(b.combatLevel - selfCombatLevel)
    if (combatA !== combatB) return combatA - combatB
    const totalA = Math.abs(a.totalLevel - selfTotalLevel)
    const totalB = Math.abs(b.totalLevel - selfTotalLevel)
    if (totalA !== totalB) return totalA - totalB
    return a.userId.localeCompare(b.userId)
  })[0]!
}

export type RankedPvpStartResult =
  | { ok: true }
  | { ok: false; reason: string }

export function canStartRankedPvp(save: PlayerSave, nowMs: number): RankedPvpStartResult {
  if (rankedFightsRemaining(save, nowMs) <= 0) {
    return { ok: false, reason: 'Ranked is capped at 5 fights a day.' }
  }
  return { ok: true }
}

/** Records a ranked fight: the daily cap, K/D, and 1,000 gold on a win. Search fights skip this. */
export function applyRankedPvpResult(save: PlayerSave, won: boolean, nowMs: number): PlayerSave {
  const key = rankedPvpDayKey(nowMs)
  const used = rankedFightsUsedToday(save, nowMs)
  const gold = won ? RANKED_PVP_WIN_GOLD : 0
  return {
    ...save,
    rankedPvpDayKey: key,
    rankedPvpFightsToday: used + 1,
    rankedPvpWins: Math.max(0, Math.floor(Number(save.rankedPvpWins) || 0)) + (won ? 1 : 0),
    rankedPvpLosses: Math.max(0, Math.floor(Number(save.rankedPvpLosses) || 0)) + (won ? 0 : 1),
    gold: save.gold + gold,
  }
}

export function arenaOpponentFromSave(
  userId: string,
  username: string,
  save: PlayerSave,
): ArenaOpponent {
  return {
    userId,
    username,
    combatLevel: combatLevelOf(save),
    totalLevel: totalLevel(save),
  }
}
