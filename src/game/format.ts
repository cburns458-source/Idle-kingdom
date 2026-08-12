const UNITS = ['', 'K', 'M', 'B', 'T', 'Qa', 'Qi']

/** Format a number of gold into a compact, human-friendly string. */
export function formatNumber(value: number): string {
  if (!Number.isFinite(value)) return '∞'
  if (value < 1000) {
    return Number.isInteger(value) ? value.toString() : value.toFixed(1)
  }
  let tier = 0
  let n = value
  while (n >= 1000 && tier < UNITS.length - 1) {
    n /= 1000
    tier += 1
  }
  return `${n.toFixed(2)}${UNITS[tier]}`
}
