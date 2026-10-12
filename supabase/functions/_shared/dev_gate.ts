// The developer_accounts gate in front of every `dev_command`, including the
// /abandonquest testing cheat. Kept free of Deno and supabase-js so the test
// suite can drive it with a fake lookup.

export const NOT_A_DEVELOPER = 'Not a developer account.'

export interface DevAuditRow {
  user_id: string
  command: string
  args: { tokens: string[] }
  ok: boolean
  reason: string
}

export interface DevGateDeps {
  /** Reads `developer_accounts` for the caller. */
  lookupDeveloper(userId: string): Promise<{ developer: boolean; error: string | null }>
  /** Writes one `developer_audit_log` row. */
  audit(row: DevAuditRow): Promise<void>
}

export type DevGateDecision = { ok: true } | { ok: false; status: 403 | 500; error: string }

/** Lets developers through; refuses everyone else with 403 and logs the attempt. */
export async function gateDevCommand(
  deps: DevGateDeps,
  userId: string,
  command: string,
  tokens: string[],
): Promise<DevGateDecision> {
  const { developer, error } = await deps.lookupDeveloper(userId)
  if (error) return { ok: false, status: 500, error }
  if (developer) return { ok: true }
  await deps.audit({ user_id: userId, command, args: { tokens }, ok: false, reason: NOT_A_DEVELOPER })
  return { ok: false, status: 403, error: NOT_A_DEVELOPER }
}
