/** Staff `/setage` parsing and failure audit, kept free of Deno so tests can drive it. */

import { staffBirthYearOk, STAFF_BIRTH_YEAR_ERROR } from './age.ts'
import type { DevAuditRow } from './dev_gate.ts'

export const SETAGE_USAGE = 'Usage: /setage <username> <year> [month]'
export const SETAGE_MONTH_ERROR = 'Enter a valid birth month.'
export const SETAGE_MISSING_PLAYER = 'That player could not be found.'

export type SetAgeParse =
  | { ok: true; username: string; year: number; month: number | null }
  | { ok: false; reason: string }

export function parseSetAgeTokens(tokens: string[], asOf: Date = new Date()): SetAgeParse {
  const username = tokens[0]?.trim() ?? ''
  const year = tokens[1] ? Number(tokens[1]) : Number.NaN
  const monthToken = tokens[2]?.trim() ?? ''
  const month = monthToken ? Number(monthToken) : null
  if (!username || !Number.isFinite(year)) return { ok: false, reason: SETAGE_USAGE }
  if (!staffBirthYearOk(year, asOf)) return { ok: false, reason: STAFF_BIRTH_YEAR_ERROR }
  if (monthToken && (!Number.isFinite(month) || month < 1 || month > 12)) {
    return { ok: false, reason: SETAGE_MONTH_ERROR }
  }
  return {
    ok: true,
    username,
    year,
    month: month != null && Number.isFinite(month) ? month : null,
  }
}

export function setAgeAuditRow(
  staffId: string,
  tokens: string[],
  reason: string,
  extra: Record<string, unknown> = {},
): DevAuditRow {
  return {
    user_id: staffId,
    command: 'setage',
    args: { tokens, ...extra },
    ok: false,
    reason,
  }
}
