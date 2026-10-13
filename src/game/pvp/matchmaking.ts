import { combatLevelOf } from '../combat/stats'
import { payReward } from '../economy/payout'
import type { PlayerSave } from '../save/types'
import { totalLevel } from '../skills/totals'

export { combatLevelOf }

export const RANKED_PVP_DAILY_CAP = 5
export const RANKED_PVP_WIN_GOLD = 1000
export const RANKED_PVP_DAILY_CAP_CODE = 'daily_cap_reached'
export const RANKED_PVP_DAILY_CAP_MESSAGE =
  "You've won 5 ranked fights today. Fights still count, but rewards return tomorrow."
export const RANKED_PVP_FAKED_WIN_REFUSAL = 'The server resolves ranked fights.'
export const RANKED_PVP_UNKNOWN_FIGHT_REFUSAL = 'Unknown ranked fight.'

/** A stored player the arena can search or match against. */
export interface ArenaOpponent {
  userId: string
  username: string
  combatLevel: number
  totalLevel: number
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

/** Ranked wins already counted toward today's cap. */
export function rankedWinsUsedToday(save: PlayerSave, nowMs: number): number {
  const key = rankedPvpDayKey(nowMs)
  if (save.rankedPvpDayKey !== key) return 0
  return Math.max(0, Math.floor(Number(save.rankedPvpFightsToday) || 0))
}

export function rankedWinsRemaining(save: PlayerSave, nowMs: number): number {
  return Math.max(0, RANKED_PVP_DAILY_CAP - rankedWinsUsedToday(save, nowMs))
}

/** @deprecated Use [rankedWinsUsedToday]. The daily cap is wins, not fights. */
export const rankedFightsUsedToday = rankedWinsUsedToday

/** Paid ranked wins still available today. Fights after the cap still resolve. */
export const rankedFightsRemaining = rankedWinsRemaining

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

/** Ranked fights always start. The daily cap stops the purse, not the match. */
export function canStartRankedPvp(_save: PlayerSave, _nowMs: number): RankedPvpStartResult {
  return { ok: true }
}

export type RankedPvpApplyResult = {
  save: PlayerSave
  won: boolean
  paid: boolean
  goldGained: number
  code?: typeof RANKED_PVP_DAILY_CAP_CODE
  winsToday: number
  winsRemaining: number
}

/**
 * Records a ranked fight: K/D always, and 1,000 gold on a win under the daily
 * cap of 5 wins. Search fights skip this. The sixth win still counts but pays
 * nothing.
 */
export function applyRankedPvpResult(save: PlayerSave, won: boolean, nowMs: number): RankedPvpApplyResult {
  const key = rankedPvpDayKey(nowMs)
  const winsToday = rankedWinsUsedToday(save, nowMs)
  const paid = won && winsToday < RANKED_PVP_DAILY_CAP
  const payout = payReward(save, { type: 'gold', amount: paid ? RANKED_PVP_WIN_GOLD : 0 })
  const nextWinsToday = won ? winsToday + 1 : winsToday
  return {
    save: {
      ...payout.save,
      rankedPvpDayKey: key,
      rankedPvpFightsToday: nextWinsToday,
      rankedPvpWins: Math.max(0, Math.floor(Number(save.rankedPvpWins) || 0)) + (won ? 1 : 0),
      rankedPvpLosses: Math.max(0, Math.floor(Number(save.rankedPvpLosses) || 0)) + (won ? 0 : 1),
    },
    won,
    paid,
    goldGained: payout.paid,
    code: won && !paid ? RANKED_PVP_DAILY_CAP_CODE : undefined,
    winsToday: nextWinsToday,
    winsRemaining: Math.max(0, RANKED_PVP_DAILY_CAP - nextWinsToday),
  }
}

export function mintRankedFightId(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID()
  }
  return `fight_${Math.random().toString(36).slice(2)}${Date.now().toString(36)}`
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
