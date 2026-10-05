export type AwayMessageTopic = 'combat-swing' | 'combat-phase' | 'combat-outcome' | 'general'

/**
 * Away-summary lines that are mid-fight chatter, not a finished action.
 *
 * Prefer structured `topic` from session message events. Regex is only a
 * fallback for older untagged lines.
 *
 * Catch-up still simulates every swing; the panel only reports gathers, crafts,
 * and fights that actually ended.
 */
export function isIncompleteCombatAwayLine(
  text: string,
  topic?: AwayMessageTopic | string | null,
): boolean {
  if (topic === 'combat-swing' || topic === 'combat-phase') return true
  if (topic === 'combat-outcome' || topic === 'general') return false
  if (/^You (hit |crit for )/.test(text)) return true
  if (/releases squidlings!/.test(text)) return true
  return false
}
