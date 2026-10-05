import { describe, expect, it } from 'vitest'
import { isIncompleteCombatAwayLine } from './summary'

describe('isIncompleteCombatAwayLine', () => {
  it('hides mid-fight chatter and keeps finished fight lines', () => {
    expect(isIncompleteCombatAwayLine('You hit 12. Cow hits 8.')).toBe(true)
    expect(isIncompleteCombatAwayLine('You crit for 40. Seagull hits 3.')).toBe(true)
    expect(
      isIncompleteCombatAwayLine('Mother Squid releases squidlings! Defeat them to continue.'),
    ).toBe(true)
    expect(isIncompleteCombatAwayLine('Defeated Cow')).toBe(false)
    expect(isIncompleteCombatAwayLine('Critical hit! Defeated Cow')).toBe(false)
    expect(isIncompleteCombatAwayLine('Thorns reflects 5 and defeats Cow!')).toBe(false)
    expect(isIncompleteCombatAwayLine('Defeated by Cow. Recovering…')).toBe(false)
  })

  it('prefers structured message topics over regex', () => {
    expect(isIncompleteCombatAwayLine('anything', 'combat-swing')).toBe(true)
    expect(isIncompleteCombatAwayLine('anything', 'combat-phase')).toBe(true)
    expect(isIncompleteCombatAwayLine('You hit 12. Cow hits 8.', 'combat-outcome')).toBe(false)
    expect(isIncompleteCombatAwayLine('You hit 12. Cow hits 8.', 'general')).toBe(false)
  })
})
