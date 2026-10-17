/** Account deletion grace, restore, and purge helpers. */

export const DELETION_GRACE_DAYS = 14
export const DELETION_REAUTH_WINDOW_MS = 15 * 60 * 1000
export const STAFF_DELETE_BLOCKED = 'Staff accounts cannot be deleted this way.'
export const ACCOUNT_FROZEN = 'This account is scheduled for deletion.'
export const ACCOUNT_BEING_DELETED = 'This account is being deleted.'
export const NAME_CONFIRM_FAILED = 'Type your character name to confirm.'
export const REAUTH_REQUIRED = 'Sign in again to confirm.'
export const DELETED_PLAYER_LABEL = 'Deleted player'

export type DeletionStatus = 'pending' | 'restored' | 'data_purged' | 'purged'

export type DeletionRequestRow = {
  id: string
  user_id: string | null
  character_name: string
  requested_at: string
  purge_after: string
  status: DeletionStatus
  data_purged_at: string | null
}

export function namesMatch(typed: string, ...candidates: Array<string | null | undefined>): boolean {
  const want = typed.trim().toLowerCase()
  if (!want) return false
  return candidates.some((name) => (name ?? '').trim().toLowerCase() === want)
}

export function reauthIsFresh(lastSignInAt: string | null | undefined, nowMs: number): boolean {
  if (!lastSignInAt) return false
  const at = Date.parse(lastSignInAt)
  return Number.isFinite(at) && nowMs - at <= DELETION_REAUTH_WINDOW_MS
}

export function graceStillOpen(purgeAfter: string, nowMs: number): boolean {
  const at = Date.parse(purgeAfter)
  return Number.isFinite(at) && nowMs < at
}

export function isTradingFrozen(pending: boolean): boolean {
  return pending
}

export function anonymisedFeedbackPatch(): { username: string; context: Record<string, unknown> } {
  return { username: DELETED_PLAYER_LABEL, context: { anonymised: true } }
}

export function discordAnonymiseEmbedFields(): Array<{ name: string; value: string; inline?: boolean }> {
  return [
    { name: 'In-game name', value: DELETED_PLAYER_LABEL, inline: true },
    { name: 'Player id', value: '—', inline: true },
  ]
}
