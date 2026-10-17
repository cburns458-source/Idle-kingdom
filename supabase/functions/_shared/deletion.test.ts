import { describe, expect, it } from 'vitest'

import {
  ACCOUNT_FROZEN,
  DELETION_GRACE_DAYS,
  NAME_CONFIRM_FAILED,
  STAFF_DELETE_BLOCKED,
  anonymisedFeedbackPatch,
  graceStillOpen,
  isTradingFrozen,
  namesMatch,
  reauthIsFresh,
} from './deletion.ts'

describe('account deletion helpers', () => {
  it('uses a 14-day grace and restores only before purge_after', () => {
    expect(DELETION_GRACE_DAYS).toBe(14)
    const now = Date.parse('2026-10-17T00:00:00.000Z')
    expect(graceStillOpen('2026-10-31T00:00:00.000Z', now)).toBe(true)
    expect(graceStillOpen('2026-10-17T00:00:00.000Z', now)).toBe(false)
  })

  it('confirms the character name case-insensitively', () => {
    expect(namesMatch('Hero', 'hero', 'Heroine')).toBe(true)
    expect(namesMatch('  HERO  ', 'hero')).toBe(true)
    expect(namesMatch('Other', 'hero')).toBe(false)
    expect(namesMatch('', 'hero')).toBe(false)
    expect(NAME_CONFIRM_FAILED).toContain('character name')
  })

  it('requires a fresh re-auth and freezes trading while pending', () => {
    const now = Date.parse('2026-10-17T12:00:00.000Z')
    expect(reauthIsFresh('2026-10-17T11:50:00.000Z', now)).toBe(true)
    expect(reauthIsFresh('2026-10-17T11:00:00.000Z', now)).toBe(false)
    expect(isTradingFrozen(true)).toBe(true)
    expect(isTradingFrozen(false)).toBe(false)
    expect(ACCOUNT_FROZEN).toMatch(/deletion/)
    expect(STAFF_DELETE_BLOCKED).toMatch(/Staff/)
  })

  it('anonymises feedback copy for Discord edits', () => {
    const patch = anonymisedFeedbackPatch()
    expect(patch.username).toBe('Deleted player')
    expect(patch.context.anonymised).toBe(true)
  })
})
