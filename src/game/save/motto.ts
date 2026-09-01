import { MOTTO_MAX_LENGTH } from './types'

/** Trim, collapse whitespace, and cap length. Empty becomes null. */
export function normalizeMotto(raw: string): string | null {
  const trimmed = raw.trim().replace(/\s+/g, ' ')
  if (!trimmed) return null
  return trimmed.slice(0, MOTTO_MAX_LENGTH)
}

export function isValidMotto(raw: string): boolean {
  // Empty is allowed (clears the motto); only reject when over the cap after trim.
  const trimmed = raw.trim().replace(/\s+/g, ' ')
  return trimmed.length <= MOTTO_MAX_LENGTH
}
