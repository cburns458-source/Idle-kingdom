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

/** Server refusal when Getting Started is still active. */
export const BAZAAR_TUTORIAL_LOCKED_CODE = 'tutorial_locked'
export const BAZAAR_TUTORIAL_LOCKED = 'Finish Getting Started before using the Bazaar.'

/** Server refusal code when a skill level is present but not numeric. */
export const BAZAAR_SKILL_LEVEL_INVALID_CODE = 'BAZAAR_SKILL_LEVEL_INVALID'

/**
 * Same numeric check as SQL `bazaar_payload_total_level`
 * (`^-?[0-9]+(\\.[0-9]+)?([eE][+-]?[0-9]+)?$`).
 */
const BAZAAR_SKILL_LEVEL_NUMERIC = /^-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?$/

/** Exact SQL `BAZAAR_SKILL_LEVEL_INVALID` exception text. */
export function bazaarSkillLevelInvalidError(raw: string): string {
  return `${BAZAAR_SKILL_LEVEL_INVALID_CODE} skill level must be numeric, got ${raw}`
}

/**
 * Sum of skill levels on a stored save payload.
 *
 * Missing skills, missing levels, and null levels count as 0. A present
 * non-numeric level raises `BAZAAR_SKILL_LEVEL_INVALID`, matching SQL.
 */
export function totalLevelFromPayload(payload: Record<string, unknown>): number {
  const skills = payload.skills
  if (!Array.isArray(skills)) return 0
  let sum = 0
  for (const entry of skills) {
    if (!entry || typeof entry !== 'object') continue
    if (!Object.prototype.hasOwnProperty.call(entry, 'level')) continue
    const raw = (entry as { level?: unknown }).level
    if (raw == null) continue
    const text = String(raw)
    if (!BAZAAR_SKILL_LEVEL_NUMERIC.test(text)) {
      throw new Error(bazaarSkillLevelInvalidError(text))
    }
    sum += Math.floor(Number(text))
  }
  return sum
}

export function bazaarTutorialLocked(payload: Record<string, unknown>): boolean {
  const quests = payload.quests
  if (!Array.isArray(quests)) return false
  return quests.some(
    (row) =>
      row &&
      typeof row === 'object' &&
      (row as { questId?: unknown }).questId === 'QST-0006' &&
      (row as { status?: unknown }).status === 'active',
  )
}

export type BazaarTotalLevelAllowed = { ok: true; totalLevel: number }

export type BazaarTotalLevelRefused = {
  ok: false
  code: typeof BAZAAR_TOTAL_LEVEL_TOO_LOW_CODE
  required: typeof BAZAAR_TOTAL_LEVEL_REQUIRED
  totalLevel: number
  error: typeof BAZAAR_TOTAL_LEVEL_TOO_LOW
}

export type BazaarSkillLevelInvalid = {
  ok: false
  code: typeof BAZAAR_SKILL_LEVEL_INVALID_CODE
  error: string
}

export type BazaarTotalLevelGate =
  | BazaarTotalLevelAllowed
  | BazaarTotalLevelRefused
  | BazaarSkillLevelInvalid

/** Whether [payload] may place a new Bazaar offer. */
export function bazaarTotalLevelGate(payload: Record<string, unknown>): BazaarTotalLevelGate {
  try {
    const totalLevel = totalLevelFromPayload(payload)
    if (totalLevel >= BAZAAR_TOTAL_LEVEL_REQUIRED) return { ok: true, totalLevel }
    return {
      ok: false,
      code: BAZAAR_TOTAL_LEVEL_TOO_LOW_CODE,
      required: BAZAAR_TOTAL_LEVEL_REQUIRED,
      totalLevel,
      error: BAZAAR_TOTAL_LEVEL_TOO_LOW,
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    if (message.startsWith(BAZAAR_SKILL_LEVEL_INVALID_CODE)) {
      return { ok: false, code: BAZAAR_SKILL_LEVEL_INVALID_CODE, error: message }
    }
    throw error
  }
}

/** Fields a `200 { ok: false }` Bazaar refusal carries for this gate. */
export function bazaarTotalLevelRefusalFields(
  gate: BazaarTotalLevelRefused,
): { code: string; required: number; totalLevel: number } {
  return { code: gate.code, required: gate.required, totalLevel: gate.totalLevel }
}
