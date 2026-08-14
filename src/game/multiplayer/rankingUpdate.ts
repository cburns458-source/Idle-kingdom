/** How long a player must wait between manual ranking updates. */
export const RANKING_UPDATE_COOLDOWN_MS = 60 * 60 * 1000

export const RANKING_UPDATE_READY_HINT = 'Publishes your current totals to the boards.'

export const RANKING_UPDATED_NOTICE = 'Ranking updated.'

/** The local-storage key that remembers when this account last submitted. */
export function rankingUpdateStorageKey(userId: string): string {
  return `idle-kingdoms.leaderboard.submit-at:${userId}`
}

/** UTC calendar day `YYYY-MM-DD` for [nowMs]. */
export function utcDayKey(nowMs: number): string {
  return new Date(nowMs).toISOString().slice(0, 10)
}

export function parseRankingSubmitAt(raw: string | null | undefined): number | null {
  if (!raw) return null
  const value = Number(raw)
  return Number.isFinite(value) ? value : null
}

/** True when this device has not submitted on today's UTC day. */
export function shouldAutoSubmitRanking(lastSubmitMs: number | null | undefined, nowMs: number): boolean {
  if (lastSubmitMs == null) return true
  return utcDayKey(lastSubmitMs) !== utcDayKey(nowMs)
}

/** True when a manual update is allowed (never submitted, or the hour is up). */
export function canUpdateRanking(lastSubmitMs: number | null | undefined, nowMs: number): boolean {
  if (lastSubmitMs == null) return true
  return nowMs - lastSubmitMs >= RANKING_UPDATE_COOLDOWN_MS
}

export function rankingCooldownRemainingMs(lastSubmitMs: number, nowMs: number): number {
  return Math.max(0, RANKING_UPDATE_COOLDOWN_MS - (nowMs - lastSubmitMs))
}

export function rankingCooldownMessage(remainingMs: number): string {
  const minutes = Math.ceil(remainingMs / 60_000)
  if (minutes <= 1) return 'You can update your ranking again in 1 minute.'
  if (minutes >= 60) return 'You can update your ranking again in 1 hour.'
  return `You can update your ranking again in ${minutes} minutes.`
}

export function rankingUpdateHint(lastSubmitMs: number | null | undefined, nowMs: number): string {
  if (lastSubmitMs != null && !canUpdateRanking(lastSubmitMs, nowMs)) {
    return rankingCooldownMessage(rankingCooldownRemainingMs(lastSubmitMs, nowMs))
  }
  return RANKING_UPDATE_READY_HINT
}
