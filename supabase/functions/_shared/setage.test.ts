import { describe, expect, it } from 'vitest'

import { staffBirthYearOk, STAFF_BIRTH_YEAR_ERROR } from './age.ts'
import { parseSetAgeTokens, SETAGE_MONTH_ERROR, SETAGE_USAGE, setAgeAuditRow } from './setage.ts'

describe('staff /setage', () => {
  const asOf = new Date('2026-10-17T00:00:00.000Z')

  it('rejects a future birth year', () => {
    expect(staffBirthYearOk(2027, asOf)).toBe(false)
    expect(staffBirthYearOk(2026, asOf)).toBe(true)
    expect(staffBirthYearOk(1899, asOf)).toBe(false)
    expect(parseSetAgeTokens(['Hero', '2027'], asOf)).toEqual({
      ok: false,
      reason: STAFF_BIRTH_YEAR_ERROR,
    })
    expect(parseSetAgeTokens(['Hero', '2012'], asOf)).toEqual({
      ok: true,
      username: 'Hero',
      year: 2012,
      month: null,
    })
    expect(parseSetAgeTokens(['Hero', '2013', '9'], asOf)).toEqual({
      ok: true,
      username: 'Hero',
      year: 2013,
      month: 9,
    })
    expect(parseSetAgeTokens(['Hero', '2013', '13'], asOf)).toEqual({
      ok: false,
      reason: SETAGE_MONTH_ERROR,
    })
  })

  it('audits usage failures before the RPC', () => {
    expect(parseSetAgeTokens(['Hero'], asOf)).toEqual({ ok: false, reason: SETAGE_USAGE })
    expect(setAgeAuditRow('staff-1', ['Hero'], SETAGE_USAGE)).toEqual({
      user_id: 'staff-1',
      command: 'setage',
      args: { tokens: ['Hero'] },
      ok: false,
      reason: SETAGE_USAGE,
    })
  })
})
