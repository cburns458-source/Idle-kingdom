// ECO-01: new Bazaar offers require total level 200.
//
// Matches `totalLevel` in `src/game/skills/totals.ts` and
// `packages/ik_rules/lib/src/skills/totals.dart`: the sum of every skill
// level on the save. The Dart copy of these constants lives in
// `packages/ik_net/lib/src/market.dart`.

/** New BUY and SELL offers require this many total levels. */
export const BAZAAR_TOTAL_LEVEL_REQUIRED = 200

/** Server refusal code when the owner is below [BAZAAR_TOTAL_LEVEL_REQUIRED]. */
export const BAZAAR_TOTAL_LEVEL_TOO_LOW_CODE = 'total_level_too_low'

/** Exact copy the Bazaar screen shows for [BAZAAR_TOTAL_LEVEL_TOO_LOW_CODE]. */
export const BAZAAR_TOTAL_LEVEL_TOO_LOW = `You need total level ${BAZAAR_TOTAL_LEVEL_REQUIRED} to use the bazaar.`

/**
 * Sum of skill levels on a stored save payload.
 *
 * Missing or unreadable skills count as 0, so a save that has never listed
 * them cannot place an offer.
 */
export function totalLevelFromPayload(payload: Record<string, unknown>): number {
  const skills = payload.skills
  if (!Array.isArray(skills)) return 0
  let sum = 0
  for (const entry of skills) {
    if (!entry || typeof entry !== 'object') continue
    const level = Number((entry as { level?: unknown }).level)
    if (Number.isFinite(level)) sum += Math.floor(level)
  }
  return sum
}

export type BazaarTotalLevelAllowed = { ok: true; totalLevel: number }

export type BazaarTotalLevelRefused = {
  ok: false
  code: typeof BAZAAR_TOTAL_LEVEL_TOO_LOW_CODE
  required: typeof BAZAAR_TOTAL_LEVEL_REQUIRED
  totalLevel: number
  error: typeof BAZAAR_TOTAL_LEVEL_TOO_LOW
}

export type BazaarTotalLevelGate = BazaarTotalLevelAllowed | BazaarTotalLevelRefused

/** Whether [payload] may place a new Bazaar offer. */
export function bazaarTotalLevelGate(payload: Record<string, unknown>): BazaarTotalLevelGate {
  const totalLevel = totalLevelFromPayload(payload)
  if (totalLevel >= BAZAAR_TOTAL_LEVEL_REQUIRED) return { ok: true, totalLevel }
  return {
    ok: false,
    code: BAZAAR_TOTAL_LEVEL_TOO_LOW_CODE,
    required: BAZAAR_TOTAL_LEVEL_REQUIRED,
    totalLevel,
    error: BAZAAR_TOTAL_LEVEL_TOO_LOW,
  }
}

/** Fields a `200 { ok: false }` Bazaar refusal carries for this gate. */
export function bazaarTotalLevelRefusalFields(
  gate: BazaarTotalLevelRefused,
): { code: string; required: number; totalLevel: number } {
  return { code: gate.code, required: gate.required, totalLevel: gate.totalLevel }
}
