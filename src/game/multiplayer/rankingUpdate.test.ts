import { describe, expect, it } from 'vitest'
import {
  canUpdateRanking,
  msUntilNextUtcHour,
  parseRankingSubmitAt,
  rankingCooldownMessage,
  rankingCooldownRemainingMs,
  RANKING_PUBLISH_DEBOUNCE_MS,
  RANKING_UPDATE_COOLDOWN_MS,
  RANKING_UPDATE_READY_HINT,
  rankingUpdateHint,
  rankingUpdateStorageKey,
  shouldAutoSubmitRanking,
  shouldPublishForUtcHour,
  shouldPublishOnOpen,
  utcDayKey,
  utcHourKey,
} from './rankingUpdate'

const noon = 1_786_568_400_000
const startOfDay = Date.UTC(
  new Date(noon).getUTCFullYear(),
  new Date(noon).getUTCMonth(),
  new Date(noon).getUTCDate(),
)
const nextDay = startOfDay + 24 * 60 * 60 * 1000

describe('ranking update policy', () => {
  it('names the storage key after the account', () => {
    expect(rankingUpdateStorageKey('usr_0001')).toBe('idle-kingdoms.leaderboard.submit-at:usr_0001')
  })

  it('auto-submits when nothing has been posted, or the UTC day rolled over', () => {
    expect(shouldAutoSubmitRanking(null, startOfDay)).toBe(true)
    expect(shouldAutoSubmitRanking(startOfDay, startOfDay + 60 * 60 * 1000)).toBe(false)
    expect(shouldAutoSubmitRanking(startOfDay, nextDay)).toBe(true)
    expect(utcDayKey(startOfDay)).toBe(utcDayKey(startOfDay + 12 * 60 * 60 * 1000))
    expect(utcDayKey(startOfDay)).not.toBe(utcDayKey(nextDay))
  })

  it('waits an hour between manual updates', () => {
    expect(canUpdateRanking(null, startOfDay)).toBe(true)
    expect(canUpdateRanking(startOfDay, startOfDay + RANKING_UPDATE_COOLDOWN_MS - 1)).toBe(false)
    expect(canUpdateRanking(startOfDay, startOfDay + RANKING_UPDATE_COOLDOWN_MS)).toBe(true)
    expect(rankingCooldownRemainingMs(startOfDay, startOfDay + 15 * 60 * 1000)).toBe(45 * 60 * 1000)
    expect(rankingCooldownMessage(45 * 60 * 1000)).toBe('You can update your ranking again in 45 minutes.')
    expect(rankingCooldownMessage(60 * 1000)).toBe('You can update your ranking again in 1 minute.')
    expect(rankingCooldownMessage(RANKING_UPDATE_COOLDOWN_MS)).toBe(
      'You can update your ranking again in 1 hour.',
    )
    expect(rankingUpdateHint(startOfDay, startOfDay)).toBe('You can update your ranking again in 1 hour.')
    expect(rankingUpdateHint(null, startOfDay)).toBe(RANKING_UPDATE_READY_HINT)
  })

  it('uses UTC hour marks and a short debounce for opening the app', () => {
    expect(utcHourKey(startOfDay).endsWith('T00')).toBe(true)
    expect(utcHourKey(startOfDay + 15 * 60 * 1000)).toBe(utcHourKey(startOfDay))
    expect(msUntilNextUtcHour(startOfDay)).toBe(60 * 60 * 1000)
    expect(msUntilNextUtcHour(startOfDay + 15 * 60 * 1000)).toBe(45 * 60 * 1000)
    expect(shouldPublishForUtcHour(null, startOfDay)).toBe(true)
    expect(shouldPublishForUtcHour(startOfDay, startOfDay + 59 * 60 * 1000)).toBe(false)
    expect(shouldPublishForUtcHour(startOfDay, startOfDay + 60 * 60 * 1000)).toBe(true)
    expect(shouldPublishOnOpen(null, startOfDay)).toBe(true)
    expect(shouldPublishOnOpen(startOfDay, startOfDay + 1000)).toBe(false)
    expect(shouldPublishOnOpen(startOfDay, startOfDay + RANKING_PUBLISH_DEBOUNCE_MS)).toBe(true)
  })

  it('parses a stored timestamp', () => {
    expect(parseRankingSubmitAt(null)).toBeNull()
    expect(parseRankingSubmitAt('')).toBeNull()
    expect(parseRankingSubmitAt('1786568400000')).toBe(1786568400000)
  })
})
