import { describe, expect, it } from 'vitest'
import {
  healTowardCeiling,
  overhealCeilingHp,
  parseOverhealRatio,
  snapToOverhealCeiling,
} from './overheal'

describe('overheal ceilings', () => {
  it('adds floor(max × ratio) above max', () => {
    expect(overhealCeilingHp(1000, 0.05)).toBe(1050)
    expect(overhealCeilingHp(1000, 0.1)).toBe(1100)
    expect(overhealCeilingHp(1000, 0)).toBe(1000)
    expect(snapToOverhealCeiling(420, 0.1)).toBe(462)
  })

  it('heals toward a source ceiling and never cuts higher surplus', () => {
    expect(healTowardCeiling(900, 1000, 320, 0.05)).toBe(1050)
    expect(healTowardCeiling(1000, 1000, 320, 0.05)).toBe(1050)
    expect(healTowardCeiling(1100, 1000, 320, 0.05)).toBe(1100)
    expect(healTowardCeiling(1000, 1000, 40, 0)).toBe(1000)
    expect(healTowardCeiling(900, 1000, 40, 0)).toBe(940)
  })

  it('reads the highest overheal_percent tag', () => {
    expect(parseOverhealRatio('food_slot; consumed_after_victory')).toBe(0)
    expect(parseOverhealRatio('food_slot; overheal_percent:5; consumed_after_victory')).toBe(0.05)
    expect(parseOverhealRatio('overheal_percent:5; overheal_percent:10')).toBe(0.1)
  })
})
