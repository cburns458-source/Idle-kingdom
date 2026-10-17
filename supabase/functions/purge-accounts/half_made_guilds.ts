export type HalfMadeGuildProbe = {
  id: string
  createdAt: Date
  memberCount: number
  hadLeaderRow: boolean
  hasHall: boolean
  hasAchievements: boolean
}

const HOUR_MS = 60 * 60 * 1000

/** Same keep/purge rules as public.account_purge_half_made_guilds(). */
export function shouldPurgeHalfMadeGuild(row: HalfMadeGuildProbe, now: Date): boolean {
  return (
    now.getTime() - row.createdAt.getTime() > HOUR_MS &&
    row.memberCount === 0 &&
    !row.hadLeaderRow &&
    !row.hasHall &&
    !row.hasAchievements
  )
}
