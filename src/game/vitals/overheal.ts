/**
 * Extra HP above max from one overheal source.
 * Ratio is a fraction of max (0.05 = 5%). Sources do not add together;
 * whichever ceiling is higher at apply time wins, and a lower source never
 * cuts surplus that is already above its own ceiling.
 */
export function overhealCeilingHp(maxHp: number, overhealRatio: number): number {
  const max = Math.max(0, Number(maxHp) || 0)
  const ratio = Math.max(0, Number(overhealRatio) || 0)
  return max + Math.floor(max * ratio)
}

/** Snap to a source's ceiling (blessing). */
export function snapToOverhealCeiling(maxHp: number, overhealRatio: number): number {
  return overhealCeilingHp(maxHp, overhealRatio)
}

/**
 * Apply a heal (or damage) against one source's ceiling.
 * Existing surplus above that ceiling is left alone.
 */
export function healTowardCeiling(
  currentHp: number,
  maxHp: number,
  amount: number,
  overhealRatio: number,
): number {
  const current = Number(currentHp) || 0
  if (amount < 0) return Math.max(1, current + amount)
  const ceiling = overhealCeilingHp(maxHp, overhealRatio)
  if (current >= ceiling) return current
  return Math.min(ceiling, current + amount)
}

/** Largest `overheal_percent:N` tag on a capability string, as a ratio. */
export function parseOverhealRatio(effects: string | null | undefined): number {
  if (typeof effects !== 'string') return 0
  let best = 0
  for (const part of effects.split(';')) {
    const match = part.trim().toLowerCase().match(/^overheal_percent:(\d+(?:\.\d+)?)$/)
    if (match) best = Math.max(best, Number(match[1]) / 100)
  }
  return best
}
