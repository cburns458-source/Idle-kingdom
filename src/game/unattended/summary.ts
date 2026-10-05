/**
 * Away-summary lines that are mid-fight chatter, not a finished action.
 *
 * Catch-up still simulates every swing; the panel only reports gathers, crafts,
 * and fights that actually ended.
 */
export function isIncompleteCombatAwayLine(text: string): boolean {
  if (/^You (hit |crit for )/.test(text)) return true
  if (/releases squidlings!/.test(text)) return true
  return false
}
