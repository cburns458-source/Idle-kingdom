// Hosted mass-boss payout claim. Kept free of Deno and game_rules so tests can
// drive a fake admin. The RPC writes player_saves and payout_claimed together.

export const MASS_CLAIM_PAYOUT_RPC = 'mass_claim_payout'
export const MASS_CLAIM_SAVE_CONFLICT = 'Save version conflict. Sync and retry.'

export type MassClaimRpcResult = { data: unknown; error: { message: string } | null }

export type MassClaimRpcAdmin = {
  rpc: (fn: string, args: Record<string, unknown>) => PromiseLike<MassClaimRpcResult>
}

export type MassClaimPersistResult =
  | { kind: 'closed' }
  | { kind: 'failed'; error: string; status: number; conflict?: boolean }
  | {
      kind: 'ok'
      version: number
      alreadyClaimed: boolean
      eligible: boolean
      payload: unknown
    }

export async function persistMassClaim(options: {
  admin: MassClaimRpcAdmin
  userId: string
  encounterId: string
  expectedVersion: number
  payload: unknown
  rngState: number
  nowMs: number
}): Promise<MassClaimPersistResult> {
  const result = await Promise.resolve(
    options.admin.rpc(MASS_CLAIM_PAYOUT_RPC, {
      p_user_id: options.userId,
      p_encounter_id: options.encounterId,
      p_expected_version: options.expectedVersion,
      p_payload: options.payload,
      p_rng_state: options.rngState,
      p_now: new Date(options.nowMs).toISOString(),
    }),
  )
  if (result.error) return { kind: 'failed', error: result.error.message, status: 500 }
  const answer =
    result.data && typeof result.data === 'object' ? (result.data as Record<string, unknown>) : {}
  if (answer.closed === true) return { kind: 'closed' }
  if (answer.ok !== true) {
    const conflict = answer.conflict === true
    return {
      kind: 'failed',
      error: typeof answer.reason === 'string' ? answer.reason : MASS_CLAIM_SAVE_CONFLICT,
      status: conflict ? 409 : 400,
      conflict,
    }
  }
  return {
    kind: 'ok',
    version: Number(answer.version ?? options.expectedVersion + 1),
    alreadyClaimed: answer.alreadyClaimed === true,
    eligible: answer.eligible === true,
    payload: answer.payload ?? options.payload,
  }
}
