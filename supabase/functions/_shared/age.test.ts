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

  it('turns chat on at 13 and keeps it off until the last day of the birth month', () => {
    expect(accountAgeYears(2013, 9, asOf)).toBe(13)
    expect(accountAgeYears(2013, 10, asOf)).toBe(12)
    expect(chatAllowedFromAge({ answered: true, birthYear: 2013, birthMonth: 9, asOf })).toBe(true)
    expect(chatAllowedFromAge({ answered: true, birthYear: 2013, birthMonth: 10, asOf })).toBe(false)
  })

  it('treats a year-only answer as 31 December', () => {
    expect(accountAgeYears(2013, null, asOf)).toBe(12)
    expect(chatAllowedFromAge({ answered: true, birthYear: 2013, asOf })).toBe(false)
    expect(accountAgeYears(2012, null, asOf)).toBe(13)
    expect(chatAllowedFromAge({ answered: true, birthYear: 2012, asOf })).toBe(true)
  })

  it('rolls a birthday over without a new answer', () => {
    const before = new Date('2026-10-30T00:00:00.000Z')
    const after = new Date('2026-10-31T00:00:00.000Z')
    expect(chatAllowedFromAge({ answered: true, birthYear: 2013, birthMonth: 10, asOf: before })).toBe(false)
    expect(chatAllowedFromAge({ answered: true, birthYear: 2013, birthMonth: 10, asOf: after })).toBe(true)
    expect(
      chatAllowedFromAge({ answered: true, birthYear: 2013, asOf: new Date('2026-12-30T00:00:00.000Z') }),
    ).toBe(false)
    expect(
      chatAllowedFromAge({ answered: true, birthYear: 2013, asOf: new Date('2026-12-31T00:00:00.000Z') }),
    ).toBe(true)
    expect(accountAgeYears(2012, 2, new Date('2025-02-27T00:00:00.000Z'))).toBe(12)
    expect(accountAgeYears(2012, 2, new Date('2025-02-28T00:00:00.000Z'))).toBe(13)
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
    expect(needsBirthMonth(2012, asOf)).toBe(false)
    expect(needsBirthMonth(2014, asOf)).toBe(false)
    expect(needsBirthMonth(2000, asOf)).toBe(false)
  })
})
