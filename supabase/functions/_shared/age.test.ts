import { describe, expect, it } from 'vitest'

import {
  AGE_GATE_CODE,
  AGE_GATE_ERROR,
  accountAgeYears,
  ageBandFromYears,
  ageGateResponse,
  chatAllowedFromAge,
  needsBirthMonth,
  storeBandAllowsChat,
} from './age.ts'

describe('chat age gate', () => {
  const asOf = new Date('2026-10-17T00:00:00.000Z')

  it('turns chat on at 13 and keeps it off until then', () => {
    expect(accountAgeYears(2013, 10, asOf)).toBe(13)
    expect(accountAgeYears(2013, 11, asOf)).toBe(12)
    expect(chatAllowedFromAge({ answered: true, birthYear: 2013, birthMonth: 10, asOf })).toBe(true)
    expect(chatAllowedFromAge({ answered: true, birthYear: 2013, birthMonth: 11, asOf })).toBe(false)
  })

  it('treats a year-only answer as 31 Dec so players cannot age up early', () => {
    expect(accountAgeYears(2013, null, asOf)).toBe(12)
    expect(chatAllowedFromAge({ answered: true, birthYear: 2013, asOf })).toBe(false)
  })

  it('rolls a birthday over without a new answer', () => {
    const before = new Date('2026-09-30T00:00:00.000Z')
    const after = new Date('2026-10-01T00:00:00.000Z')
    expect(chatAllowedFromAge({ answered: true, birthYear: 2013, birthMonth: 10, asOf: before })).toBe(false)
    expect(chatAllowedFromAge({ answered: true, birthYear: 2013, birthMonth: 10, asOf: after })).toBe(true)
  })

  it('keeps chat off until the account answers', () => {
    expect(chatAllowedFromAge({ answered: false, birthYear: 2000, birthMonth: 1, asOf })).toBe(false)
    expect(ageGateResponse(false)).toEqual({ status: 403, error: AGE_GATE_ERROR, code: AGE_GATE_CODE })
    expect(ageGateResponse(true)).toBeNull()
  })

  it('maps store bands and requires a month near the threshold', () => {
    expect(storeBandAllowsChat('0-12')).toBe(false)
    expect(storeBandAllowsChat('13-15')).toBe(true)
    expect(ageBandFromYears(12)).toBe('0-12')
    expect(ageBandFromYears(13)).toBe('13-15')
    expect(needsBirthMonth(2013, asOf)).toBe(true)
    expect(needsBirthMonth(2000, asOf)).toBe(false)
  })
})
