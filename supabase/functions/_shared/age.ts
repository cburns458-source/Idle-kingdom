/** Chat age-gate helpers. Threshold is 13; age never blocks play. */

export const CHAT_AGE_THRESHOLD = 13
export const AGE_GATE_CODE = 'age_gate'
export const AGE_GATE_ERROR = 'Chat is not available for this account.'

export const STORE_AGE_BANDS = ['0-12', '13-15', '16-17', '18+'] as const
export type StoreAgeBand = (typeof STORE_AGE_BANDS)[number]
/** `store_signal` is stored for staff/legacy rows only. Clients cannot write it. */
export type AgeSource = 'self' | 'support' | 'store_signal'

export function isStoreAgeBand(value: string): value is StoreAgeBand {
  return (STORE_AGE_BANDS as readonly string[]).includes(value)
}

export function storeBandAllowsChat(band: string): boolean {
  return band === '13-15' || band === '16-17' || band === '18+'
}

/** Years old on [asOf], or null when the year is missing. Birthday is last day of the month. */
export function accountAgeYears(
  birthYear: number | null | undefined,
  birthMonth: number | null | undefined,
  asOf: Date = new Date(),
): number | null {
  if (birthYear == null || !Number.isFinite(birthYear)) return null
  const month = birthMonth == null ? 12 : birthMonth
  let years = asOf.getUTCFullYear() - birthYear
  // Day 0 of the next month is the last day of [month] in the as-of year.
  const anniversary = new Date(Date.UTC(asOf.getUTCFullYear(), month, 0))
  if (asOf.getTime() < anniversary.getTime()) years -= 1
  return years
}

export function ageBandFromYears(years: number | null): string {
  if (years == null) return 'unknown'
  if (years < 13) return '0-12'
  if (years < 16) return '13-15'
  if (years < 18) return '16-17'
  return '18+'
}

export function chatAllowedFromAge(input: {
  answered: boolean
  birthYear?: number | null
  birthMonth?: number | null
  ageBand?: string | null
  asOf?: Date
}): boolean {
  if (!input.answered) return false
  if (input.birthYear != null) {
    const years = accountAgeYears(input.birthYear, input.birthMonth, input.asOf)
    return (years ?? 0) >= CHAT_AGE_THRESHOLD
  }
  return storeBandAllowsChat(input.ageBand ?? '')
}

/** True only when the year alone cannot settle whether they are 13 yet. */
export function needsBirthMonth(birthYear: number, asOf: Date = new Date()): boolean {
  return asOf.getUTCFullYear() - birthYear === CHAT_AGE_THRESHOLD
}

export function ageGateResponse(allowed: boolean): { status: 403; error: string; code: string } | null {
  if (allowed) return null
  return { status: 403, error: AGE_GATE_ERROR, code: AGE_GATE_CODE }
}

export const STAFF_BIRTH_YEAR_MIN = 1900
export const STAFF_BIRTH_YEAR_ERROR = 'Enter a valid birth year.'

/** Staff `/setage` years must be real and not in the future. */
export function staffBirthYearOk(year: number, asOf: Date = new Date()): boolean {
  return Number.isFinite(year) && year >= STAFF_BIRTH_YEAR_MIN && year <= asOf.getUTCFullYear()
}
