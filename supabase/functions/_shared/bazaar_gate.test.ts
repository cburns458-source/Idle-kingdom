import { describe, expect, it } from 'vitest'

import {
  BAZAAR_TOTAL_LEVEL_REQUIRED,
  BAZAAR_TOTAL_LEVEL_TOO_LOW,
  BAZAAR_TOTAL_LEVEL_TOO_LOW_CODE,
  bazaarTotalLevelGate,
  bazaarTotalLevelRefusalFields,
  totalLevelFromPayload,
} from './bazaar_gate.ts'

function payloadAt(totalLevel: number): Record<string, unknown> {
  return {
    skills: [{ skillId: 'SKL-0001', level: totalLevel, xp: 0 }],
  }
}

describe('ECO-01 bazaar total-level gate', () => {
  it('sums skill levels the way totalLevel does', () => {
    expect(totalLevelFromPayload({})).toBe(0)
    expect(totalLevelFromPayload({ skills: 'nope' })).toBe(0)
    expect(
      totalLevelFromPayload({
        skills: [
          { skillId: 'SKL-0001', level: 10, xp: 0 },
          { skillId: 'SKL-0002', level: 189, xp: 0 },
        ],
      }),
    ).toBe(199)
    expect(
      totalLevelFromPayload({
        skills: [
          { skillId: 'SKL-0001', level: 10, xp: 0 },
          { skillId: 'SKL-0002', level: 190, xp: 0 },
        ],
      }),
    ).toBe(200)
  })

  it('refuses BUY and SELL at 199 with the structured payload', () => {
    const gate = bazaarTotalLevelGate(payloadAt(199))
    expect(gate.ok).toBe(false)
    if (gate.ok) return
    expect(gate).toEqual({
      ok: false,
      code: BAZAAR_TOTAL_LEVEL_TOO_LOW_CODE,
      required: BAZAAR_TOTAL_LEVEL_REQUIRED,
      totalLevel: 199,
      error: BAZAAR_TOTAL_LEVEL_TOO_LOW,
    })
    expect(bazaarTotalLevelRefusalFields(gate)).toEqual({
      code: 'total_level_too_low',
      required: 200,
      totalLevel: 199,
    })
    expect(gate.error).toBe('You need total level 200 to use the bazaar.')
  })

  it('allows a new offer at exactly 200', () => {
    expect(bazaarTotalLevelGate(payloadAt(200))).toEqual({ ok: true, totalLevel: 200 })
  })

  it('allows a new offer above 200', () => {
    expect(bazaarTotalLevelGate(payloadAt(201))).toEqual({ ok: true, totalLevel: 201 })
  })
})
